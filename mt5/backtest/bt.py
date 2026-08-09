#!/usr/bin/env python3
"""
Bar-by-bar simulator replicating the exact order logic of:
  A) XAU_StraddleReverse_v4_4.mq5   (SAR v4)
  B) XAUUSD_Straddle_Scalper_TH_v3_1.mq5

Data: XAUUSD M1 OHLC + per-bar spread.
Intrabar model = MT5 "1 minute OHLC" tick generation:
    bullish bar (C>=O): O -> L -> H -> C
    bearish bar (C< O): O -> H -> L -> C
Within each segment price moves monotonically; every order level crossed
inside the segment is executed in the order it is reached.
If SL and TP fall inside the same segment, SL wins (pessimistic).

All CSV prices treated as BID. ASK = BID + spread*point.
"""
import csv, datetime, math, sys, random
from dataclasses import dataclass, field

POINT       = 0.01
DIGITS      = 2
CONTRACT    = 100.0          # oz per lot
TICK_VALUE  = 1.0            # $ per point per lot  (100 oz * 0.01)
STOPS_LEVEL = 0              # broker min stop distance, in points
LOT_STEP    = 0.01
LOT_MIN     = 0.01
LOT_MAX     = 100.0
SERVER_GMT  = 3              # broker server offset assumption (Thai = server + 4h)

CSV = '/root/.claude/uploads/8a5f5bb8-2cd3-5a59-922c-8f14f2bb5c4a/d4805bf5-XAUUSDVIP_M1_202607010100_202607072151.csv'


def load():
    bars = []
    with open(CSV) as f:
        for r in csv.DictReader(f, delimiter='\t'):
            t = datetime.datetime.strptime(r['<DATE>'] + ' ' + r['<TIME>'], '%Y.%m.%d %H:%M:%S')
            bars.append(dict(t=t, o=float(r['<OPEN>']), h=float(r['<HIGH>']),
                             l=float(r['<LOW>']), c=float(r['<CLOSE>']),
                             sp=int(r['<SPREAD>']), tv=int(r['<TICKVOL>'])))
    return bars


def norm(p):
    return round(p, DIGITS)


# ----------------------------------------------------------------------------
@dataclass
class Position:
    typ: str            # 'buy' | 'sell'
    lots: float
    open_price: float
    sl: float
    tp: float
    open_time: datetime.datetime
    state: str = 'open'          # used by EA-B state machine
    opened_bar: int = 0


@dataclass
class Pending:
    typ: str            # 'buystop' | 'sellstop'
    lots: float
    price: float
    sl: float
    tp: float


@dataclass
class Trade:
    typ: str
    lots: float
    entry: float
    exit: float
    open_time: datetime.datetime
    close_time: datetime.datetime
    reason: str
    pl: float
    pts: float


class Broker:
    """Holds account state + executes fills. Shared by both EAs."""

    def __init__(self, balance, commission_per_lot_side=0.0):
        self.balance = balance
        self.equity = balance
        self.start = balance
        self.pos = None
        self.pend = []           # list[Pending]
        self.trades = []
        self.comm = commission_per_lot_side
        self.peak = balance
        self.max_dd = 0.0
        self.max_dd_pct = 0.0
        self.eq_curve = []
        self.blown = False
        self.day_pl = {}

    # --- fills -------------------------------------------------------------
    def open_from_pending(self, p, price, t, bar_i):
        self.pos = Position(
            typ='buy' if p.typ == 'buystop' else 'sell',
            lots=p.lots, open_price=price, sl=p.sl, tp=p.tp,
            open_time=t, state='open', opened_bar=bar_i)
        self.balance -= self.comm * p.lots      # entry commission

    def close(self, price, t, reason):
        p = self.pos
        if p is None:
            return
        pts = (price - p.open_price) / POINT if p.typ == 'buy' else (p.open_price - price) / POINT
        gross = pts * TICK_VALUE * p.lots
        self.balance += gross - self.comm * p.lots
        net = gross - 2 * self.comm * p.lots
        self.trades.append(Trade(p.typ, p.lots, p.open_price, price, p.open_time, t,
                                 reason, net, pts))
        self.day_pl[t.date()] = self.day_pl.get(t.date(), 0.0) + net
        self.pos = None
        if self.balance <= 0:
            self.blown = True

    def floating(self, bid, ask):
        if self.pos is None:
            return 0.0
        p = self.pos
        px = bid if p.typ == 'buy' else ask
        pts = (px - p.open_price) / POINT if p.typ == 'buy' else (p.open_price - px) / POINT
        return pts * TICK_VALUE * p.lots

    def mark(self, bid, ask, t):
        eq = self.balance + self.floating(bid, ask)
        self.equity = eq
        if eq > self.peak:
            self.peak = eq
        dd = self.peak - eq
        if dd > self.max_dd:
            self.max_dd = dd
            self.max_dd_pct = dd / self.peak * 100 if self.peak > 0 else 0
        self.eq_curve.append((t, eq))


