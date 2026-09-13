from bt import *
import statistics as st
bars = load()

def agg(ea_cls, seeds=(1,2,3,4,5), **kw):
    rs=[run(ea_cls,bars,10000.0,seed=s,**kw) for s in seeds]
    ss=[stats(b,e,'') for b,e in rs]
    f=lambda k:[r[k] for r in ss]
    return dict(net=st.mean(f('net')), n=st.mean(f('n')), wr=st.mean(f('wr')),
                pf=st.mean(f('pf')), dd=st.mean(f('ddp')), pts=st.mean(f('net_pts')),
                avgp=st.mean(f('avg_pts')), blown=sum(1 for r in ss if r['blown']),
                rs=rs, ss=ss)
def L(t,d):
    print(f"{t:<46} net {d['net']:>+11,.0f}  trades {d['n']:>6.0f}  WR {d['wr']:>5.1f}%  "
          f"PF {d['pf']:>5.2f}  DD {d['dd']:>5.1f}%  pts/trade {d['avgp']:>+6.1f}"
          + ("  BLOWN" if d['blown'] else ""))

print("### 3. NORMALISED: both EAs at FIXED 0.01 lot (strategy shape, no compounding)\n")
for noise in (0.28,0.45,0.65):
    L(f"EA A  0.01 lot  noise={noise}", agg(EA_A, noise=noise, lot_mode='fixed', fixed=0.01))
    L(f"EA B  0.01 lot  noise={noise}", agg(EA_B, noise=noise, auto_lot=False, fixed=0.01))
    print()

print("### 4. TRANSACTION-COST SENSITIVITY (0.01 lot, noise=0.45)\n")
for comm,slip in [(0,0),(0,3),(0,8),(3.5,3),(3.5,8),(7,5)]:
    L(f"EA A  comm ${comm}/lot/side  slip {slip}pt",
      agg(EA_A, noise=0.45, lot_mode='fixed', fixed=0.01, commission=comm, slip_pts=slip))
for comm,slip in [(0,0),(0,3),(0,8),(3.5,3),(3.5,8),(7,5)]:
    L(f"EA B  comm ${comm}/lot/side  slip {slip}pt",
      agg(EA_B, noise=0.45, auto_lot=False, fixed=0.01, commission=comm, slip_pts=slip))

print("\n### 5. EA-A reverse module: does it ever fire?\n")
for noise in (0.28,0.45,0.65):
    tot=fires=0
    for s in (1,2,3):
        bk,ea = run(EA_A,bars,10000.0,seed=s,noise=noise)
        tot+=len(bk.trades); fires+=ea.rev_fires
    print(f"  noise={noise}:  {fires} reverse fills out of {tot} trades  ({fires/tot*100:.2f}%)")

print("\n### 6. EA-B lot growth (auto 5% risk, NO cap) - noise=0.28, seed 1\n")
bk,ea = run(EA_B,bars,10000.0,seed=1,noise=0.28)
lots=[t.lots for t in bk.trades]
print(f"  first lot {lots[0]}   max lot {max(lots)}   last lot {lots[-1]}   trades {len(lots)}")
print(f"  biggest single loss: {min(t.pl for t in bk.trades):+,.0f} USD")
bk,ea = run(EA_B,bars,10000.0,seed=1,noise=0.65)
print(f"  noise=0.65 -> equity path ends {bk.balance:+,.0f}, blown={bk.blown}, trades={len(bk.trades)}")

print("\n### 7. EA-B with EA-A's risk discipline (1% risk, 0.5 lot cap, time filter ON)\n")
for noise in (0.28,0.45,0.65):
    L(f"EA B  tamed  noise={noise}", agg(EA_B, noise=noise, risk=1.0, max_lot=0.5, use_time=True))
