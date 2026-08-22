import datetime, statistics as st
from bt import load, run, stats
from eac import EA_C
BARS=load()
IS=[b for b in BARS if b['t'].date() in {datetime.date(2026,7,1),datetime.date(2026,7,2),datetime.date(2026,7,3)}]
OS=[b for b in BARS if b['t'].date() in {datetime.date(2026,7,6),datetime.date(2026,7,7)}]
COST=dict(commission=3.5, slip_pts=3.0); CAP=300.0
def band(bars,kw,noise,seeds=(1,2,3,4,5)):
    rs=[]
    for s in seeds:
        bk,ea=run(EA_C,bars,CAP,seed=s,noise=noise,**COST,**kw)
        d=stats(bk,ea,''); d['comm']=sum(x.lots for x in bk.trades)*3.5*2; rs.append(d)
    f=lambda k:[r[k] for r in rs]
    return dict(net=st.mean(f('net')),lo=min(f('net')),n=st.mean(f('n')),
                pf=st.mean(f('pf')),dd=st.mean(f('ddp')),comm=st.mean(f('comm')))
BASE=dict()
VAR={
 'ตั้งต้น (TP=0, cd 60s, cap100)': dict(),
 'ไม่พักหลัง SL':                  dict(cd_sl=0),
 'ใส่ TP $10':                     dict(tp=10.0),
 'TP $10 + ไม่พัก':                dict(tp=10.0, cd_sl=0),
 'TP $10 + ไม่พัก + ไม่จำกัดไม้':   dict(tp=10.0, cd_sl=0, max_day=0),
 'TP $10 + ไม่พัก + cap 50':       dict(tp=10.0, cd_sl=0, max_day=50),
 'TP $10 + ไม่พัก + cap 200':      dict(tp=10.0, cd_sl=0, max_day=200),
 'TP $5  + ไม่พัก':                dict(tp=5.0, cd_sl=0),
 'TP $10 + ไม่พัก + ไม่ไล่แท่ง':    dict(tp=10.0, cd_sl=0, use_ct=False),
}
h=f"{'ค่า':<34} {'IS':>9} {'OOS .45':>9} {'OOS .65':>9} {'เต็มชุด .45':>12} {'ไม้':>6} {'PF':>5} {'DD%':>6}"
print(f"XAU_StraddleCore_v1 · $300 · ล็อต 0.01 · คอม+slip จริง\n"); print(h); print('-'*len(h))
for name,kw in VAR.items():
    k=dict(BASE,**kw)
    i=band(IS,k,0.45,seeds=(1,2,3)); o=band(OS,k,0.45,seeds=(1,2,3))
    o65=band(OS,k,0.65,seeds=(1,2,3)); full=band(BARS,k,0.45)
    print(f"{name:<34} {i['net']:>+9.2f} {o['net']:>+9.2f} {o65['net']:>+9.2f} "
          f"{full['net']:>+12.2f} {full['n']:>6.0f} {full['pf']:>5.2f} {full['dd']:>6.2f}")