def round_lot(lot, cap=None):
    lot = math.floor(lot / LOT_STEP) * LOT_STEP
    hi = LOT_MAX if cap is None else min(cap, LOT_MAX)
    lot = max(LOT_MIN, min(hi, lot))
    return round(lot, 2)


# ============================================================================
#  EA A — XAU_StraddleReverse_v4_2
# ============================================================================
class EA_A:
    name = 'A: XAU_StraddleReverse_v4.2'

    def __init__(self, bk, **kw):
        self.bk = bk
        # inputs (USD units -> points)
        self.straddle = kw.get('straddle', 0.50)
        self.sl       = kw.get('sl', 1.50)
        self.tp       = kw.get('tp', 10.00)
        self.use_be   = kw.get('use_be', True)
        self.be_start = kw.get('be_start', 0.80)
        self.be_lock  = kw.get('be_lock', 0.20)
        self.use_tr   = kw.get('use_tr', True)
        self.tr_start = kw.get('tr_start', 1.50)
        self.tr_dist  = kw.get('tr_dist', 1.00)
        self.use_rev  = kw.get('use_rev', True)
        self.rev_start= kw.get('rev_start', 1.00)
        self.rev_gap  = kw.get('rev_gap', 1.20)
        self.use_cd   = kw.get('use_cd', True)
        self.cd_sec   = kw.get('cd_sec', 60)
        self.cd_kill  = True
        self.max_sl_day = kw.get('max_sl_day', 0)
        self.use_time = kw.get('use_time', True)
        self.sessions = [(7*60, 8*60+30), (19*60, 20*60+30), (2*60, 3*60+30)]
        self.close_at_end = False
        self.lot_mode = kw.get('lot_mode', 'auto')
        self.risk     = kw.get('risk', 1.0)
        self.fixed    = kw.get('fixed', 0.01)
        self.max_lot  = kw.get('max_lot', 0.50)
        self.max_spread = kw.get('max_spread', 0.60)
        # state
        self.cooldown_until = None
        self.last_place_try = None
        self.sl_today = 0
        self.day = None
        self.flips = 0
        self.rev_fires = 0
        self.reason_hist = {}

    # helpers
    def pts(self, usd):
        return 0 if usd <= 0 else int(round(usd / POINT))

    def in_session(self, t):
        if not self.use_time:
            return True
        thai = (t.hour * 60 + t.minute) + (7 - SERVER_GMT) * 60
        thai %= 1440
        for s, e in self.sessions:
            if (s <= e and s <= thai < e) or (s > e and (thai >= s or thai < e)):
                return True
        return False

    def calc_lot(self):
        if self.lot_mode == 'fixed':
            return round_lot(self.fixed, self.max_lot)
        risk_money = self.bk.balance * self.risk / 100.0
        loss_per_lot = self.pts(self.sl) * TICK_VALUE
        lot = risk_money / loss_per_lot if loss_per_lot > 0 else self.fixed
        return round_lot(lot, self.max_lot)

    # ------------------------------------------------------------------
    def place_straddle(self, bid, ask):
        lot = self.calc_lot()
        d = max(self.pts(self.straddle), STOPS_LEVEL) * POINT
        slp, tpp = self.pts(self.sl), self.pts(self.tp)
        bp = norm(ask + d)
        sp = norm(bid - d)
        self.bk.pend = [
            Pending('buystop', lot, bp,
                    norm(bp - slp * POINT) if slp else 0.0,
                    norm(bp + tpp * POINT) if tpp else 0.0),
            Pending('sellstop', lot, sp,
                    norm(sp + slp * POINT) if slp else 0.0,
                    norm(sp - tpp * POINT) if tpp else 0.0),
        ]

    def on_fill(self, reason):
        """called by engine right after a position closes"""
        self.reason_hist[reason] = self.reason_hist.get(reason, 0) + 1
        if reason == 'sl':
            self.sl_today += 1
            if self.use_cd:
                self.cooldown_until = self.now + datetime.timedelta(seconds=self.cd_sec)

    # ------------------------------------------------------------------
    def tick(self, t, bid, ask, newbar):
        self.now = t
        bk = self.bk
        if self.day != t.date():
            self.day = t.date()
            self.sl_today = 0

        spread_pts = (ask - bid) / POINT
        cooling = self.use_cd and self.cooldown_until and t < self.cooldown_until
        day_hit = self.max_sl_day > 0 and self.sl_today >= self.max_sl_day
        insess = self.in_session(t)

        if bk.pos is None:
            if cooling or day_hit:
                if self.cd_kill and bk.pend:
                    bk.pend = []
                return
            if not insess:
                bk.pend = []
                return
            if len(bk.pend) >= 2:
                return
            if len(bk.pend) == 1:
                bk.pend = []
            if spread_pts > self.pts(self.max_spread):
                return
            if self.last_place_try and (t - self.last_place_try).total_seconds() < 2:
                return
            self.last_place_try = t
            self.place_straddle(bid, ask)
            return

        # --- one position open
        p = bk.pos
        if not insess and self.close_at_end:
            bk.pend = []
            return 'close'

        # ManageStops
        prof = (bid - p.open_price) / POINT if p.typ == 'buy' else (p.open_price - ask) / POINT
        new_sl = 0.0
        if self.use_tr and prof >= self.pts(self.tr_start):
            new_sl = (bid - self.pts(self.tr_dist) * POINT) if p.typ == 'buy' \
                else (ask + self.pts(self.tr_dist) * POINT)
        elif self.use_be and prof >= self.pts(self.be_start):
            new_sl = (p.open_price + self.pts(self.be_lock) * POINT) if p.typ == 'buy' \
                else (p.open_price - self.pts(self.be_lock) * POINT)
        if new_sl:
            minD = STOPS_LEVEL * POINT
            ok = (new_sl <= bid - minD) if p.typ == 'buy' else (new_sl >= ask + minD)
            if ok:
                new_sl = norm(new_sl)
                improve = (p.sl == 0 or new_sl > p.sl + POINT * .5) if p.typ == 'buy' \
                    else (p.sl == 0 or new_sl < p.sl - POINT * .5)
                if improve:
                    p.sl = new_sl

        # drop same-side pending
        bk.pend = [q for q in bk.pend
                   if not ((p.typ == 'buy' and q.typ == 'buystop') or
                           (p.typ == 'sell' and q.typ == 'sellstop'))]

        if not self.use_rev:
            return
        gap = max(self.pts(self.rev_gap), STOPS_LEVEL) * POINT
        minD = STOPS_LEVEL * POINT
        slp, tpp = self.pts(self.sl), self.pts(self.tp)

        if not bk.pend:
            if prof >= self.pts(self.rev_start):
                if spread_pts > self.pts(self.max_spread):
                    return
                lot = self.calc_lot()
                if p.typ == 'buy':
                    pr = norm(bid - gap)
                    bk.pend = [Pending('sellstop', lot, pr,
                                       norm(pr + slp * POINT) if slp else 0.0,
                                       norm(pr - tpp * POINT) if tpp else 0.0)]
                else:
                    pr = norm(ask + gap)
                    bk.pend = [Pending('buystop', lot, pr,
                                       norm(pr - slp * POINT) if slp else 0.0,
                                       norm(pr + tpp * POINT) if tpp else 0.0)]
            return

        q = bk.pend[0]
        if p.typ == 'buy' and q.typ == 'sellstop':
            np_ = norm(bid - gap)
            if np_ > q.price + POINT * .5 and np_ < bid - minD:
                q.price = np_
                q.sl = norm(np_ + slp * POINT) if slp else 0.0
                q.tp = norm(np_ - tpp * POINT) if tpp else 0.0
        elif p.typ == 'sell' and q.typ == 'buystop':
            np_ = norm(ask + gap)
            if np_ < q.price - POINT * .5 and np_ > ask + minD:
                q.price = np_
                q.sl = norm(np_ - slp * POINT) if slp else 0.0
                q.tp = norm(np_ + tpp * POINT) if tpp else 0.0


