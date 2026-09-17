#!/usr/bin/env python3
import json
from pathlib import Path
import numpy as np
import pandas as pd

DATA=Path('research/python_xau_backtest/data/xauusd_m5.csv')
OUT=Path('research/python_xau_backtest/output'); OUT.mkdir(parents=True,exist_ok=True)
POINT=0.01

def prep(ind='ewm',ema_n=50):
 d=pd.read_csv(DATA); d['time']=pd.to_datetime(d.time,utc=True,errors='coerce'); d=d.dropna(subset=['time','open','high','low','close']).sort_values('time').drop_duplicates('time'); end=d.time.max(); start=end-pd.Timedelta(days=365); d=d[d.time>=start]
 x=d.set_index('time').resample('15min',label='left',closed='left').agg({'open':'first','high':'max','low':'min','close':'last'}).dropna().reset_index()
 h,l,c=x.high,x.low,x.close; tr=pd.concat([h-l,(h-c.shift(1)).abs(),(l-c.shift(1)).abs()],axis=1).max(axis=1)
 up=h.diff(); dn=-l.diff(); pdm=pd.Series(np.where((up>dn)&(up>0),up,0.0),index=x.index); mdm=pd.Series(np.where((dn>up)&(dn>0),dn,0.0),index=x.index)
 if ind=='wilder':
  atr=tr.ewm(alpha=1/14,adjust=False).mean(); pdi=100*pdm.ewm(alpha=1/14,adjust=False).mean()/atr; mdi=100*mdm.ewm(alpha=1/14,adjust=False).mean()/atr; dx=100*(pdi-mdi).abs()/(pdi+mdi).replace(0,np.nan); adx=dx.ewm(alpha=1/14,adjust=False).mean()
 else:
  atr=tr.ewm(span=14,adjust=False).mean(); pdi=100*pdm.ewm(span=14,adjust=False).mean()/atr; mdi=100*mdm.ewm(span=14,adjust=False).mean()/atr; dx=100*(pdi-mdi).abs()/(pdi+mdi).replace(0,np.nan); adx=dx.ewm(span=14,adjust=False).mean()
 x['atr']=atr; x['adx']=adx; x['ema']=c.ewm(span=ema_n,adjust=False).mean(); x=x.dropna().reset_index(drop=True)
 return x,start,end

def run(am=1.5,rr=2.5,ema_n=50,adx_min=22,spread=20,slip=0,ind='ewm'):
 x,start,end=prep(ind,ema_n); o=x.open.to_numpy(); h=x.high.to_numpy(); l=x.low.to_numpy(); c=x.close.to_numpy(); a=x.atr.to_numpy(); ad=x.adx.to_numpy(); em=x.ema.to_numpy(); tm=x.time.to_numpy(); n=len(x)
 ts=0.; side=0; ent=sl=tp=risk=0.; et=None; rows=[]; sp=spread*POINT; slp=slip*POINT
 for i in range(2,n):
  if side:
   ep=None; reason=None
   if side==1:
    if l[i]<=sl: ep=sl-slp; reason='SL'
    elif h[i]>=tp: ep=tp-slp; reason='TP'
   else:
    if h[i]>=sl: ep=sl+slp; reason='SL'
    elif l[i]<=tp: ep=tp+slp; reason='TP'
   if ep is not None:
    r=(ep-ent)/risk if side==1 else (ent-ep)/risk; rows.append((et,tm[i],side,ent,sl,tp,risk,r,reason)); side=0
  if a[i-1]<6 or ad[i-1]<adx_min: continue
  nl=am*a[i-1]; prev=ts
  if c[i-1]>prev and c[i-2]>prev: ts=max(prev,c[i-1]-nl)
  elif c[i-1]<prev and c[i-2]<prev: ts=min(prev,c[i-1]+nl)
  elif c[i-1]>prev: ts=c[i-1]-nl
  else: ts=c[i-1]+nl
  longsig=c[i-1]>ts and c[i-1]>em[i-1]; shortsig=c[i-1]<ts and c[i-1]<em[i-1]
  if side==0 and (longsig or shortsig):
   side=1 if longsig else -1; ent=o[i]+sp+slp if side==1 else o[i]-sp-slp; risk=nl; sl=ent-nl if side==1 else ent+nl; tp=ent+rr*nl if side==1 else ent-rr*nl; et=tm[i]
   ep=None; reason=None
   if side==1:
    if l[i]<=sl: ep=sl-slp; reason='SL_ENTRY'
    elif h[i]>=tp: ep=tp-slp; reason='TP_ENTRY'
   else:
    if h[i]>=sl: ep=sl+slp; reason='SL_ENTRY'
    elif l[i]<=tp: ep=tp+slp; reason='TP_ENTRY'
   if ep is not None:
    r=(ep-ent)/risk if side==1 else (ent-ep)/risk; rows.append((et,tm[i],side,ent,sl,tp,risk,r,reason)); side=0
 return pd.DataFrame(rows,columns=['entry_time','exit_time','side','entry','sl','tp','n_loss','r','reason']),start,end

