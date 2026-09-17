#!/usr/bin/env python3
import json
from pathlib import Path
import numpy as np
import pandas as pd

DATA = Path("research/python_xau_backtest/data/xauusd_m5.csv")
OUT = Path("research/python_xau_backtest/output")
OUT.mkdir(parents=True, exist_ok=True)
POINT_VALUE = 0.01
RR_DEFAULT = 2.5


def ewm_atr(df, period=14):
    h,l,c=df.high,df.low,df.close
    tr=pd.concat([h-l,(h-c.shift(1)).abs(),(l-c.shift(1)).abs()],axis=1).max(axis=1)
    return tr.ewm(span=period,adjust=False).mean()

def ema(s,n): return s.ewm(span=n,adjust=False).mean()

def ewm_adx(df,period=14):
    h,l,c=df.high,df.low,df.close
    up=h.diff(); down=-l.diff()
    pdm=pd.Series(np.where((up>down)&(up>0),up,0.0),index=df.index)
    mdm=pd.Series(np.where((down>up)&(down>0),down,0.0),index=df.index)
    tr=pd.concat([h-l,(h-c.shift(1)).abs(),(l-c.shift(1)).abs()],axis=1).max(axis=1)
    a=tr.ewm(span=period,adjust=False).mean()
    pdi=100*pdm.ewm(span=period,adjust=False).mean()/a
    mdi=100*mdm.ewm(span=period,adjust=False).mean()/a
    dx=100*(pdi-mdi).abs()/(pdi+mdi).replace(0,np.nan)
    return dx.ewm(span=period,adjust=False).mean()

def wilder_rma(s,n): return s.ewm(alpha=1/n,adjust=False).mean()

def wilder_atr(df,period=14):
    h,l,c=df.high,df.low,df.close
    tr=pd.concat([h-l,(h-c.shift(1)).abs(),(l-c.shift(1)).abs()],axis=1).max(axis=1)
    return wilder_rma(tr,period)

def wilder_adx(df,period=14):
    h,l,c=df.high,df.low,df.close
    up=h.diff(); down=-l.diff()
    pdm=pd.Series(np.where((up>down)&(up>0),up,0.0),index=df.index)
    mdm=pd.Series(np.where((down>up)&(down>0),down,0.0),index=df.index)
    tr=pd.concat([h-l,(h-c.shift(1)).abs(),(l-c.shift(1)).abs()],axis=1).max(axis=1)
    a=wilder_rma(tr,period)
    pdi=100*wilder_rma(pdm,period)/a
    mdi=100*wilder_rma(mdm,period)/a
    dx=100*(pdi-mdi).abs()/(pdi+mdi).replace(0,np.nan)
    return wilder_rma(dx,period)

def load_m15():
    d=pd.read_csv(DATA)
    d['time']=pd.to_datetime(d['time'],utc=True,errors='coerce')
    d=d.dropna(subset=['time','open','high','low','close']).sort_values('time').drop_duplicates('time')
    end=d.time.max(); start=end-pd.Timedelta(days=365)
    d=d[d.time>=start]
    return (d.set_index('time').resample('15min',label='left',closed='left')
            .agg({'open':'first','high':'max','low':'min','close':'last'}).dropna().reset_index()), start, end