# ============================================================================
#  EA B — XAUUSD_Straddle_Scalper_TH_v3
# ============================================================================
class EA_B:
    name = 'B: XAUUSD_Straddle_Scalper_TH v3'

    def __init__(self, bk, **kw):
        self.bk = bk
        self.d_buy   = kw.get('d_buy', 100)
        self.d_sell  = kw.get('d_sell', 100)
        self.sl      = kw.get('sl', 250)
        self.tp      = kw.get('tp', 1000)
        self.ts_min  = kw.get('ts_min', 0)
        self.ts_pts  = kw.get('ts_pts', 30)
        self.use_time= kw.get('use_time', False)
        self.sessions= [(7*60, 8*60+30), (19*60, 20*60+30), (2*60, 3*60+30)]
        self.close_end = True
        self.grace   = 0
        self.be_trig = kw.get('be_trig', 60)
        self.be_off  = kw.get('be_off', 30)
        self.lock_gap= kw.get('lock_gap', 100)
        self.tr_buf  = kw.get('tr_buf', 50)
        self.sp_comp = kw.get('sp_comp', 30)
        self.auto_lot= kw.get('auto_lot', True)
        self.risk    = kw.get('risk', 5.0)
        self.fixed   = kw.get('fixed', 0.01)
        self.max_lot = kw.get('max_lot', None)      # EA has NO cap
        self.max_spread = kw.get('max_spread', 50)
        self.use_dloss = kw.get('use_dloss', False)
        self.dloss_pct = kw.get('dloss_pct', 5.0)
        self.use_dprof = kw.get('use_dprof', False)
        self.dprof_pct = kw.get('dprof_pct', 5.0)
        self.max_trades_day = kw.get('max_trades_day', 0)   # 0 = unlimited
        self.cooldown_sec   = kw.get('cooldown_sec', 0)     # gap after a closed trade
        # state
        self.state = 'idle'
        self.last_candle = None
        self.halt_day = None
        self.day_net = 0.0
        self.day = None
        self.reason_hist = {}
        self.prev_low = None
        self.prev_high = None

    def in_session(self, t):
        if not self.use_time:
            return True
        thai = (t.hour * 60 + t.minute) + (7 - SERVER_GMT) * 60
        thai %= 1440
        for s, e in self.sessions:
            if (s <= e and s <= thai < e) or (s > e and (thai >= s or thai < e)):
                return True
        return False

    def calc_lot(self):
        if not self.auto_lot:
            lot = self.fixed
        else:
            risk_money = self.bk.balance * self.risk / 100.0
            loss_per_lot = self.sl * TICK_VALUE
            lot = risk_money / loss_per_lot
        return round_lot(lot, self.max_lot)

    def on_fill(self, reason):
        self.reason_hist[reason] = self.reason_hist.get(reason, 0) + 1
        self.state = 'idle'

    def tick(self, t, bid, ask, newbar):
        bk = self.bk
        t2 = t
        if self.day != t.date():
            self.day = t.date()
            self.day_net = 0.0
            self.halt_day = None

        # day stats: net closed pnl today (running total maintained by broker)
        self.day_net = bk.day_pl.get(t.date(), 0.0)
        today = self.day_net + bk.floating(bid, ask)

        if self.halt_day is None:
            if self.use_dloss and today <= -bk.balance * self.dloss_pct / 100.0:
                self.halt_day = t.date()
            elif self.use_dprof and today >= bk.balance * self.dprof_pct / 100.0:
                self.halt_day = t.date()

        pend = len(bk.pend)
        has = bk.pos is not None
        if has and pend:
            bk.pend = []
            pend = 0

        if self.halt_day == t.date():
            bk.pend = []
            if has:
                return 'close'
            self.state = 'idle'
            return

        if self.use_time and not self.in_session(t):
            bk.pend = []
            if has:
                if self.close_end:
                    return 'close'
                self.manage(t, bid, ask, newbar)
                return
            self.state = 'idle'
            return

        if has:
            if self.state in ('idle', 'pending'):
                self.state = 'pos_open'
                self.last_candle = t.replace(second=0)
            return self.manage(t, bid, ask, newbar)

        if pend >= 2:
            self.state = 'pending'
            return
        if pend == 1:
            bk.pend = []

        self.state = 'idle'

        # --- frequency controls: commission is the dominant cost on a small account
        if self.max_trades_day > 0:
            done = sum(1 for t in bk.trades if t.close_time.date() == t2.date())
            if done >= self.max_trades_day:
                return
        if self.cooldown_sec > 0 and bk.trades:
            last = bk.trades[-1].close_time
            if (t2 - last).total_seconds() < self.cooldown_sec:
                return

        # PlaceStraddle
        spread_pts = (ask - bid) / POINT
        if spread_pts > self.max_spread:
            return
        minstop = STOPS_LEVEL * POINT
        db = max(self.d_buy * POINT, minstop + POINT)
        ds = max(self.d_sell * POINT, minstop + POINT)
        bp, sp = norm(ask + db), norm(bid - ds)
        lot = self.calc_lot()
        if lot <= 0:
            return
        bk.pend = [
            Pending('buystop', lot, bp, norm(bp - self.sl * POINT),
                    norm(bp + self.tp * POINT) if self.tp else 0.0),
            Pending('sellstop', lot, sp, norm(sp + self.sl * POINT),
                    norm(sp - self.tp * POINT) if self.tp else 0.0),
        ]
        self.state = 'pending'

    # ------------------------------------------------------------------
    def manage(self, t, bid, ask, newbar):
        p = self.bk.pos
        prof = (bid - p.open_price) / POINT if p.typ == 'buy' else (p.open_price - ask) / POINT

        if self.ts_min > 0:
            mins = (t - p.open_time).total_seconds() / 60
            if mins >= self.ts_min and prof < self.ts_pts:
                return 'close_ts'

        be = norm(p.open_price + self.be_off * POINT) if p.typ == 'buy' \
            else norm(p.open_price - self.be_off * POINT)

        if prof >= self.be_trig:
            minstop = STOPS_LEVEL * POINT
            need = (p.sl < be) if p.typ == 'buy' else (p.sl > be or p.sl == 0)
            okbrk = (be < bid - minstop) if p.typ == 'buy' else (be > ask + minstop)
            if need and okbrk:
                p.sl = be
                if self.state == 'pos_open':
                    self.state = 'be_set'
            elif not need and self.state == 'pos_open':
                self.state = 'be_set'

            spread_now = (ask - bid) / POINT
            if p.typ == 'buy':
                lock = norm(bid - self.lock_gap * POINT)
                if lock < be:
                    lock = be
                if self.state != 'pos_open' and lock > p.sl:
                    p.sl = lock
            else:
                lock = norm(ask + (self.lock_gap + max(self.sp_comp, spread_now)) * POINT)
                if lock > be:
                    lock = be
                if self.state != 'pos_open' and (lock < p.sl or p.sl == 0):
                    p.sl = lock

        # candle trailing, once per new bar
        if not newbar:
            return
        if self.state not in ('be_set', 'trailing'):
            return
        self.state = 'trailing'
        if self.prev_low is None:
            return
        spread_comp = max(self.sp_comp, (ask - bid) / POINT)
        minstop = STOPS_LEVEL * POINT
        if p.typ == 'buy':
            new = norm(self.prev_low - self.tr_buf * POINT)
            if new < be:
                new = be
            if new > p.sl and new < bid - minstop:
                p.sl = new
        else:
            new = norm(self.prev_high + (self.tr_buf + spread_comp) * POINT)
            if new > be:
                new = be
            if (new < p.sl or p.sl == 0) and new > ask + minstop:
                p.sl = new


