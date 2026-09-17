#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
import numpy as np
UPSTREAM=Path("/tmp/xau-quant")
sys.path.insert(0,str(UPSTREAM))
from core.discover import load_series
from core.strategy import SWING
from research.features import build

OUT=Path(os.environ.get("GITHUB_WORKSPACE","."))/"research/python_xau_backtest/output"
OUT.mkdir(parents=True,exist_ok=True)

def stats(rows):
    if not rows:return {"trades":0}
    r=np.array([float(x["r"]) for x in rows])
    w=r[r>0]; l=r[r<0]; pf=float(w.sum()/abs(l.sum())) if len(l) else float("inf")
    eq=10000.; peak=eq; dd=0.
    for q in r: eq*=1+0.01*q; peak=max(peak,eq); dd=min(dd,(eq-peak)/peak*100)
    return {"trades":len(r),"win_rate_pct":float((r>0.05).mean()*100),
            "profit_factor_R":pf,"expectancy_R":float(r.mean()),"sum_R":float(r.sum()),
            "fixed_risk_1pct_return_pct":float((eq/10000-1)*100),"max_drawdown_pct":float(dd)}

def main():
    series=load_series("XAUUSD")
    if "M5" not in series or "M1" not in series: raise SystemExit("missing M1/M5 store")
    b=series["M5"]; end=int(b.time[-1]); start=end-365*86400
    since=int(np.searchsorted(np.asarray(b.time,np.int64),start,"left"))
    rows=build("XAUUSD",base="M5",target_r=8.0,hold_hours=24,series=series,since_bar=since,quiet=False)
    rows=[x for x in rows if int(b.time[int(x["bar"])])>=start]
    sel=SWING.select(rows)
    res=stats(sel); res["candidate_count"]=len(rows)
    res["strategy"]="Aarayanc49 frozen SWING via native feature/exit engine"
    res["data_start"]=str(np.datetime64(start,"s")); res["data_end"]=str(np.datetime64(end,"s"))
    res["spread_model"]="APPROX: synthetic feed spread 1.8p normal / 4.4p rollover, then native funded 1.67x scaling"
    if sel:
        ss=sorted(sel,key=lambda x:x["bar"]); m=len(ss)//2
        res["H1"]=stats(ss[:m]); res["H2"]=stats(ss[m:])
    with open(OUT/"quant_native_approx_metrics.json","w") as f: json.dump(res,f,indent=2)
    with open(OUT/"quant_native_approx_trades.json","w") as f: json.dump(sel,f)
    print("=== QUANT NATIVE APPROX 1Y ==="); print(json.dumps(res,indent=2))
    gate=(res.get("trades",0)>=50 and res.get("profit_factor_R",0)>=1.20 and res.get("expectancy_R",0)>0 and abs(res.get("max_drawdown_pct",-999))<=20)
    print("SCREEN_GATE:","PASS" if gate else "FAIL")
if __name__=="__main__":main()
