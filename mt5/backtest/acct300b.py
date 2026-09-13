import datetime, statistics as st
from bt import load, run, stats, EA_A, EA_B
BARS=load()
OS=[b for b in BARS if b['t'].date() in {datetime.date(2026,7,6),datetime.date(2026,7,7)}]
COST=dict(commission=3.5, slip_pts=3.0); CAP=300.0
NEWB=dict(auto_lot=False, fixed=0.01, d_buy=50, d_sell=50, sl=150, be_trig=60,
          lock_gap=100, use_time=True)
NEWA=dict(lot_mode='fixed', fixed=0.01, straddle=0.50, sl=2.50, tr_start=1.00,
          tr_dist=1.50, use_time=True)
def band(cls,bars,kw,noise,seeds=(1,2,3,4,5)):
    rs=[]
    for s in seeds:
        bk,ea=run(cls,bars,CAP,seed=s,noise=noise,**COST,**kw); d=stats(bk,ea,'')
        d['eqmin']=min(e for _,e in bk.eq_curve); d['comm']=sum(t.lots for t in bk.trades)*3.5*2
        rs.append(d)
    f=lambda k:[r[k] for r in rs]
    return dict(net=st.mean(f('net')),lo=min(f('net')),n=st.mean(f('n')),wr=st.mean(f('wr')),
                pf=st.mean(f('pf')),dd=st.mean(f('ddp')),eqmin=min(f('eqmin')),
                comm=st.mean(f('comm')),worst=min(f('worst')))
print(f"บัญชี ${CAP:.0f} | ล็อตคงที่ 0.01 (ไม่ทบต้น) | คอม $3.5/ล็อต/ข้าง + slip 3 จุด\n")
h=f"{'ค่า':<16} {'noise':>5} {'กำไร$':>8} {'%':>7} {'แย่สุด':>8} {'ไม้':>6} {'PF':>5} {'DD%':>6} {'ทุนต่ำสุด':>10} {'ค่าคอมรวม$':>11}"
print(h); print('-'*len(h))
for tag,cls,kw in [('A-new 0.01',EA_A,NEWA),('B-new 0.01',EA_B,NEWB)]:
    for noise in (0.28,0.45,0.65,0.85):
        d=band(cls,BARS,kw,noise)
        print(f"{tag:<16} {noise:>5} {d['net']:>+8.2f} {d['net']/CAP*100:>+6.1f}% {d['lo']:>+8.2f} "
              f"{d['n']:>6.0f} {d['pf']:>5.2f} {d['dd']:>6.2f} {d['eqmin']:>10.2f} {d['comm']:>11.2f}")
    print()
print("OUT-OF-SAMPLE 6-7 ก.ค. | noise=0.45 | ล็อตคงที่ 0.01")
for tag,cls,kw in [('A-new 0.01',EA_A,NEWA),('B-new 0.01',EA_B,NEWB)]:
    d=band(cls,OS,kw,0.45,seeds=(1,2,3))
    print(f"  {tag:<12} {d['net']:>+8.2f} ({d['net']/CAP*100:>+5.1f}%)  ไม้ {d['n']:.0f}  PF {d['pf']:.2f}")
