#!/usr/bin/env python3
import json
from pathlib import Path
import numpy as np
import pandas as pd

DATA=Path("research/python_xau_backtest/data/xauusd_m5.csv")
OUT=Path("research/python_xau_backtest/output"); OUT.mkdir(parents=True,exist_ok=True)
TZ="Asia/Kolkata"; RR=2.0; TOL=0.50; SWING=3; MIN_SL=0.30; MAX_SL=15.0; MAX_EXIT=300

def profile(x,bins=100,va=0.70):
    lo=float(x.low.min()); hi=float(x.high.max())
    if hi<=lo:return None
    edges=np.linspace(lo,hi,bins+1); vol=np.zeros(bins,float)
    for r in x.itertuples():
        if r.high<=r.low: continue
        a=max(0,min(bins-1,np.searchsorted(edges,r.low,side="right")-1))
        b=max(0,min(bins,np.searchsorted(edges,r.high,side="left")))
        touched=[]
        for i in range(a,b):
            ov=max(0,min(r.high,edges[i+1])-max(r.low,edges[i]))
            if ov>0:touched.append((i,ov))
        if touched:
            z=sum(v for _,v in touched)
            for i,v in touched:vol[i]+=float(r.tick_volume)*v/z
        else:
            i=max(0,min(bins-1,np.searchsorted(edges,r.close)-1)); vol[i]+=float(r.tick_volume)
    if vol.sum()<=0:return None
    p=int(np.argmax(vol)); acc=vol[p]; L=U=p; target=vol.sum()*va
    while acc<target and (L>0 or U<bins-1):
        lv=vol[L-1] if L>0 else -1; uv=vol[U+1] if U<bins-1 else -1
        if uv>lv: U+=1; acc+=vol[U]
        else: L-=1; acc+=vol[L]
    return {"POC":(edges[p]+edges[p+1])/2,"VAH":edges[U+1],"VAL":edges[L]}

def stats(t):
    if not t:return {"trades":0}
    r=np.array([x["r"] for x in t],float); w=r[r>0]; l=r[r<0]
    pf=float(w.sum()/abs(l.sum())) if len(l) else float("inf")
    eq=10000.0; peak=eq; dd=0.0
    for q in r:
        eq*=1+0.01*q; peak=max(peak,eq); dd=min(dd,(eq-peak)/peak*100)
    return {"trades":len(t),"win_rate_pct":float((r>0).mean()*100),"profit_factor_R":pf,
            "expectancy_R":float(r.mean()),"sum_R":float(r.sum()),
            "fixed_risk_1pct_return_pct":float((eq/10000-1)*100),"max_drawdown_pct":float(dd)}

def main():
    d=pd.read_csv(DATA); d["time"]=pd.to_datetime(d.time,utc=True)
    end=d.time.max(); start=end-pd.Timedelta(days=365); d=d[d.time>=start].copy()
    d["ist"]=d.time.dt.tz_convert(TZ); d["date"]=d.ist.dt.date
    trades=[]
    sessions=[("MORNING","03:30","06:00"),("US_OPEN","18:55","19:55")]
    for day,g in d.groupby("date",sort=True):
        g=g.sort_values("time")
        for sname,st,en in sessions:
            local_date=str(day)
            ss=pd.Timestamp(f"{local_date} {st}",tz=TZ); ee=pd.Timestamp(f"{local_date} {en}",tz=TZ)
            sess=g[(g.ist>=ss)&(g.ist<=ee)]
            if len(sess)<5: continue
            p=profile(sess)
            if not p: continue
            post=g[g.ist>ee]
            if len(post)<2: continue
            idxs=post.index.to_list()
            for k in range(1,len(idxs)-1):
                i=idxs[k]; prev=idxs[k-1]; nxt=idxs[k+1]
                row=d.loc[i]; prow=d.loc[prev]
                side=None; level_name=None; level=None
                for nm,lv in p.items():
                    if row.low<=lv+TOL and row.close>lv and prow.close<=lv:
                        side="BUY"; level_name=nm; level=lv; break
                    if row.high>=lv-TOL and row.close<lv and prow.close>=lv:
                        side="SELL"; level_name=nm; level=lv; break
                if not side: continue
                # FIX: close-confirmation first, entry at NEXT bar open
                entry=float(d.loc[nxt,"open"]); hist=d.loc[:i].tail(SWING)
                if side=="BUY":
                    sl=float(hist.low.min()); risk=entry-sl
                    tp=entry+RR*risk
                else:
                    sl=float(hist.high.max()); risk=sl-entry
                    tp=entry-RR*risk
                if risk<MIN_SL or risk>MAX_SL: continue
                future=d.loc[nxt:].head(MAX_EXIT)
                outcome=None; exitt=None
                for z in future.itertuples():
                    if side=="BUY":
                        hs=z.low<=sl; ht=z.high>=tp
                    else:
                        hs=z.high>=sl; ht=z.low<=tp
                    if hs: outcome=-1.0; exitt=z.time; break
                    if ht: outcome=RR; exitt=z.time; break
                if outcome is None: continue
                trades.append({"entry_time":str(d.loc[nxt,"time"]),"exit_time":str(exitt),"session":sname,
                               "level":level_name,"side":side,"entry":entry,"sl":sl,"tp":tp,"r":outcome})
                break
    t=pd.DataFrame(trades)
    if len(t): t.to_csv(OUT/"volume_profile_fixed_trades.csv",index=False)
    result=stats(trades); result["strategy"]="Volume Profile no-lookahead fixed"; result["data_start"]=str(start); result["data_end"]=str(end)
    if len(t):
        tt=t.copy(); tt["entry_time"]=pd.to_datetime(tt.entry_time,utc=True)
        mid=tt.entry_time.min()+(tt.entry_time.max()-tt.entry_time.min())/2
        result["H1"]=stats(tt[tt.entry_time<=mid].to_dict("records"))
        result["H2"]=stats(tt[tt.entry_time>mid].to_dict("records"))
        mo=tt.groupby(tt.entry_time.dt.to_period("M")).r.sum()
        result["positive_months"]=int((mo>0).sum()); result["months"]=int(len(mo))
    with open(OUT/"volume_profile_fixed_metrics.json","w") as f: json.dump(result,f,indent=2)
    print("=== VOLUME PROFILE FIXED 1Y ==="); print(json.dumps(result,indent=2))
    gate=(result.get("trades",0)>=100 and result.get("profit_factor_R",0)>=1.20 and result.get("expectancy_R",0)>0 and abs(result.get("max_drawdown_pct",-999))<=20)
    print("SCREEN_GATE:","PASS" if gate else "FAIL")
if __name__=="__main__": main()
