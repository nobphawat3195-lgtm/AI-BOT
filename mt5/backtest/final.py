import datetime, statistics as st
from bt import load, run, stats
from eac import EA_C
BARS=load()
OS=[b for b in BARS if b['t'].date() in {datetime.date(2026,7,6),datetime.date(2026,7,7)}]
COST=dict(commission=3.5, slip_pts=3.0); CAP=300.0
FINAL=dict(tp=10.0, cd_sl=0, max_day=200, use_ct=False)
def band(bars,kw,noise,seeds=(1,2,3,4,5)):
    rs=[]
    for s in seeds:
        bk,ea=run(EA_C,bars,CAP,seed=s,noise=noise,**COST,**kw)
        d=stats(bk,ea,''); d['comm']=sum(x.lots for x in bk.trades)*3.5*2
        d['eqmin']=min(e for _,e in bk.eq_curve); rs.append(d)
    f=lambda k:[r[k] for r in rs]
    return dict(net=st.mean(f('net')),lo=min(f('net')),hi=max(f('net')),n=st.mean(f('n')),
                wr=st.mean(f('wr')),pf=st.mean(f('pf')),dd=st.mean(f('ddp')),
                comm=st.mean(f('comm')),eqmin=min(f('eqmin')),blown=sum(1 for r in rs if r['blown']))
print("XAU_StraddleCore_v1 ค่าสุดท้าย · $300 · ล็อต 0.01 · คอม $3.5/ข้าง + slip 3 จุด\n")
h=f"{'noise':>6} {'กำไร$':>9} {'%':>8} {'แย่สุด':>9} {'ดีสุด':>9} {'ไม้':>6} {'WR%':>6} {'PF':>5} {'DD%':>6} {'ทุนต่ำสุด':>10} {'คอม%':>6}"
print(h); print('-'*len(h))
for noise in (0.28,0.45,0.65,0.85):
    d=band(BARS,FINAL,noise)
    print(f"{noise:>6} {d['net']:>+9.2f} {d['net']/CAP*100:>+7.1f}% {d['lo']:>+9.2f} {d['hi']:>+9.2f} "
          f"{d['n']:>6.0f} {d['wr']:>6.1f} {d['pf']:>5.2f} {d['dd']:>6.2f} {d['eqmin']:>10.2f} "
          f"{d['comm']/CAP*100:>5.1f}%" + ("  ล้างพอร์ต" if d['blown'] else ""))
print("\nOUT-OF-SAMPLE 6-7 ก.ค.:")
for noise in (0.28,0.45,0.65):
    d=band(OS,FINAL,noise,seeds=(1,2,3))
    print(f"  noise {noise}: {d['net']:>+8.2f} ({d['net']/CAP*100:>+5.1f}%)  ไม้ {d['n']:.0f}  PF {d['pf']:.2f}")
print("\nเทียบกับ EA เดิม (นอกกลุ่มตัวอย่าง noise 0.45):")
print("  A เก่า -6.7%  |  A ใหม่ -6.1%  |  B เก่า -94.3%  |  B ใหม่ +7.6%")
d=band(OS,FINAL,0.45,seeds=(1,2,3))
print(f"  StraddleCore v1: {d['net']/CAP*100:+.1f}%")
