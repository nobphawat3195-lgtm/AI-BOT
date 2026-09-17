#!/usr/bin/env python3
import json, math, os, sys
from pathlib import Path
import numpy as np
import pandas as pd

DATA_FILE = Path("research/python_xau_backtest/data/xauusd_m5.csv")
OUTDIR = Path("research/python_xau_backtest/output")
OUTDIR.mkdir(parents=True, exist_ok=True)

ACCOUNT_BALANCE = 500.0
ATR_PERIOD = 14
ATR_MULT_SL = 1.5
RR_RATIO = 2.5
EMA_PERIOD = 50
ADX_PERIOD = 14
ADX_MINIMUM = 22.0
MIN_ATR = 6.0
SPREAD_POINTS = 20
POINT_VALUE = 0.01
LOT_SIZE_UNIT = 100
BASE_LOT = 0.01
MAX_LOT = 0.03
MAX_RISK_PCT = 0.02
SCALE_UP_AFTER = 2
SCALE_UP_AFTER_2 = 4

def calc_atr(df, period=14):
    high, low, close = df["high"], df["low"], df["close"]
    tr = pd.concat([high-low,(high-close.shift(1)).abs(),(low-close.shift(1)).abs()], axis=1).max(axis=1)
    return tr.ewm(span=period, adjust=False).mean()

def calc_ema(s, period):
    return s.ewm(span=period, adjust=False).mean()

def calc_adx(df, period=14):
    high, low, close = df["high"], df["low"], df["close"]
    up = high.diff()
    down = -low.diff()
    plus_dm = np.where((up > down) & (up > 0), up, 0.0)
    minus_dm = np.where((down > up) & (down > 0), down, 0.0)
    tr = pd.concat([high-low,(high-close.shift(1)).abs(),(low-close.shift(1)).abs()], axis=1).max(axis=1)
    atr_s = tr.ewm(span=period, adjust=False).mean()
    plus_di = 100 * pd.Series(plus_dm,index=df.index).ewm(span=period,adjust=False).mean() / atr_s
    minus_di = 100 * pd.Series(minus_dm,index=df.index).ewm(span=period,adjust=False).mean() / atr_s
    dx = 100 * (plus_di-minus_di).abs()/(plus_di+minus_di).replace(0,np.nan)
    return dx.ewm(span=period, adjust=False).mean()

def get_lot_size(balance, consec_wins, consec_losses, sl_distance):
    if consec_wins >= SCALE_UP_AFTER_2:
        lot = 0.03
    elif consec_wins >= SCALE_UP_AFTER:
        lot = 0.02
    else:
        lot = BASE_LOT
    max_risk_amount = balance * MAX_RISK_PCT
    max_lot_by_risk = max_risk_amount / (sl_distance * LOT_SIZE_UNIT)
    lot = min(lot, max_lot_by_risk)
    lot = max(BASE_LOT, min(MAX_LOT, lot))
    return round(lot, 2)

def load_data():
    print("Loading:", DATA_FILE, flush=True)
    if not DATA_FILE.exists():
        raise RuntimeError(f"data file not found: {DATA_FILE}")
    df = pd.read_csv(DATA_FILE)
    cols = {str(c).lower().strip(): c for c in df.columns}
    if "time" not in cols and "timestamp" in cols:
        df["time"] = pd.to_datetime(df[cols["timestamp"]], unit="ms", utc=True, errors="coerce")
    elif "time" in cols:
        df["time"] = pd.to_datetime(df[cols["time"]], utc=True, errors="coerce")
    else:
        raise RuntimeError(f"missing time/timestamp column; got {list(df.columns)}")
    for c0 in ["open","high","low","close"]:
        if c0 not in cols:
            raise RuntimeError(f"missing column {c0}; got {list(df.columns)}")
    df = df.rename(columns={cols[k]:k for k in cols if k in ["open","high","low","close","volume","tick_volume"]})
    df = df.dropna(subset=["time","open","high","low","close"]).sort_values("time").drop_duplicates("time")
    latest = df["time"].max()
    start = latest - pd.Timedelta(days=365)
    df = df[df["time"] >= start].copy()
    print(f"M5 slice: {df['time'].min()} -> {df['time'].max()} | bars={len(df):,}", flush=True)
    m15 = (df.set_index("time")
             .resample("15min", label="left", closed="left")
             .agg({"open":"first","high":"max","low":"min","close":"last"}).dropna().reset_index())
    print(f"M15 bars={len(m15):,}", flush=True)
    return m15, start, latest

