"""
Parameter optimisation with a robustness screen.

Plain "find the highest net profit" optimisation on this dataset would just
curve-fit the intrabar path model. So every candidate is scored three ways:

  1. net profit on the REAL series (mean across seeds, and worst seed)
  2. net profit on SHUFFLED series (same volatility, structure destroyed)
  3. EDGE = real - shuffled

Only a positive EDGE is evidence of anything real. A candidate that scores
high on both is exploiting the simulation, not the market.

Baseline assumptions (deliberately realistic, not flattering):
  fixed 0.01 lot, noise=0.45, commission $3.5/lot/side, 3 points slippage.
"""
import itertools, statistics as st, sys
from multiprocessing import Pool
from bt import load, run, stats, EA_A, EA_B
from control import shuffled_series

BARS = load()
SHUF = [shuffled_series(BARS, seed=s) for s in (0, 1, 2)]
SEEDS = (1, 2, 3)
BASE = dict(commission=3.5, slip_pts=3.0, noise=0.45)


def score(args):
    cls, kw = args
    real = []
    for s in SEEDS:
        bk, ea = run(cls, BARS, 10000.0, seed=s, **BASE, **kw)
        real.append(stats(bk, ea, ''))
    shuf = []
    for i, sb in enumerate(SHUF):
        bk, ea = run(cls, sb, 10000.0, seed=i + 1, **BASE, **kw)
        shuf.append(stats(bk, ea, ''))

    net = [r['net'] for r in real]
    snet = [r['net'] for r in shuf]
    return dict(kw=kw,
                net=st.mean(net), worst=min(net),
                shuf=st.mean(snet),
                edge=st.mean(net) - st.mean(snet),
                n=st.mean(r['n'] for r in real),
                wr=st.mean(r['wr'] for r in real),
                pf=st.mean(r['pf'] for r in real),
                dd=st.mean(r['ddp'] for r in real))


def grid(d):
    keys = list(d)
    for vals in itertools.product(*(d[k] for k in keys)):
        yield dict(zip(keys, vals))


GRID_A = dict(
    lot_mode=['fixed'], fixed=[0.01],
    straddle=[0.30, 0.50, 0.80, 1.20],
    sl      =[1.00, 1.50, 2.50],
    tr_start=[1.00, 1.50, 2.50],
    tr_dist =[0.60, 1.00, 1.50],
    use_time=[True, False],
)

GRID_B = dict(
    auto_lot=[False], fixed=[0.01],
    d_buy   =[50, 100, 200],
    sl      =[150, 250, 400],
    be_trig =[40, 60, 100],
    lock_gap=[60, 100, 150],
    use_time=[True, False],
)


def run_grid(name, cls, g, extra_link=None):
    combos = []
    for kw in grid(g):
        if extra_link:
            extra_link(kw)
        combos.append((cls, kw))
    print(f"\n{'='*100}\n{name}: {len(combos)} combinations x "
          f"{len(SEEDS)} seeds real + {len(SHUF)} shuffled\n{'='*100}", flush=True)
    with Pool(4) as p:
        res = p.map(score, combos)
    res.sort(key=lambda r: -r['edge'])
    hdr = (f"{'rank':>4} {'net(real)':>10} {'worst':>9} {'net(shuf)':>10} "
           f"{'EDGE':>9} {'trades':>7} {'WR%':>6} {'PF':>6} {'DD%':>6}  params")
    print(hdr)
    print('-' * len(hdr))
    for i, r in enumerate(res[:15], 1):
        ps = ' '.join(f"{k}={v}" for k, v in r['kw'].items()
                      if k not in ('lot_mode', 'fixed', 'auto_lot'))
        print(f"{i:>4} {r['net']:>+10.2f} {r['worst']:>+9.2f} {r['shuf']:>+10.2f} "
              f"{r['edge']:>+9.2f} {r['n']:>7.0f} {r['wr']:>6.1f} {r['pf']:>6.2f} "
              f"{r['dd']:>6.2f}  {ps}")
    # also show what a naive "max net" optimiser would have picked
    naive = max(res, key=lambda r: r['net'])
    ps = ' '.join(f"{k}={v}" for k, v in naive['kw'].items()
                  if k not in ('lot_mode', 'fixed', 'auto_lot'))
    print(f"\n  naive max-net pick: net {naive['net']:+.2f} | on shuffled "
          f"{naive['shuf']:+.2f} | EDGE {naive['edge']:+.2f}  [{ps}]")
    pos = [r for r in res if r['edge'] > 0 and r['worst'] > 0]
    print(f"  combos with positive EDGE and every seed profitable: {len(pos)} / {len(res)}")
    return res


def link_b(kw):
    kw['d_sell'] = kw['d_buy']


if __name__ == '__main__':
    which = sys.argv[1] if len(sys.argv) > 1 else 'both'
    if which in ('a', 'both'):
        run_grid('EA A - XAU_StraddleReverse v4.2', EA_A, GRID_A)
    if which in ('b', 'both'):
        run_grid('EA B - XAUUSD_Straddle_Scalper_TH v3', EA_B, GRID_B, link_b)
