"""จูนรอบสุดท้าย: ล็อกช่วงเวลาไว้แล้ว ปรับเฉพาะระยะเข้า/SL/กันทุน/ล็อกกำไร
เกณฑ์ไม่ใช่ 'กำไรสูงสุด' แต่คือ 'ทนทานที่สุด':
   - ต้องบวกนอกกลุ่มตัวอย่าง
   - ต้องชนะข้อมูลสุ่ม
   - ต้องไม่พังที่สมมติฐานหยาบ (noise 0.65)  <- จุดอ่อนปัจจุบัน
คะแนน = ค่าที่แย่กว่าระหว่าง noise 0.45 กับ 0.65 (worst-case)"""
import itertools, datetime, statistics as st
from multiprocessing import Pool
from bt import load, run, stats
from eac import EA_C
from control import shuffled_series

BARS=load()
OS=[b for b in BARS if b['t'].date() in {datetime.date(2026,7,6),datetime.date(2026,7,7)}]
SH=[shuffled_series(BARS,seed=s) for s in (0,1)]
COST=dict(commission=3.5, slip_pts=3.0)
FIX=dict(tp=10.0, cd_sl=0, max_day=200, use_ct=False,
         sessions=[(8*60,9*60),(20*60,21*60)])

GRID=dict(entry=[0.30,0.50,0.80],
          sl   =[1.00,1.50,2.50],
          be_start=[0.40,0.60,1.00],
          lock_gap=[0.60,1.00,1.50])

def one(kw):
    def m(bars,noise,seeds):
        r=[stats(*run(EA_C,bars,300.0,seed=s,noise=noise,**COST,**FIX,**kw),'')
           for s in seeds]
        return st.mean(x['net'] for x in r), st.mean(x['pf'] for x in r), st.mean(x['ddp'] for x in r)
    n45,pf45,dd45=m(BARS,0.45,(1,2,3))
    n65,_,dd65   =m(BARS,0.65,(1,2,3))
    oos,_,_      =m(OS,0.45,(1,2,3))
    sh=st.mean(m(s,0.45,(1,))[0] for s in SH)
    return dict(kw=kw, n45=n45, n65=n65, oos=oos, sh=sh, edge=n45-sh,
                pf=pf45, dd=max(dd45,dd65), worst=min(n45,n65))

def stats_wrap(bk_ea, label=''):
    return stats(bk_ea[0], bk_ea[1], label)

if __name__=='__main__':
    combos=[dict(zip(GRID,v)) for v in itertools.product(*GRID.values())]
    with Pool(4) as p: res=p.map(one, combos)
    ok=[r for r in res if r['oos']>0 and r['edge']>0 and r['n65']>0]
    print(f"ทดสอบ {len(res)} ชุด | ผ่านเกณฑ์ทนทานทั้ง 3 ข้อ: {len(ok)} ชุด\n")
    ok.sort(key=lambda r:-r['worst'])
    hd=f"{'#':>2} {'entry':>6} {'SL':>5} {'BE':>5} {'lock':>5} | {'n=.45':>8} {'n=.65':>8} {'worst':>8} {'OOS':>8} {'EDGE':>8} {'PF':>5} {'DD%':>6}"
    print(hd); print('-'*len(hd))
    for i,r in enumerate(ok[:12],1):
        k=r['kw']
        print(f"{i:>2} {k['entry']:>6.2f} {k['sl']:>5.2f} {k['be_start']:>5.2f} {k['lock_gap']:>5.2f} | "
              f"{r['n45']:>+8.2f} {r['n65']:>+8.2f} {r['worst']:>+8.2f} {r['oos']:>+8.2f} "
              f"{r['edge']:>+8.2f} {r['pf']:>5.2f} {r['dd']:>6.2f}")
    cur=[r for r in res if r['kw']=={'entry':0.50,'sl':1.50,'be_start':0.60,'lock_gap':1.00}][0]
    print(f"\nค่าปัจจุบัน (0.50/1.50/0.60/1.00): n45 {cur['n45']:+.2f}  n65 {cur['n65']:+.2f}  "
          f"worst {cur['worst']:+.2f}  OOS {cur['oos']:+.2f}  PF {cur['pf']:.2f}  DD {cur['dd']:.2f}%")