def backtest(df, spread_points=SPREAD_POINTS, slippage_points=0):
    df = df.copy()
    df["atr"] = calc_atr(df, ATR_PERIOD)
    df["ema50"] = calc_ema(df["close"], EMA_PERIOD)
    df["adx"] = calc_adx(df, ADX_PERIOD)
    df = df.dropna().reset_index(drop=True)

    trades=[]
    balance=ACCOUNT_BALANCE
    position=None
    trailing_stop=0.0
    spread=spread_points*POINT_VALUE
    slippage=slippage_points*POINT_VALUE
    consec_wins=0
    consec_losses=0
    equity=[balance]

    for i in range(2,len(df)):
        row=df.iloc[i]
        atr_val=df.iloc[i-1]["atr"]
        ema_val=df.iloc[i-1]["ema50"]
        adx_val=df.iloc[i-1]["adx"]
        close1=df.iloc[i-1]["close"]
        close2=df.iloc[i-2]["close"]

        if position is not None:
            exit_price=exit_reason=None
            if position["direction"]=="buy":
                if row["low"] <= position["sl"]:
                    exit_price,exit_reason=position["sl"]-slippage,"SL"
                elif row["high"] >= position["tp"]:
                    exit_price,exit_reason=position["tp"]-slippage,"TP"
            else:
                if row["high"] >= position["sl"]:
                    exit_price,exit_reason=position["sl"]+slippage,"SL"
                elif row["low"] <= position["tp"]:
                    exit_price,exit_reason=position["tp"]+slippage,"TP"
            if exit_price is not None:
                diff=(exit_price-position["entry"]) if position["direction"]=="buy" else (position["entry"]-exit_price)
                pnl=diff*position["lot"]*LOT_SIZE_UNIT
                risk_cash=position["n_loss"]*position["lot"]*LOT_SIZE_UNIT
                r_mult=pnl/risk_cash if risk_cash else 0.0
                balance += pnl
                if pnl>0:
                    consec_wins+=1; consec_losses=0
                else:
                    consec_losses+=1; consec_wins=0
                trades.append({
                    "entry_time":str(position["entry_time"]),
                    "exit_time":str(row["time"]),
                    "direction":position["direction"],
                    "entry":position["entry"],
                    "exit":exit_price,
                    "sl":position["sl"],"tp":position["tp"],
                    "lot":position["lot"],"pnl":pnl,"r":r_mult,
                    "reason":exit_reason
                })
                position=None

        if atr_val < MIN_ATR or adx_val < ADX_MINIMUM:
            equity.append(balance)
            continue

        n_loss=ATR_MULT_SL*atr_val
        prev_stop=trailing_stop
        if close1>prev_stop and close2>prev_stop:
            trailing_stop=max(prev_stop,close1-n_loss)
        elif close1<prev_stop and close2<prev_stop:
            trailing_stop=min(prev_stop,close1+n_loss)
        elif close1>prev_stop:
            trailing_stop=close1-n_loss
        else:
            trailing_stop=close1+n_loss

        long_signal=(close1>trailing_stop) and (close1>ema_val)
        short_signal=(close1<trailing_stop) and (close1<ema_val)

        if position is None:
            ask=row["open"]+spread+slippage
            bid=row["open"]-spread-slippage
            if long_signal:
                lot=get_lot_size(balance,consec_wins,consec_losses,n_loss)
                position={"direction":"buy","entry_time":row["time"],"entry":ask,
                          "sl":ask-n_loss,"tp":ask+n_loss*RR_RATIO,"lot":lot,"n_loss":n_loss}
            elif short_signal:
                lot=get_lot_size(balance,consec_wins,consec_losses,n_loss)
                position={"direction":"sell","entry_time":row["time"],"entry":bid,
                          "sl":bid+n_loss,"tp":bid-n_loss*RR_RATIO,"lot":lot,"n_loss":n_loss}
        equity.append(balance)

    return pd.DataFrame(trades), np.asarray(equity,float), balance

def metrics(trades,equity,final_balance):
    if trades.empty:
        return {"trades":0,"final_balance":final_balance}
    wins=trades[trades.pnl>0]; losses=trades[trades.pnl<=0]
    gross_profit=float(wins.pnl.sum())
    gross_loss=float(abs(losses.pnl.sum()))
    pf=gross_profit/gross_loss if gross_loss else float("inf")
    peak=np.maximum.accumulate(equity)
    dd=(equity-peak)/peak
    max_dd=float(dd.min()*100)
    r=trades["r"].to_numpy()
    return {
        "trades":int(len(trades)),
        "win_rate_pct":float((trades.pnl>0).mean()*100),
        "profit_factor":float(pf),
        "net_profit":float(trades.pnl.sum()),
        "return_pct":float((final_balance/ACCOUNT_BALANCE-1)*100),
        "final_balance":float(final_balance),
        "max_drawdown_pct":float(max_dd),
        "expectancy_R":float(np.mean(r)),
        "median_R":float(np.median(r)),
        "avg_win_R":float(wins.r.mean()) if len(wins) else None,
        "avg_loss_R":float(losses.r.mean()) if len(losses) else None
    }


def normalized_risk_metrics(trades, initial_balance=10000.0, risk_pct=0.01):
    """Replay the exact trade R-sequence with fixed fractional risk.
    This removes the repo's win-streak anti-martingale sizing from the screening DD.
    """
    if trades.empty:
        return {"initial_balance": initial_balance, "risk_pct": risk_pct,
                "final_balance": initial_balance, "return_pct": 0.0,
                "max_drawdown_pct": 0.0}
    bal = float(initial_balance)
    peak = bal
    max_dd = 0.0
    for r in trades["r"].astype(float):
        bal *= (1.0 + risk_pct * r)
        peak = max(peak, bal)
        dd = (bal - peak) / peak * 100.0
        max_dd = min(max_dd, dd)
    return {
        "initial_balance": initial_balance,
        "risk_pct": risk_pct,
        "final_balance": bal,
        "return_pct": (bal / initial_balance - 1.0) * 100.0,
        "max_drawdown_pct": max_dd,
    }


