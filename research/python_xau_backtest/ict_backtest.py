#!/usr/bin/env python3
import json
from pathlib import Path
import numpy as np
import pandas as pd

DATA=Path("research/python_xau_backtest/data/xauusd_m5.csv")
OUT=Path("research/python_xau_backtest/output"); OUT.mkdir(parents=True,exist_ok=True)
MA_FAST=10; MA_SLOW=50; ATR_PERIOD=14
UTC_OFFSET=7; BROKER_UTC_OFFSET=3
TREND_DAYS={0,1,2}; MAX_AGE_M15=48
ATR_MIN=0.5; ATR_MAX=5.0; ATR_BUF=0.8

def bias(h):
    if len(h)<51:return "RANGING"
    f=h.close.tail(10).mean(); s=h.close.tail(50).mean(); c=h.close.iloc[-1]
    if c>f and c>s and f>s:return "BULLISH"
    if c<f and c<s and f<s:return "BEARISH"
    return "RANGING"

def pd_zone(h):
    if len(h)<50:return "EQUILIBRIUM"
    x=h.tail(50); hi=x.high.max(); lo=x.low.min(); c=h.close.iloc[-1]
    if hi==lo:return "EQUILIBRIUM"
    q=(c-lo)/(hi-lo)
    return "PREMIUM" if q>0.5 else "DISCOUNT" if q<0.5 else "EQUILIBRIUM"

def h4_structure(h):
    if len(h)<20:return "NEUTRAL"
    highs=[]; lows=[]
    for i in range(2,len(h)-2):
        if all(h.high.iloc[i]>h.high.iloc[j] for j in range(i-2,i+3) if j!=i): highs.append(h.high.iloc[i])
        if all(h.low.iloc[i]<h.low.iloc[j] for j in range(i-2,i+3) if j!=i): lows.append(h.low.iloc[i])
    if len(highs)>=2 and len(lows)>=2:
        if highs[-1]>highs[-2] and lows[-1]>lows[-2]:return "BULLISH"
        if highs[-1]<highs[-2] and lows[-1]<lows[-2]:return "BEARISH"
    return "NEUTRAL"

def atr(m):
    if len(m)<=14:return 0.0
    pc=m.close.shift(1)
    tr=pd.concat([(m.high-m.low),(m.high-pc).abs(),(m.low-pc).abs()],axis=1).max(axis=1)
    return float(tr.rolling(14).mean().iloc[-1])

def fvg(m,b):
    if len(m)<15:return None
    last=len(m)-1
    for i in range(last-1,max(2,last-15),-1):
        c1=m.iloc[i-2]; c3=m.iloc[i]
        if c3.low>c1.high:
            gt,gb=c3.low,c1.high; valid=True; ret=False
            for j in range(i+1,len(m)):
                z=m.iloc[j]
                if z.close<gb: valid=False; break
                if z.low<=gt: ret=True
            if valid and ret and b in ("BULLISH","RANGING"): return ("BUY",float(c1.low))
        if c3.high<c1.low:
            gt,gb=c1.low,c3.high; valid=True; ret=False
            for j in range(i+1,len(m)):
                z=m.iloc[j]
                if z.close>gt: valid=False; break
                if z.high>=gb: ret=True
            if valid and ret and b in ("BEARISH","RANGING"): return ("SELL",float(c1.high))
    return None

def stats(rows):
    if not rows:return {"trades":0}
    r=np.array([x["r"] for x in rows if x.get("r") is not None],float)
    if not len(r):return {"trades":len(rows),"closed":0}
    w=r[r>0]; l=r[r<0]; pf=float(w.sum()/abs(l.sum())) if len(l) else float("inf")
    eq=10000.; peak=eq; dd=0.
    for q in r: eq*=1+0.01*q; peak=max(peak,eq); dd=min(dd,(eq-peak)/peak*100)
    return {"trades":len(rows),"closed":len(r),"win_rate_pct":float((r>0).mean()*100),
            "profit_factor_R":pf,"expectancy_R":float(r.mean()),"sum_R":float(r.sum()),
            "fixed_risk_1pct_return_pct":float((eq/10000-1)*100),"max_drawdown_pct":float(dd)}

