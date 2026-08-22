import datetime, statistics as st
from bt import load, run, stats, EA_A, EA_B

BARS = load()
OS = [b for b in BARS if b['t'].date() in {datetime.date(2026,7,6), datetime.date(2026,7,7)}]
COST = dict(commission=3.5, slip_pts=3.0)
SEEDS = (1,2,3,4,5)
CAP = 300.0

CFG = {
 'A-old': (EA_A, dict()),                                    # ตามที่แจกมา: auto 1%, cap 0.5, time ON
 'A-new': (EA_A, dict(straddle=0.50, sl=2.50, tr_start=1.00, tr_dist=1.50,
                      use_time=True, risk=1.0, max_lot=0.50)),
 'B-old': (EA_B, dict()),                                    # ตามที่แจกมา: auto 5%, ไม่มีเพดาน, time OFF
 'B-new': (EA_B, dict(d_buy=50, d_sell=50, sl=150, be_trig=60, lock_gap=100,
                      use_time=True, risk=1.0, max_lot=0.50)),
}

def band(cls, bars, kw, noise, seeds=SEEDS):
    rs=[]
    for s in seeds:
        bk,ea = run(cls, bars, CAP, seed=s, noise=noise, **COST, **kw)
        d = stats(bk,ea,'')
        eqmin = min(e for _,e in bk.eq_curve) if bk.eq_curve else CAP
        d['eqmin']=eqmin
        d['lots']=st.mean(t.lots for t in bk.trades) if bk.trades else 0
        d['maxlot']=max((t.lots for t in bk.trades), default=0)
        rs.append(d)
    f=lambda k:[r[k] for r in rs]
    return dict(net=st.mean(f('net')), lo=min(f('net')), hi=max(f('net')),
                n=st.mean(f('n')), wr=st.mean(f('wr')), pf=st.mean(f('pf')),
                dd=st.mean(f('ddp')), eqmin=min(f('eqmin')),
                worst=min(f('worst')), lots=st.mean(f('lots')), maxlot=max(f('maxlot')),
                blown=sum(1 for r in rs if r['blown']))

print(f"บัญชี ${CAP:.0f} | ค่าคอม $3.5/ล็อต/ข้าง + slippage 3 จุด | เฉลี่ย 5 seeds\n")
hdr=f"{'ค่า':<7} {'noise':>5} {'กำไร$':>9} {'%':>8} {'แย่สุด':>9} {'ไม้':>6} {'WR%':>6} {'PF':>5} {'DD%':>6} {'ทุนต่ำสุด$':>11} {'ล็อต':>6} {'เสีย/ไม้':>9}"
print(hdr); print('-'*len(hdr))
res={}
for tag,(cls,kw) in CFG.items():
    for noise in (0.28,0.45,0.65):
        d=band(cls,BARS,kw,noise); res[(tag,noise)]=d
        flag='  ล้างพอร์ต' if d['blown'] else ''
        print(f"{tag:<7} {noise:>5} {d['net']:>+9.2f} {d['net']/CAP*100:>+7.1f}% {d['lo']:>+9.2f} "
              f"{d['n']:>6.0f} {d['wr']:>6.1f} {d['pf']:>5.2f} {d['dd']:>6.2f} {d['eqmin']:>11.2f} "
              f"{d['lots']:>6.2f} {d['worst']:>+9.2f}{flag}")
    print()

print("\nOUT-OF-SAMPLE (6-7 ก.ค. ที่ไม่ได้ใช้จูน) | noise=0.45")
print(f"{'ค่า':<7} {'กำไร$':>9} {'%':>8} {'ไม้':>6} {'PF':>5}")
print('-'*40)
for tag,(cls,kw) in CFG.items():
    d=band(cls,OS,kw,0.45,seeds=(1,2,3))
    print(f"{tag:<7} {d['net']:>+9.2f} {d['net']/CAP*100:>+7.1f}% {d['n']:>6.0f} {d['pf']:>5.2f}")