# ============================================================================
#  Engine
# ============================================================================
def run(ea_cls, bars, balance=10000.0, commission=0.0, seed=1,
        slip_pts=0.0, noise=0.28, **kw):
    """slip_pts = adverse slippage in points applied to stop-order entries
    and stop-loss exits (market-order style fills)."""
    import path as pathmod
    rng = random.Random(seed)
    bk = Broker(balance, commission)
    ea = ea_cls(bk, **kw)
    prev_low = prev_high = None
    slip = slip_pts * POINT
    ONEMIN = datetime.timedelta(seconds=60)

    for i, b in enumerate(bars):
        spread = b['sp'] * POINT
        if hasattr(ea, 'prev_low'):
            ea.prev_low, ea.prev_high = prev_low, prev_high

        pts_path = pathmod.bar_path(b['o'], b['h'], b['l'], b['c'], b.get('tv', 60), rng, noise=noise)
        npts = len(pts_path)
        t0 = b['t']

        for si in range(npts - 1):
            a, z = pts_path[si], pts_path[si + 1]
            tnow = t0 + ONEMIN * (si / max(1, npts - 1))
            cur = a
            guard = 0
            while True:
                guard += 1
                if guard > 40:
                    cur = z
                    break
                lvl, kind = next_level(bk, cur, z, spread)
                if lvl is None:
                    cur = z
                    break
                cur = lvl
                bid, ask = cur, cur + spread
                if kind == 'sl':
                    px = bk.pos.sl + (-slip if bk.pos.typ == 'buy' else slip)
                    bk.close(px, tnow, 'sl')
                    ea.on_fill('sl')
                    if isinstance(ea, EA_A) and ea.use_cd:
                        bk.pend = []
                elif kind == 'tp':
                    bk.close(bk.pos.tp, tnow, 'tp')
                    ea.on_fill('tp')
                elif kind in ('buystop', 'sellstop'):
                    q = [x for x in bk.pend if x.typ == kind][0]
                    if bk.pos is not None:
                        bk.close(bid if bk.pos.typ == 'buy' else ask, tnow, 'reverse')
                        ea.on_fill('reverse')
                        if isinstance(ea, EA_A):
                            ea.flips += 1
                            ea.rev_fires += 1
                    bk.pend = []
                    fill = q.price + (slip if q.typ == 'buystop' else -slip)
                    q2 = Pending(q.typ, q.lots, fill, q.sl, q.tp)
                    bk.open_from_pending(q2, fill, tnow, i)

            bid, ask = cur, cur + spread
            r = ea.tick(tnow, bid, ask, si == 0)
            if r in ('close', 'close_ts') and bk.pos is not None:
                px = bid if bk.pos.typ == 'buy' else ask
                bk.close(px, tnow, 'session' if r == 'close' else 'timestop')
                ea.on_fill('session' if r == 'close' else 'timestop')
            if bk.blown:
                break
        bk.mark(cur, cur + spread, b['t'])
        prev_low, prev_high = b['l'], b['h']
        if bk.blown:
            break
    return bk, ea