def main():
    d=pd.read_csv(DATA); d["time"]=pd.to_datetime(d.time,utc=True)
    end=d.time.max(); start=end-pd.Timedelta(days=365); d=d[d.time>=start].reset_index(drop=True)
    m15=(d.set_index("time").resample("15min",label="left",closed="left").agg({"open":"first","high":"max","low":"min","close":"last"}).dropna().reset_index())
    h4=(d.set_index("time").resample("4h",label="left",closed="left").agg({"open":"first","high":"max","low":"min","close":"last"}).dropna().reset_index())
    mt15=m15.time.values.astype("datetime64[ns]"); ht4=h4.time.values.astype("datetime64[ns]")
    trades=[]; open_trades=[]; trackers={"BUY":{},"SELL":{}}
    for i in range(100,len(d)):
        now=d.time.iloc[i]; hi=float(d.high.iloc[i]); lo=float(d.low.iloc[i])
        # outcome tracker, same precedence: SL -> TP2 -> TP1 -> expire
        for t in open_trades:
            if t["r"] is not None: continue
            age=(now-t["raw_time"]).total_seconds()/900
            if t["side"]=="BUY":
                if lo<=t["sl"]: t["r"]=-1.0
                elif hi>=t["tp2"]: t["r"]=2.0
                elif hi>=t["tp1"]: t["r"]=abs(t["tp1"]-t["entry"])/t["risk"]
            else:
                if hi>=t["sl"]: t["r"]=-1.0
                elif lo<=t["tp2"]: t["r"]=2.0
                elif lo<=t["tp1"]: t["r"]=abs(t["tp1"]-t["entry"])/t["risk"]
            if t["r"] is None and age>MAX_AGE_M15: t["r"]=0.0
        # repo timezone convention: broker-time +4h -> WIB
        local=now+pd.Timedelta(hours=UTC_OFFSET-BROKER_UTC_OFFSET)
        hr=local.hour
        session="LONDON" if 14<=hr<17 else "NY" if 19<=hr<23 else None
        if session is None: continue
        # CAUSAL FIX: only fully CLOSED M15/H4 bars are available.
        mcut=now-pd.Timedelta(minutes=15)
        hcut=now-pd.Timedelta(hours=4)
        mi=np.searchsorted(mt15,np.datetime64(mcut.to_datetime64()),side="right")
        hi4=np.searchsorted(ht4,np.datetime64(hcut.to_datetime64()),side="right")
        mm=m15.iloc[max(0,mi-60):mi].copy(); hh=h4.iloc[max(0,hi4-60):hi4].copy()
        if len(mm)<15 or len(hh)<51: continue
        b=bias(hh); z=fvg(mm,b)
        if not z: continue
        side,ext=z
        score=1 + (1 if (side=="BUY" and b=="BULLISH") or (side=="SELL" and b=="BEARISH") else 0) + 1
        if session=="LONDON":
            if local.weekday() not in TREND_DAYS or score<2: continue
        else:
            if score<3: continue
        prev=trackers[side]
        if prev.get("ext")==ext and prev.get("time") is not None and (local-prev["time"]).total_seconds()<900: continue
        entry=float(d.close.iloc[i])
        if (side=="BUY" and entry<ext) or (side=="SELL" and entry>ext): continue
        pz=pd_zone(hh); hs=h4_structure(hh)
        if side=="BUY" and pz!="DISCOUNT": continue
        if side=="SELL" and pz!="PREMIUM": continue
        if side=="BUY" and hs=="BEARISH": continue
        if side=="SELL" and hs=="BULLISH": continue
        a=atr(mm)
        if not np.isfinite(a) or a<=0: continue
        buf=a*ATR_BUF
        if side=="BUY":
            sl=round(ext-buf,2)
            if sl>=entry: sl=round(entry-buf-1.0,2)
        else:
            sl=round(ext+buf,2)
            if sl<=entry: sl=round(entry+buf+1.0,2)
        risk=abs(entry-sl)
        if risk<a*ATR_MIN or risk>a*ATR_MAX: continue
        trig=d.iloc[max(0,i-59):i+1]
        if side=="BUY":
            fallback=entry+risk; recent=float(trig.high.max()); tp1=round(recent if recent>fallback else fallback,2); tp2=round(entry+2*risk,2)
        else:
            fallback=entry-risk; recent=float(trig.low.min()); tp1=round(recent if recent<fallback else fallback,2); tp2=round(entry-2*risk,2)
        t={"raw_time":now,"entry_time":str(now),"local_time":str(local),"side":side,"session":session,"bias":b,
           "entry":entry,"sl":sl,"tp1":tp1,"tp2":tp2,"risk":risk,"r":None}
        trades.append(t); open_trades.append(t); trackers[side]={"ext":ext,"time":local}
    rows=[]
    for t in trades:
        q=t.copy(); q.pop("raw_time",None); rows.append(q)
    pd.DataFrame(rows).to_csv(OUT/"ict_fixed_trades.csv",index=False)
    res=stats(rows); res["strategy"]="ICT FVG causality-fixed"; res["data_start"]=str(start); res["data_end"]=str(end)
    closed=[x for x in rows if x.get("r") is not None]
    if closed:
        tt=pd.DataFrame(closed); tt["entry_time"]=pd.to_datetime(tt.entry_time,utc=True)
        mid=tt.entry_time.min()+(tt.entry_time.max()-tt.entry_time.min())/2
        res["H1"]=stats(tt[tt.entry_time<=mid].to_dict("records")); res["H2"]=stats(tt[tt.entry_time>mid].to_dict("records"))
    with open(OUT/"ict_fixed_metrics.json","w") as f: json.dump(res,f,indent=2)
    print("=== ICT FIXED 1Y ==="); print(json.dumps(res,indent=2))
    gate=(res.get("closed",0)>=100 and res.get("profit_factor_R",0)>=1.20 and res.get("expectancy_R",0)>0 and abs(res.get("max_drawdown_pct",-999))<=20)
    print("SCREEN_GATE:","PASS" if gate else "FAIL")
if __name__=="__main__":main()
