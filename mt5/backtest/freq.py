import datetime, statistics as st
from bt import load, run, stats, EA_B
BARS=load()
OS=[b for b in BARS if b['t'].date() in {datetime.date(2026,7,6),datetime.date(2026,7,7)}]
COST=dict(commission=3.5, slip_pts=3.0); CAP=300.0
BASE=dict(auto_lot=False, fixed=0.01, d_buy=50, d_sell=50, sl=150,
          be_trig=60, lock_gap=100, use_time=True)
def band(bars,kw,noise,seeds=(1,2,3,4,5)):
    rs=[]
    for s in seeds:
        bk,ea=run(EA_B,bars,CAP,seed=s,noise=noise,**COST,**kw); d=stats(bk,ea,'')
        d['comm']=sum(t.lots for t in bk.trades)*3.5*2; rs.append(d)
    f=lambda k:[r[k] for r in rs]
    return dict(net=st.mean(f('net')),lo=min(f('net')),n=st.mean(f('n')),
                pf=st.mean(f('pf')),dd=st.mean(f('ddp')),comm=st.mean(f('comm')),
                wr=st.mean(f('wr')))
print("บัญชี $300 · ล็อต 0.01 · คอม $3.5/ข้าง + slip 3 จุด · B ค่าใหม่\n")
h=f"{'จำกัดไม้/วัน':>12} {'พัก(วิ)':>8} | {'noise .45':>10} {'OOS':>9} {'ไม้':>6} {'PF':>5} {'DD%':>6} {'คอม$':>7} {'คอม%พอร์ต':>10}"
print(h); print('-'*len(h))
for mx,cd in [(0,0),(0,60),(0,300),(100,0),(50,0),(30,0),(20,0),(10,0),(30,60),(20,300)]:
    kw=dict(BASE, max_trades_day=mx, cooldown_sec=cd)
    d=band(BARS,kw,0.45); o=band(OS,kw,0.45,seeds=(1,2,3))
    lbl = 'ไม่จำกัด' if mx==0 else str(mx)
    print(f"{lbl:>12} {cd:>8} | {d['net']:>+10.2f} {o['net']:>+9.2f} {d['n']:>6.0f} "
          f"{d['pf']:>5.2f} {d['dd']:>6.2f} {d['comm']:>7.2f} {d['comm']/CAP*100:>9.1f}%")