def next_level(bk, cur, target, spread):
    """First actionable price level strictly between cur and target (bid terms)."""
    up = target > cur
    cands = []
    if bk.pos is not None:
        p = bk.pos
        if p.typ == 'buy':
            if p.sl:
                cands.append((p.sl, 'sl', False))            # bid <= sl
            if p.tp:
                cands.append((p.tp, 'tp', True))             # bid >= tp
        else:
            if p.sl:
                cands.append((p.sl - spread, 'sl', True))    # ask >= sl
            if p.tp:
                cands.append((p.tp - spread, 'tp', False))   # ask <= tp
    for q in bk.pend:
        if q.typ == 'buystop':
            cands.append((q.price - spread, 'buystop', True))   # ask >= price
        else:
            cands.append((q.price, 'sellstop', False))          # bid <= price

    best = None
    for lvl, kind, need_up in cands:
        if need_up != up:
            continue
        if up and cur < lvl <= target:
            if best is None or lvl < best[0] or (lvl == best[0] and kind == 'sl'):
                best = (lvl, kind)
        elif (not up) and target <= lvl < cur:
            if best is None or lvl > best[0] or (lvl == best[0] and kind == 'sl'):
                best = (lvl, kind)
    if best is None:
        return None, None
    # pessimistic: if an SL sits at the same distance as a TP, SL first
    lvl, kind = best
    for l2, k2, nu in cands:
        if k2 == 'sl' and nu == up and abs(l2 - lvl) < 1e-9:
            kind = 'sl'
    return lvl, kind