def run(df, atr_mult=1.5, rr=2.5, ema_period=50, adx_min=22, min_atr=6,
        spread_points=20, slippage_points=0, indicator='ewm'):
    x=df.copy()
    if indicator=='wilder':
        x['atr']=wilder_atr(x,14); x['adx']=wilder_adx(x,14)
    else:
        x['atr']=ewm_atr(x,14); x['adx']=ewm_adx(x,14)
    x['ema']=ema(x.close,ema_period)
    x=x.dropna().reset_index(drop=True)
    spread=spread_points*POINT_VALUE; slip=slippage_points*POINT_VALUE
    pos=None; ts=0.0; trades=[]
    for i in range(2,len(x)):
        row=x.iloc[i]; p1=x.iloc[i-1]; p2=x.iloc[i-2]
        # Existing position management on current candle.
        if pos is not None:
            out=None
            if pos['side']=='buy':
                if row.low<=pos['sl']: out=(pos['sl']-slip,'SL')
                elif row.high>=pos['tp']: out=(pos['tp']-slip,'TP')
            else:
                if row.high>=pos['sl']: out=(pos['sl']+slip,'SL')
                elif row.low<=pos['tp']: out=(pos['tp']+slip,'TP')
            if out:
                ep,reason=out
                diff=ep-pos['entry'] if pos['side']=='buy' else pos['entry']-ep
                trades.append({'entry_time':pos['time'],'exit_time':row.time,'side':pos['side'],
                    'entry':pos['entry'],'sl':pos['sl'],'tp':pos['tp'],'n_loss':pos['risk'],
                    'r':diff/pos['risk'],'reason':reason})
                pos=None
        if p1.atr<min_atr or p1.adx<adx_min: continue
        nloss=atr_mult*p1.atr
        prev=ts
        if p1.close>prev and p2.close>prev: ts=max(prev,p1.close-nloss)
        elif p1.close<prev and p2.close<prev: ts=min(prev,p1.close+nloss)
        elif p1.close>prev: ts=p1.close-nloss
        else: ts=p1.close+nloss
        long_sig=p1.close>ts and p1.close>p1['ema']
        short_sig=p1.close<ts and p1.close<p1['ema']
        if pos is None and (long_sig or short_sig):
            if long_sig:
                entry=row.open+spread+slip; side='buy'; sl=entry-nloss; tp=entry+rr*nloss
            else:
                entry=row.open-spread-slip; side='sell'; sl=entry+nloss; tp=entry-rr*nloss
            pos={'side':side,'entry':float(entry),'sl':float(sl),'tp':float(tp),'risk':float(nloss),'time':row.time}
            # FIX: entry bar is tradable after the open. If its OHLC touches stop/target,
            # resolve conservatively stop-first on the same bar.
            out=None
            if side=='buy':
                if row.low<=sl: out=(sl-slip,'SL_ENTRY_BAR')
                elif row.high>=tp: out=(tp-slip,'TP_ENTRY_BAR')
            else:
                if row.high>=sl: out=(sl+slip,'SL_ENTRY_BAR')
                elif row.low<=tp: out=(tp+slip,'TP_ENTRY_BAR')
            if out:
                ep,reason=out
                diff=ep-entry if side=='buy' else entry-ep
                trades.append({'entry_time':row.time,'exit_time':row.time,'side':side,'entry':entry,
                    'sl':sl,'tp':tp,'n_loss':nloss,'r':diff/nloss,'reason':reason})
                pos=None
    return pd.DataFrame(trades)

def r_stats(t,risk=0.005):
    if t.empty:return {'trades':0}
    r=t.r.astype(float).to_numpy(); w=r[r>0]; l=r[r<=0]
    eq=10000.; peak=eq; dd=0.
    for q in r:
        eq*=1+risk*q; peak=max(peak,eq); dd=min(dd,(eq-peak)/peak*100)
    return {'trades':int(len(r)),'win_rate_pct':float((r>0).mean()*100),
        'profit_factor_R':float(w.sum()/abs(l.sum())) if len(l) else float('inf'),
        'expectancy_R':float(r.mean()),'sum_R':float(r.sum()),'risk_pct':risk*100,
        'return_pct':float((eq/10000-1)*100),'max_drawdown_pct':float(dd)}

def periods(t):
    z=t.copy(); z['dt']=pd.to_datetime(z.entry_time,utc=True)
    monthly=z.groupby(z.dt.dt.to_period('M')).r.sum()
    quarterly=z.groupby(z.dt.dt.to_period('Q')).r.sum()
    mid=z.dt.min()+(z.dt.max()-z.dt.min())/2
    return {'positive_months':int((monthly>0).sum()),'months':int(len(monthly)),
        'worst_month_R':float(monthly.min()),'best_month_R':float(monthly.max()),
        'worst_quarter_R':float(quarterly.min()),'best_quarter_R':float(quarterly.max()),
        'H1':r_stats(z[z.dt<=mid],0.005),'H2':r_stats(z[z.dt>mid],0.005),
        'monthly_R':{str(k):float(v) for k,v in monthly.items()}}

