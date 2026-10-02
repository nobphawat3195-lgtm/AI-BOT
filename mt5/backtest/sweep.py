from bt import *
from control import shuffled_series
import statistics as st

bars = load()

def agg(ea_cls, bars, seeds=(1,2,3,4,5,6,7,8), **kw):
    rs=[]
    for s in seeds:
        bk,ea = run(ea_cls, bars, 10000.0, seed=s, **kw)
        rs.append(stats(bk,ea,''))
    f=lambda k:[r[k] for r in rs]
    return dict(net=st.mean(f('net')), net_sd=st.pstdev(f('net')),
                lo=min(f('net')), hi=max(f('net')),
                n=st.mean(f('n')), wr=st.mean(f('wr')), pf=st.mean(f('pf')),
                dd=st.mean(f('ddp')), pts=st.mean(f('net_pts')),
                blown=sum(1 for r in rs if r['blown']))

def line(tag, d):
    print(f"{tag:<44} net {d['net']:>+11,.0f}  (sd {d['net_sd']:>8,.0f}; {d['lo']:>+10,.0f}..{d['hi']:>+10,.0f})"
          f"  trades {d['n']:>6.0f}  WR {d['wr']:>5.1f}%  PF {d['pf']:>5.2f}  DD {d['dd']:>5.1f}%"
          + ("  BLOWN" if d['blown'] else ""))

print("\n### 1. INTRABAR-NOISE SENSITIVITY (how rough is price inside the minute?)")
print("    Same data, same logic - only the assumed intrabar path changes.\n")
for noise in (0.15, 0.28, 0.45, 0.65, 0.85):
    line(f"EA A  noise={noise}", agg(EA_A, bars, noise=noise))
print()
for noise in (0.15, 0.28, 0.45, 0.65, 0.85):
    line(f"EA B  noise={noise}", agg(EA_B, bars, noise=noise))

print("\n### 2. CONTROL TEST - shuffled returns (same volatility, no real structure)")
print("    An EA with a genuine edge should go to ~zero minus costs here.\n")
for cs in (0,1,2):
    sb = shuffled_series(bars, seed=cs)
    line(f"EA A  shuffled series #{cs}", agg(EA_A, sb, seeds=(1,2,3)))
for cs in (0,1,2):
    sb = shuffled_series(bars, seed=cs)
    line(f"EA B  shuffled series #{cs}", agg(EA_B, sb, seeds=(1,2,3)))