# ----------------------------------------------------------------------------
def exit_breakdown(bk):
    d = {}
    for t in bk.trades:
        k = t.reason + ('+' if t.pl > 0 else '-')
        d[k] = d.get(k, 0) + 1
    return d


def stats(bk, ea, label):
    tr = bk.trades
    n = len(tr)
    wins = [t for t in tr if t.pl > 0]
    loss = [t for t in tr if t.pl <= 0]
    gp = sum(t.pl for t in wins)
    gl = -sum(t.pl for t in loss)
    net = bk.balance - bk.start
    pf = (gp / gl) if gl > 0 else float('inf')
    avgw = gp / len(wins) if wins else 0
    avgl = gl / len(loss) if loss else 0
    # consecutive losses
    mc = c = 0
    for t in tr:
        if t.pl <= 0:
            c += 1
            mc = max(mc, c)
        else:
            c = 0
    d = dict(label=label, n=n, net=net, ret=net / bk.start * 100,
             win=len(wins), lose=len(loss),
             wr=len(wins) / n * 100 if n else 0,
             pf=pf, gp=gp, gl=gl, avgw=avgw, avgl=avgl,
             dd=bk.max_dd, ddp=bk.max_dd_pct, maxcl=mc,
             end=bk.balance, blown=bk.blown,
             reasons=exit_breakdown(bk),
             best=max((t.pl for t in tr), default=0),
             worst=min((t.pl for t in tr), default=0),
             avg_pts=sum(t.pts for t in tr) / n if n else 0,
             net_pts=sum(t.pts for t in tr))
    return d