def stats(t,riskpct=.005):
 if t.empty:return {'trades':0}
 r=t.r.to_numpy(float); w=r[r>0]; lo=r[r<=0]; eq=1.; peak=1.; dd=0.
 for q in r: eq*=1+riskpct*q; peak=max(peak,eq); dd=min(dd,(eq-peak)/peak*100)
 return {'trades':int(len(r)),'win_rate_pct':float((r>0).mean()*100),'profit_factor_R':float(w.sum()/abs(lo.sum())) if len(lo) else float('inf'),'expectancy_R':float(r.mean()),'sum_R':float(r.sum()),'return_pct':float((eq-1)*100),'max_drawdown_pct':float(dd),'risk_pct':riskpct*100}

def mc(t,riskpct=.005,n=2000):
 r=t.r.to_numpy(float); rng=np.random.default_rng(42); d=[]
 for _ in range(n):
  eq=peak=1.; dd=0.
  for q in rng.permutation(r): eq*=1+riskpct*q; peak=max(peak,eq); dd=min(dd,(eq-peak)/peak*100)
  d.append(dd)
 return {'runs':n,'dd_p50_pct':float(np.percentile(d,50)),'dd_p95_worst_pct':float(np.percentile(d,5)),'dd_worst_pct':float(np.min(d))}

def main():
 cfgs=[('base',1.5,2.5,50,22,20,0,'ewm'),('spread1_5x',1.5,2.5,50,22,30,0,'ewm'),('spread2x',1.5,2.5,50,22,40,0,'ewm'),('slip5',1.5,2.5,50,22,20,5,'ewm'),('slip10',1.5,2.5,50,22,20,10,'ewm'),('atr1_2',1.2,2.5,50,22,20,0,'ewm'),('atr1_8',1.8,2.5,50,22,20,0,'ewm'),('rr2',1.5,2.0,50,22,20,0,'ewm'),('rr3',1.5,3.0,50,22,20,0,'ewm'),('adx18',1.5,2.5,50,18,20,0,'ewm'),('adx26',1.5,2.5,50,26,20,0,'ewm'),('ema40',1.5,2.5,40,22,20,0,'ewm'),('ema60',1.5,2.5,60,22,20,0,'ewm'),('wilder',1.5,2.5,50,22,20,0,'wilder')]
 out={}; base=None; start=end=None
 for name,am,rr,e,ad,sp,sl,ind in cfgs:
  t,start,end=run(am,rr,e,ad,sp,sl,ind); out[name]=stats(t,.005); out[name]['params']={'atr_mult':am,'rr':rr,'ema':e,'adx_min':ad,'spread_points':sp,'slippage_points':sl,'indicator':ind}; print(name,out[name]);
  if name=='base': base=t
 z=base.copy(); z['dt']=pd.to_datetime(z.entry_time,utc=True); mid=z.dt.min()+(z.dt.max()-z.dt.min())/2; mo=z.groupby(z.dt.dt.to_period('M')).r.sum(); qu=z.groupby(z.dt.dt.to_period('Q')).r.sum()
 report={'strategy':'UT Bot final stress FAST','data_start':str(start),'data_end':str(end),'entry_bar_fix':'enabled stop-first','scenarios':out,'risk_sweep':{str(p):stats(base,p/100) for p in (.25,.5,1.0)},'periods':{'H1':stats(z[z.dt<=mid],.005),'H2':stats(z[z.dt>mid],.005),'positive_months':int((mo>0).sum()),'months':int(len(mo)),'worst_month_R':float(mo.min()),'worst_quarter_R':float(qu.min()),'monthly_R':{str(k):float(v) for k,v in mo.items()}},'monte_carlo':{str(p):mc(base,p/100) for p in (.25,.5,1.0)}}
 report['scenario_pass_count']=sum(1 for v in out.values() if v.get('profit_factor_R',0)>=1.2 and v.get('expectancy_R',0)>0)
 report['FINAL_SCREEN_PASS']=bool(out['base'].get('profit_factor_R',0)>=1.2 and abs(out['base'].get('max_drawdown_pct',999))<=20 and report['periods']['H1'].get('expectancy_R',-1)>0 and report['periods']['H2'].get('expectancy_R',-1)>0 and out['spread2x'].get('profit_factor_R',0)>=1.2)
 base.to_csv(OUT/'utbot_final_stress_fast_trades.csv',index=False); json.dump(report,open(OUT/'utbot_final_stress_fast.json','w'),indent=2); print('=== FINAL ==='); print(json.dumps(report,indent=2)); print('FINAL_SCREEN_PASS:',report['FINAL_SCREEN_PASS'])
if __name__=='__main__':main()
