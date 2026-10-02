"""
Validation of the optimisation winners.

Two things separate a real result from a curve-fit:
  1. it survives a DIFFERENT intrabar-path assumption than the one it was tuned on
  2. it survives OUT-OF-SAMPLE data it never saw during tuning
"""
import datetime, itertools, statistics as st
from multiprocessing import Pool
from bt import load, run, stats, EA_A, EA_B
from control import shuffled_series

BARS = load()
IS_DAYS = {datetime.date(2026, 7, 1), datetime.date(2026, 7, 2), datetime.date(2026, 7, 3)}
OS_DAYS = {datetime.date(2026, 7, 6), datetime.date(2026, 7, 7)}
IS = [b for b in BARS if b['t'].date() in IS_DAYS]
OS = [b for b in BARS if b['t'].date() in OS_DAYS]

COST = dict(commission=3.5, slip_pts=3.0)
SEEDS = (1, 2, 3, 4, 5)

BEST_A = dict(lot_mode='fixed', fixed=0.01, straddle=0.50, sl=2.50,
              tr_start=1.00, tr_dist=1.50, use_time=True)
DEF_A  = dict(lot_mode='fixed', fixed=0.01)

BEST_B = dict(auto_lot=False, fixed=0.01, d_buy=50, d_sell=50, sl=150,
              be_trig=60, lock_gap=100, use_time=True)
DEF_B  = dict(auto_lot=False, fixed=0.01)


def ev(args):
    cls, bars, kw, noise, seed = args
    bk, ea = run(cls, bars, 10000.0, seed=seed, noise=noise, **COST, **kw)
    return stats(bk, ea, '')


def band(cls, bars, kw, noise, seeds=SEEDS):
    rs = [ev((cls, bars, kw, noise, s)) for s in seeds]
    net = [r['net'] for r in rs]
    return dict(mean=st.mean(net), lo=min(net), hi=max(net),
                n=st.mean(r['n'] for r in rs), pf=st.mean(r['pf'] for r in rs),
                wr=st.mean(r['wr'] for r in rs), dd=st.mean(r['ddp'] for r in rs))


def show(tag, d):
    print(f"  {tag:<34} net {d['mean']:>+9.2f}  (worst {d['lo']:>+8.2f} / best {d['hi']:>+8.2f})"
          f"  trades {d['n']:>5.0f}  WR {d['wr']:>5.1f}%  PF {d['pf']:>5.2f}  DD {d['dd']:>5.2f}%")


print("=" * 104)
print("TEST 1 - do the optimised settings survive a DIFFERENT intrabar-path assumption?")
print("         (tuned at noise=0.45; costs $3.5/lot/side + 3pt slippage; 0.01 lot; 5 seeds)")
print("=" * 104)
for name, cls, best, deflt in [('EA A', EA_A, BEST_A, DEF_A), ('EA B', EA_B, BEST_B, DEF_B)]:
    print(f"\n{name}")
    for noise in (0.28, 0.45, 0.65, 0.85):
        show(f"optimised   noise={noise}", band(cls, BARS, best, noise))
    for noise in (0.28, 0.45, 0.65, 0.85):
        show(f"defaults    noise={noise}", band(cls, BARS, deflt, noise))

print("\n" + "=" * 104)
print("TEST 2 - WALK-FORWARD: tune on 1-3 Jul, then test untouched on 6-7 Jul")
print("=" * 104)

GRID_A = dict(lot_mode=['fixed'], fixed=[0.01],
              straddle=[0.30, 0.50, 0.80, 1.20], sl=[1.00, 1.50, 2.50],
              tr_start=[1.00, 1.50, 2.50], tr_dist=[0.60, 1.00, 1.50],
              use_time=[True, False])
GRID_B = dict(auto_lot=[False], fixed=[0.01], d_buy=[50, 100, 200],
              sl=[150, 250, 400], be_trig=[40, 60, 100],
              lock_gap=[60, 100, 150], use_time=[True, False])


def grid(d):
    keys = list(d)
    for vals in itertools.product(*(d[k] for k in keys)):
        yield dict(zip(keys, vals))


def walkforward(name, cls, g, link=None):
    combos = []
    for kw in grid(g):
        if link:
            link(kw)
        combos.append(kw)
    jobs = [(cls, IS, kw, 0.45, s) for kw in combos for s in (1, 2, 3)]
    with Pool(4) as p:
        res = p.map(ev, jobs)
    scored = []
    for i, kw in enumerate(combos):
        chunk = res[i * 3:(i + 1) * 3]
        scored.append((st.mean(r['net'] for r in chunk), kw))
    scored.sort(key=lambda x: -x[0])

    print(f"\n{name}   (in-sample 1-3 Jul -> out-of-sample 6-7 Jul)")
    print(f"  {'rank':>4} {'IS net':>9} {'OOS net':>9} {'OOS worst':>10}  params")
    oos_nets = []
    for rank, (isnet, kw) in enumerate(scored[:8], 1):
        o = band(cls, OS, kw, 0.45, seeds=(1, 2, 3))
        oos_nets.append(o['mean'])
        ps = ' '.join(f"{k}={v}" for k, v in kw.items()
                      if k not in ('lot_mode', 'fixed', 'auto_lot', 'd_sell'))
        print(f"  {rank:>4} {isnet:>+9.2f} {o['mean']:>+9.2f} {o['lo']:>+10.2f}  {ps}")

    # how does the IS-best do vs. the average of all combos, out of sample?
    allo = [band(cls, OS, kw, 0.45, seeds=(1,))['mean'] for _, kw in scored]
    print(f"  --> top-8 IS picks average {st.mean(oos_nets):+.2f} out-of-sample; "
          f"all {len(scored)} combos average {st.mean(allo):+.2f}")
    pos = sum(1 for x in oos_nets if x > 0)
    print(f"  --> {pos}/8 of the in-sample winners stayed profitable out-of-sample")


def link_b(kw):
    kw['d_sell'] = kw['d_buy']


walkforward('EA A', EA_A, GRID_A)
walkforward('EA B', EA_B, GRID_B, link_b)