def show(d):
    print(f"\n{'='*74}\n{d['label']}\n{'='*74}")
    print(f"  Net P/L            : {d['net']:+,.2f} USD   ({d['ret']:+.2f}%)")
    print(f"  Ending balance     : {d['end']:,.2f}" + ("   *** ACCOUNT BLOWN ***" if d['blown'] else ""))
    print(f"  Total trades       : {d['n']}")
    print(f"  Win / Loss         : {d['win']} / {d['lose']}   (win rate {d['wr']:.1f}%)")
    print(f"  Gross profit/loss  : {d['gp']:,.2f} / -{d['gl']:,.2f}")
    print(f"  Profit factor      : {d['pf']:.3f}")
    print(f"  Avg win / avg loss : {d['avgw']:,.2f} / -{d['avgl']:,.2f}")
    print(f"  Best / worst trade : {d['best']:+,.2f} / {d['worst']:+,.2f}")
    print(f"  Max drawdown       : {d['dd']:,.2f}  ({d['ddp']:.2f}%)")
    print(f"  Max consec losses  : {d['maxcl']}")
    print(f"  Net points         : {d['net_pts']:+,.0f}  (avg {d['avg_pts']:+.1f} pts/trade)")
    print(f"  Exit reasons       : {d['reasons']}")


if __name__ == '__main__':
    bars = load()
    print(f"Bars: {len(bars)}  {bars[0]['t']} -> {bars[-1]['t']}")