def monte_carlo(t,risk=0.005,n=2000,seed=42):
    r=t.r.astype(float).to_numpy(); rng=np.random.default_rng(seed)
    dds=[]; rets=[]
    for _ in range(n):
        p=rng.permutation(r); eq=1.; peak=1.; dd=0.
        for q in p:
            eq*=1+risk*q; peak=max(peak,eq); dd=min(dd,(eq-peak)/peak)
        dds.append(dd*100); rets.append((eq-1)*100)
    return {'runs':n,'risk_pct':risk*100,'dd_p50_pct':float(np.percentile(dds,50)),
        'dd_p95_worst_pct':float(np.percentile(dds,5)), 'dd_worst_pct':float(np.min(dds)),
        'return_p50_pct':float(np.percentile(rets,50))}

def main():
    df,start,end=load_m15()
    configs=[
      ('base',1.5,2.5,50,22,6,20,0,'ewm'),
      ('spread1_5x',1.5,2.5,50,22,6,30,0,'ewm'),
      ('spread2x',1.5,2.5,50,22,6,40,0,'ewm'),
      ('slip5',1.5,2.5,50,22,6,20,5,'ewm'),
      ('slip10',1.5,2.5,50,22,6,20,10,'ewm'),
      ('atr1_2',1.2,2.5,50,22,6,20,0,'ewm'),
      ('atr1_8',1.8,2.5,50,22,6,20,0,'ewm'),
      ('rr2_0',1.5,2.0,50,22,6,20,0,'ewm'),
      ('rr3_0',1.5,3.0,50,22,6,20,0,'ewm'),
      ('adx18',1.5,2.5,50,18,6,20,0,'ewm'),
      ('adx26',1.5,2.5,50,26,6,20,0,'ewm'),
      ('ema40',1.5,2.5,40,22,6,20,0,'ewm'),
      ('ema60',1.5,2.5,60,22,6,20,0,'ewm'),
      ('wilder_mt5like',1.5,2.5,50,22,6,20,0,'wilder'),
    ]
    out={}
    base_trades=None
    for name,am,rr,ep,ad,mina,sp,sl,ind in configs:
        t=run(df,am,rr,ep,ad,mina,sp,sl,ind)
        if name=='base': base_trades=t
        out[name]=r_stats(t,0.005)
        out[name]['params']={'atr_mult':am,'rr':rr,'ema':ep,'adx_min':ad,'spread_points':sp,'slippage_points':sl,'indicator':ind}
        print(name, json.dumps(out[name]))
    report={'strategy':'UT Bot final stress','data_start':str(start),'data_end':str(end),
        'entry_bar_fix':'enabled, stop-first if both touched','scenarios':out,
        'base_periods':periods(base_trades),
        'risk_sweep':{str(r):r_stats(base_trades,r/100) for r in (0.25,0.5,1.0)},
        'monte_carlo':{str(r):monte_carlo(base_trades,r/100) for r in (0.25,0.5,1.0)}}
    base=out['base']
    robust=sum(1 for k,v in out.items() if v.get('profit_factor_R',0)>=1.2 and v.get('expectancy_R',-1)>0)
    report['robust_scenarios_pass']=robust; report['robust_scenarios_total']=len(out)
    report['FINAL_SCREEN_PASS']=bool(base.get('profit_factor_R',0)>=1.2 and base.get('expectancy_R',0)>0 and abs(base.get('max_drawdown_pct',999))<=20 and report['base_periods']['H1'].get('expectancy_R',-1)>0 and report['base_periods']['H2'].get('expectancy_R',-1)>0 and out['spread2x'].get('profit_factor_R',0)>=1.2)
    base_trades.to_csv(OUT/'utbot_final_stress_trades.csv',index=False)
    with open(OUT/'utbot_final_stress.json','w') as f: json.dump(report,f,indent=2)
    print('=== UT BOT FINAL STRESS ==='); print(json.dumps(report,indent=2)); print('FINAL_SCREEN_PASS:',report['FINAL_SCREEN_PASS'])
if __name__=='__main__': main()
