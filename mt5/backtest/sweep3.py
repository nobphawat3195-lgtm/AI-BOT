import bt
from bt import *
bars=load()

print("### 8. EA-A sensitivity to broker server timezone (session filter depends on it)\n")
for g in (0,2,3,5):
    bt.SERVER_GMT=g
    bk,ea=run(EA_A,bars,10000.0,seed=1,noise=0.45,lot_mode='fixed',fixed=0.01)
    s=stats(bk,ea,'')
    print(f"  server GMT+{g}: net {s['net']:>+8.2f}  trades {s['n']:>4d}  WR {s['wr']:.1f}%  PF {s['pf']:.2f}")
bt.SERVER_GMT=3

print("\n### 9. Per-day P/L, fixed 0.01 lot, noise=0.45 (mean of 5 seeds)\n")
import collections, statistics as st
for name,cls,kw in [("EA A",EA_A,dict(lot_mode='fixed',fixed=0.01)),
                    ("EA B",EA_B,dict(auto_lot=False,fixed=0.01))]:
    acc=collections.defaultdict(list)
    for s in (1,2,3,4,5):
        bk,ea=run(cls,bars,10000.0,seed=s,noise=0.45,**kw)
        d=collections.defaultdict(float); c=collections.Counter()
        for t in bk.trades: d[t.close_time.date()]+=t.pl; c[t.close_time.date()]+=1
        for k,v in d.items(): acc[k].append((v,c[k]))
    print(f"  {name}:")
    for k in sorted(acc):
        pl=st.mean(x[0] for x in acc[k]); n=st.mean(x[1] for x in acc[k])
        print(f"    {k}  {pl:>+8.2f} USD   ({n:>5.0f} trades)")
