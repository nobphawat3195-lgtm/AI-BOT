"""EA_C - replicates XAU_StraddleCore_v1.mq5 logic for validation."""
import datetime
from bt import POINT, TICK_VALUE, STOPS_LEVEL, SERVER_GMT, norm, round_lot, Pending

class EA_C:
    name = 'C: XAU_StraddleCore v1'
    def __init__(self, bk, **kw):
        self.bk=bk
        self.entry   = kw.get('entry', 0.50)
        self.sl      = kw.get('sl', 1.50)
        self.tp      = kw.get('tp', 0.0)
        self.be_start= kw.get('be_start', 0.60)
        self.be_lock = kw.get('be_lock', 0.30)
        self.lock_gap= kw.get('lock_gap', 1.00)
        self.use_ct  = kw.get('use_ct', True)
        self.ct_buf  = kw.get('ct_buf', 0.50)
        self.max_day = kw.get('max_day', 100)
        self.cd_sl   = kw.get('cd_sl', 60)
        self.min_gap = kw.get('min_gap', 0)
        self.use_time= kw.get('use_time', True)
        self.sessions=[(7*60,8*60+30),(19*60,20*60+30),(2*60,3*60+30)]
        self.close_end=kw.get('close_end', True)
        self.lot_mode= kw.get('lot_mode','fixed')
        self.fixed   = kw.get('fixed', 0.01)
        self.risk    = kw.get('risk', 1.0)
        self.max_lot = kw.get('max_lot', 0.10)
        self.max_spread=kw.get('max_spread', 0.50)
        self.use_dl  = kw.get('use_dl', True)
        self.dl_pct  = kw.get('dl_pct', 5.0)
        # state
        self.be_done=False; self.last_candle=None; self.cd_till=None
        self.last_close=None; self.halt_day=None; self.day=None
        self.reason_hist={}; self.prev_low=None; self.prev_high=None
    def minstop(self): return STOPS_LEVEL*POINT
    def eff_sl(self):
        return max(self.sl, self.minstop()) if self.sl>0 else 0.0
    def in_session(self,t):
        if not self.use_time: return True
        m=((t.hour*60+t.minute)+(7-SERVER_GMT)*60)%1440
        return any((s<=e and s<=m<e) or (s>e and (m>=s or m<e)) for s,e in self.sessions)
    def calc_lot(self):
        if self.lot_mode=='fixed': lot=self.fixed
        else:
            slp=self.eff_sl()
            if slp<=0: return 0
            lot=(self.bk.balance*self.risk/100.0)/((slp/POINT)*TICK_VALUE)
        return round_lot(lot, self.max_lot)
    def on_fill(self, reason):
        self.reason_hist[reason]=self.reason_hist.get(reason,0)+1
        self.be_done=False; self.last_close=self.now
        if reason=='sl' and self.cd_sl>0:
            self.cd_till=self.now+datetime.timedelta(seconds=self.cd_sl)
    def tick(self,t,bid,ask,newbar):
        self.now=t; bk=self.bk
        if self.day!=t.date(): self.day=t.date(); self.halt_day=None
        has = bk.pos is not None
        if has and bk.pend: bk.pend=[]
        if not has: self.be_done=False

        day_net=bk.day_pl.get(t.date(),0.0)+bk.floating(bid,ask)
        if self.halt_day is None and self.use_dl and day_net<=-bk.balance*self.dl_pct/100.0:
            self.halt_day=t.date()
        if self.halt_day==t.date():
            bk.pend=[]
            return 'close' if has else None
        if not self.in_session(t):
            bk.pend=[]
            if has: return 'close' if self.close_end else self.manage(t,bid,ask,newbar)
            return
        if has: return self.manage(t,bid,ask,newbar)

        done=sum(1 for x in bk.trades if x.close_time.date()==t.date())
        if self.max_day>0 and done>=self.max_day: bk.pend=[]; return
        if self.cd_till and t<self.cd_till: bk.pend=[]; return
        if self.min_gap>0 and self.last_close and (t-self.last_close).total_seconds()<self.min_gap:
            bk.pend=[]; return
        if len(bk.pend)>=2: return
        if len(bk.pend)==1: bk.pend=[]
        if (ask-bid) > self.max_spread: return

        d=max(self.entry, self.minstop()+POINT); slD=self.eff_sl()
        tpD=max(self.tp,self.minstop()+POINT) if self.tp>0 else 0.0
        bp,sp=norm(ask+d),norm(bid-d); lot=self.calc_lot()
        if lot<=0: return
        bk.pend=[Pending('buystop',lot,bp, norm(bp-slD) if slD else 0.0, norm(bp+tpD) if tpD else 0.0),
                 Pending('sellstop',lot,sp, norm(sp+slD) if slD else 0.0, norm(sp-tpD) if tpD else 0.0)]
    def manage(self,t,bid,ask,newbar):
        p=self.bk.pos; isbuy = p.typ=='buy'
        profit=(bid-p.open_price) if isbuy else (p.open_price-ask)
        be = norm(p.open_price+self.be_lock) if isbuy else norm(p.open_price-self.be_lock)
        new=0.0
        if profit>=self.be_start:
            new=be; self.be_done=True
            lock=norm(bid-self.lock_gap) if isbuy else norm(ask+self.lock_gap)
            if isbuy and lock>new: new=lock
            if (not isbuy) and lock<new: new=lock
        if self.use_ct and self.be_done and newbar and self.prev_low is not None:
            if isbuy:
                c=norm(self.prev_low-self.ct_buf)
                if c>new: new=c
                if new<be: new=be
            else:
                c=norm(self.prev_high+self.ct_buf+(ask-bid))
                if new==0.0 or c<new: new=c
                if new>be: new=be
        if new==0.0: return
        md=self.minstop()
        if isbuy and new>bid-md: return
        if (not isbuy) and new<ask+md: return
        better=(p.sl==0 or new>p.sl+POINT*.5) if isbuy else (p.sl==0 or new<p.sl-POINT*.5)
        if better: p.sl=norm(new)