def r_metrics(trades):
    if trades.empty:
        return {"trades":0,"win_rate_pct":0.0,"profit_factor_R":0.0,"expectancy_R":0.0}
    r = trades["r"].astype(float)
    wins = r[r > 0]
    losses = r[r <= 0]
    gp = float(wins.sum())
    gl = float(abs(losses.sum()))
    return {
        "trades": int(len(r)),
        "win_rate_pct": float((r > 0).mean()*100),
        "profit_factor_R": float(gp/gl) if gl else float("inf"),
        "expectancy_R": float(r.mean()),
        "median_R": float(r.median())
    }

def monthly_consistency(trades):
    if trades.empty:
        return {"months":0,"positive_months":0,"positive_month_ratio":0.0,"best_month_R":0.0,"worst_month_R":0.0}
    t=trades.copy()
    t["entry_time"]=pd.to_datetime(t["entry_time"], utc=True)
    m=t.groupby(t["entry_time"].dt.to_period("M"))["r"].sum()
    return {
        "months": int(len(m)),
        "positive_months": int((m>0).sum()),
        "positive_month_ratio": float((m>0).mean()),
        "best_month_R": float(m.max()),
        "worst_month_R": float(m.min()),
        "monthly_R": {str(k): float(v) for k,v in m.items()}
    }

def half_year_oos(df):
    midpoint = df["time"].min() + (df["time"].max() - df["time"].min())/2
    out={}
    for name,part in [("H1",df[df["time"]<=midpoint]),("H2",df[df["time"]>midpoint])]:
        tr,eq,bal=backtest(part, spread_points=20, slippage_points=0)
        rm=r_metrics(tr)
        rm["normalized_fixed_risk_1pct"]=normalized_risk_metrics(tr,10000.0,0.01)
        rm["start"]=str(part["time"].min())
        rm["end"]=str(part["time"].max())
        out[name]=rm
    return out

def stress_suite(df):
    scenarios=[
        ("base_s20_slip0",20,0),
        ("spread30",30,0),
        ("spread40",40,0),
        ("spread60",60,0),
        ("slip5",20,5),
        ("slip10",20,10),
    ]
    out={}
    for name,sp,sl in scenarios:
        tr,eq,bal=backtest(df, spread_points=sp, slippage_points=sl)
        rm=r_metrics(tr)
        rm["normalized_fixed_risk_1pct"]=normalized_risk_metrics(tr,10000.0,0.01)
        rm["spread_points"]=sp
        rm["slippage_points"]=sl
        out[name]=rm
    return out

def main():
    df,start,end=load_data()
    trades,equity,final_balance=backtest(df)
    m=metrics(trades,equity,final_balance)
    m["stress_suite"]=stress_suite(df)
    m["half_year_oos"]=half_year_oos(df)
    m["monthly_consistency"]=monthly_consistency(trades)
    norm = normalized_risk_metrics(trades, initial_balance=10000.0, risk_pct=0.01)
    m["normalized_fixed_risk_1pct"] = norm
    m["data_start"]=str(start)
    m["data_end"]=str(end)
    m["strategy"]="shreyg19/xauusd-algo UT Bot v6 Python logic"
    m["timeframe"]="M15 resampled from public MT5 M5"
    m["notes"]=[
        "Replicates repo Python EMA/ATR/ADX ewm(span) semantics, not MT5 Wilder indicators.",
        "Replicates fixed synthetic spread = 20 points * 0.01 and original anti-martingale win-streak sizing.",
        "Same-candle SL/TP resolves SL first because SL branch is checked first."
    ]
    trades.to_csv(OUTDIR/"utbot_trades.csv",index=False)
    with open(OUTDIR/"utbot_metrics.json","w") as f: json.dump(m,f,indent=2)
    pd.DataFrame([{**{"scenario":k}, **v, "norm_return_pct":v["normalized_fixed_risk_1pct"]["return_pct"], "norm_dd_pct":v["normalized_fixed_risk_1pct"]["max_drawdown_pct"]} for k,v in m["stress_suite"].items()]).to_csv(OUTDIR/"utbot_stress.csv",index=False)
    print("\n=== UT BOT 1Y RESULT ===")
    print(json.dumps(m,indent=2))
    if m.get("trades",0) > 0:
        gate = (m["profit_factor"] >= 1.20 and abs(norm["max_drawdown_pct"]) <= 20 and m["expectancy_R"] > 0)
        print("SCREEN_GATE_NORMALIZED_1PCT:", "PASS" if gate else "FAIL")
    else:
        print("SCREEN_GATE: FAIL")
if __name__=="__main__":
    main()
