// XAU Adaptive Regime Grid v1 -- research implementation, not a profit claim.
// Read DESIGN_AND_TEST_PLAN_TH.md before compiling or enabling trading.
#property strict
#property version "1.00"
#include <Trade/Trade.mqh>

enum MARKET_REGIME { REGIME_RANGE, REGIME_TREND_UP, REGIME_TREND_DOWN,
                     REGIME_EXPANSION, REGIME_NEUTRAL };
enum LOT_MODE { LOT_FIXED, LOT_RISK_BASED };
enum EXIT_MODE { EXIT_ATR, EXIT_PROFIT_PERCENT };
enum NEWS_MODE { NEWS_OFF, NEWS_NATIVE, NEWS_CSV };
enum ENGINE_STATE { STATE_FLAT, STATE_ACTIVE, STATE_CLOSING, STATE_DAY_LOCK, STATE_FAULT };

input group "GENERAL"
input ulong MagicNumber=26091301;
input LOT_MODE LotMode=LOT_RISK_BASED;
input double FixedLot=0.01;
input group "TREND"
input double TrendADXThreshold=25.0;
input int SlopeLookback=5;
input double MinimumSlopeATR=0.10;
input group "GRID"
input int ATRPeriod=14;
input double GridATRMultiplier=0.7;
input int MaxGridLevels=4;
input bool EnableRangeMode=false;
input group "RISK"
input double MaxBasketRiskPercent=1.5;
input double MaxBasketLossPercent=1.5;
input double DailyLossLimitPercent=3.0;
input double MaxEquityDrawdownPercent=8.0;
input double HardStopATR=3.5;
input double CostReservePerLot=10.0; // round-turn fees, account currency/lot; not USD unless account is USD
input group "EXIT"
input EXIT_MODE BasketExitMode=EXIT_ATR;
input double BasketTP_ATR=0.4;
input double BasketProfitPercent=0.5;
input bool CloseOnRegimeFlip=true;
input group "SESSION"
input string AsianSession="";              // empty=disabled; HH:MM-HH:MM, broker time
input string LondonSession="08:00-17:00";  // example only: set to YOUR broker clock
input string NewYorkSession="13:00-22:00";
input group "FILTER"
input double ExpansionATRMultiplier=1.8;
input double ExpansionCandleMultiplier=2.5;
input int MaxSpreadPoints=40; // broker points, verify digits before using
input NEWS_MODE NewsMode=NEWS_OFF;
input int NewsBeforeMinutes=30;
input int NewsAfterMinutes=15;
input string NewsCSVFile="XAU_USD_high_impact.csv";
input group "DEBUG"
input bool DebugMode=false;

// Fixed research conventions, deliberately not optimized in v1.
const int RANGE_LEVELS=2;
const int ATR_BASELINE_BARS=50;
const int VWAP_OSCILLATION_BARS=12;
const ulong DEVIATION_POINTS=20;
const double RANGE_ADX=20.0;
const double PULLBACK_EMA_ATR=0.5;
const double MAX_VWAP_EXTENSION_ATR=1.5;
const double RANGE_ENTRY_ATR=0.8;
const double RANGE_MAX_EXTENSION_ATR=1.8;
const int MIN_FITNESS_TRADES=200;

CTrade trade;
int hE50[3],hE200[3],hATR[3],hADX[3];
ENUM_TIMEFRAMES frames[3]={PERIOD_M5,PERIOD_M15,PERIOD_H1};
struct SNAPSHOT {
 double e50[3],e200[3],atr[3],adx[3],slope[3];
 double close,low,high,vwap,atrMean;
 bool oscillating;
};
SNAPSHOT sig;
struct BASKET {
 int count,dir;
 double volume,average,profit,lastPrice,minVolume;
 long lastTime;
 bool valid;
};
BASKET basket;
MARKET_REGIME regime=REGIME_NEUTRAL;
ENGINE_STATE state=STATE_FLAT;
MqlTick quote;
bool ready=false,dayLocked=false,fault=false,closing=false,haveLock=false,tester=false;
string reason="Waiting for closed-bar data",prefix,lockKey;
double lockToken=0,dayEquity=0,peakEquity=0,basketEquity=0,basketSL=0,levelLot=0,filledVolume=0;
int basketLevels=0,basketCap=0,basketDir=0;
bool basketRange=false;
datetime dayStart=0,basketStart=0,lastBar=0,lastCloseTry=0;
int sessionStart[3],sessionEnd[3];
bool sessionEnabled[3];
datetime newsTimes[];
datetime lastNewsCheck=0;
bool cachedNewsBlocked=true;

// ---------------- Persistence / single owner ----------------
uint HashText(const string value) {
 uint hash=2166136261;
 for(int i=0;i<StringLen(value);i++) hash=(hash^(uint)StringGetCharacter(value,i))*16777619;
 return hash;
}
bool Put(const string key,const double value) {
 if(GlobalVariableSet(prefix+key,value)==0) {
  Print("Persistent state write failed: ",key," error=",GetLastError());
  fault=true; reason="Persistence failure"; return false;
 }
 return true;
}
double Get(const string key) { return GlobalVariableGet(prefix+key); }
void SaveState() {
 if(tester) return;
 Put("version",-1.0); GlobalVariablesFlush(); // interrupted snapshots fail closed
 Put("day",(double)dayStart); Put("dayeq",dayEquity); Put("peak",peakEquity);
 Put("locked",dayLocked?1.0:0.0); Put("fault",fault?1.0:0.0);
 Put("closing",closing?1.0:0.0); Put("beq",basketEquity); Put("sl",basketSL);
 Put("lot",levelLot); Put("filled",filledVolume); Put("levels",basketLevels); Put("cap",basketCap);
 Put("dir",basketDir); Put("range",basketRange?1.0:0.0);
 Put("start",(double)basketStart); Put("bar",(double)lastBar);
 Put("version",1.0); GlobalVariablesFlush();
}
bool LoadState() {
 if(tester || !GlobalVariableCheck(prefix+"version")) return false;
 string keys[]={"day","dayeq","peak","locked","fault","closing","beq","sl",
                "lot","filled","levels","cap","dir","range","start","bar"};
 for(int i=0;i<ArraySize(keys);i++) if(!GlobalVariableCheck(prefix+keys[i])) {
  fault=true; reason="Incomplete persistent state"; return false;
 }
 dayStart=(datetime)Get("day"); dayEquity=Get("dayeq"); peakEquity=Get("peak");
 dayLocked=(Get("locked")!=0); fault=(Get("fault")!=0); closing=(Get("closing")!=0);
 basketEquity=Get("beq"); basketSL=Get("sl"); levelLot=Get("lot");filledVolume=Get("filled");
 basketLevels=(int)Get("levels"); basketCap=(int)Get("cap"); basketDir=(int)Get("dir");
 basketRange=(Get("range")!=0); basketStart=(datetime)Get("start"); lastBar=(datetime)Get("bar");
 if(dayEquity<=0 || peakEquity<=0 || Get("version")!=1.0) {
  fault=true; reason="Invalid persistent baseline";
 }
 return true;
}
bool AcquireLock() {
 if(tester) return true;
 lockKey=prefix+"owner";
 if(!GlobalVariableTemp(lockKey)) return false;
 lockToken=(double)ChartID(); if(lockToken==0) lockToken=1;
 haveLock=GlobalVariableSetOnCondition(lockKey,lockToken,0.0);
 return haveLock;
}
void ReleaseLock() {
 if(!tester && haveLock) {
  if(!GlobalVariableSetOnCondition(lockKey,0.0,lockToken)) Print("Owner lock release failed");
  haveLock=false;
 }
}
void Reject(const string why) { reason=why; if(DebugMode) Print("REJECT: ",why); }
void StartClosing(const string why) {
 closing=true; reason=why;
 datetime b=iTime(_Symbol,PERIOD_M5,0);if(b>lastBar) lastBar=b;
 SaveState();
 Print("CLOSE BASKET: ",why);
}

// ---------------- Broker time / sessions ----------------
datetime TradingDay(const datetime stamp) {
 MqlDateTime t; if(!TimeToStruct(stamp,t)) return 0;
 t.hour=0;t.min=0;t.sec=0;return StructToTime(t);
}
bool ParseClock(const string s,int &minute) {
 if(StringLen(s)!=5 || StringSubstr(s,2,1)!=":") return false;
 for(int i=0;i<5;i++) if(i!=2) {
  ushort ch=StringGetCharacter(s,i); if(ch<48 || ch>57) return false;
 }
 int h=(int)StringToInteger(StringSubstr(s,0,2));
 int m=(int)StringToInteger(StringSubstr(s,3,2));
 if(h>23 || m>59) return false; minute=h*60+m;return true;
}
bool ParseSession(const string s,const int index) {
 sessionEnabled[index]=(s!=""); if(s=="") return true;
 if(StringLen(s)!=11 || StringSubstr(s,5,1)!="-") return false;
 return ParseClock(StringSubstr(s,0,5),sessionStart[index]) &&
        ParseClock(StringSubstr(s,6,5),sessionEnd[index]);
}
bool InSession() {
 MqlDateTime t; if(!TimeToStruct(TimeCurrent(),t)) return false;
 int m=t.hour*60+t.min;
 for(int i=0;i<3;i++) if(sessionEnabled[i]) {
  int a=sessionStart[i],b=sessionEnd[i];
  if(a==b || (a<b && m>=a && m<b) || (a>b && (m>=a || m<b))) return true;
 }
 return false;
}
bool MarketSessionOpen() {
 MqlDateTime t; if(!TimeToStruct(TimeCurrent(),t)) return false;
 int now=t.hour*3600+t.min*60+t.sec;
 for(int offset=0;offset<=1;offset++) {
  ENUM_DAY_OF_WEEK dow=(ENUM_DAY_OF_WEEK)((t.day_of_week-offset+7)%7);
  for(uint k=0;k<20;k++) {
   datetime from,to;
   if(!SymbolInfoSessionTrade(_Symbol,dow,k,from,to)) break;
   int a=(int)((long)from%86400),b=(int)((long)to%86400);
   if(offset==0) {
    if(a==b || (a<b && now>=a && now<b) || (a>b && now>=a)) return true;
   } else if(a>b && now<b) return true;
  }
 }
 return false; // no published schedule: fail closed for new entries
}
double SpreadPoints() { return (quote.ask-quote.bid)/_Point; }

// ---------------- Indicators and closed-bar session VWAP ----------------
bool BufferValue(const int handle,const int buffer,const int shift,double &value) {
 double a[1];
 if(handle==INVALID_HANDLE || CopyBuffer(handle,buffer,shift,1,a)!=1) return false;
 value=a[0]; return MathIsValidNumber(value) && value!=EMPTY_VALUE;
}
bool SessionVWAP(double &value,bool &oscillates) {
 datetime bar=iTime(_Symbol,PERIOD_M5,0),start=TradingDay(bar);
 if(bar<=start) return false;
 MqlRates rates[];
 int n=CopyRates(_Symbol,PERIOD_M5,start,bar-1,rates);
 if(n<3) return false; // midnight warm-up, do not use previous day's VWAP
 bool realVolume=true;
 for(int i=0;i<n;i++) if(rates[i].real_volume<=0) { realVolume=false;break; }
 double pv=0,volume=0; int above=0,below=0;
 for(int i=0;i<n;i++) { // CopyRates physical order: oldest -> newest
  if(rates[i].time<start || rates[i].time>=bar) continue;
  double v=realVolume?(double)rates[i].real_volume:(double)rates[i].tick_volume;
  if(v<=0) continue;
  pv+=((rates[i].high+rates[i].low+rates[i].close)/3.0)*v;volume+=v;
  if(i>=n-VWAP_OSCILLATION_BARS) {
   double causalVWAP=pv/volume;
   if(rates[i].close>causalVWAP) above++;
   if(rates[i].close<causalVWAP) below++;
  }
 }
 if(volume<=0) return false;
 value=pv/volume;oscillates=(above>=2 && below>=2);return true;
}
bool RefreshIndicators() {
 for(int i=0;i<3;i++) {
  double past=0;
  if(BarsCalculated(hE200[i])<200+SlopeLookback+2 ||
     !BufferValue(hE50[i],0,1,sig.e50[i]) || !BufferValue(hE200[i],0,1,sig.e200[i]) ||
     !BufferValue(hATR[i],0,1,sig.atr[i]) || !BufferValue(hADX[i],0,1,sig.adx[i]) ||
     !BufferValue(hE200[i],0,1+SlopeLookback,past) || sig.atr[i]<=0) return false;
  sig.slope[i]=(sig.e200[i]-past)/sig.atr[i];
 }
 double atrs[];
 if(CopyBuffer(hATR[0],0,2,ATR_BASELINE_BARS,atrs)!=ATR_BASELINE_BARS) return false;
 sig.atrMean=0;
 for(int i=0;i<ATR_BASELINE_BARS;i++) {
  if(!MathIsValidNumber(atrs[i]) || atrs[i]<=0 || atrs[i]==EMPTY_VALUE) return false;
  sig.atrMean+=atrs[i];
 }
 sig.atrMean/=ATR_BASELINE_BARS;
 MqlRates r[1]; if(CopyRates(_Symbol,PERIOD_M5,1,1,r)!=1) return false;
 sig.close=r[0].close;sig.low=r[0].low;sig.high=r[0].high;
 return SessionVWAP(sig.vwap,sig.oscillating);
}
bool StrongTrend(const int tf,const int direction) {
 return (direction*(sig.e50[tf]-sig.e200[tf])>0 &&
         direction*sig.slope[tf]>=MinimumSlopeATR && sig.adx[tf]>=TrendADXThreshold);
}
MARKET_REGIME DetectMarketRegime() {
 if(!ready) return REGIME_NEUTRAL;
 if(SpreadPoints()>MaxSpreadPoints || sig.atr[0]>sig.atrMean*ExpansionATRMultiplier ||
    sig.high-sig.low>sig.atr[0]*ExpansionCandleMultiplier) return REGIME_EXPANSION;
 if(StrongTrend(1,1) && !StrongTrend(2,-1)) return REGIME_TREND_UP;
 if(StrongTrend(1,-1) && !StrongTrend(2,1)) return REGIME_TREND_DOWN;
 if(sig.adx[1]<RANGE_ADX && MathAbs(sig.slope[1])<MinimumSlopeATR &&
    !StrongTrend(2,1) && !StrongTrend(2,-1) && sig.oscillating) return REGIME_RANGE;
 return REGIME_NEUTRAL;
}

// ---------------- Basket accounting / strict ownership ----------------
bool OwnPosition() {
 return PositionGetString(POSITION_SYMBOL)==_Symbol &&
        (ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber;
}
bool OwnOrder() {
 return OrderGetString(ORDER_SYMBOL)==_Symbol &&
        (ulong)OrderGetInteger(ORDER_MAGIC)==MagicNumber;
}
int OwnOrderCount() {
 int n=0;for(int i=OrdersTotal()-1;i>=0;i--) {
  if(OrderGetTicket(i)!=0 && OwnOrder()) n++;
 }return n;
}
void ScanBasket() {
 ZeroMemory(basket);basket.valid=true;basket.minVolume=DBL_MAX;
 double weighted=0;
 for(int i=PositionsTotal()-1;i>=0;i--) {
  ulong ticket=PositionGetTicket(i);if(ticket==0 || !OwnPosition()) continue;
  int d=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;
  if(basket.dir!=0 && basket.dir!=d) basket.valid=false;
  basket.dir=d;basket.count++;
  double v=PositionGetDouble(POSITION_VOLUME),p=PositionGetDouble(POSITION_PRICE_OPEN);
  basket.volume+=v;weighted+=v*p;basket.minVolume=MathMin(basket.minVolume,v);
  basket.profit+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
  long ms=PositionGetInteger(POSITION_TIME_MSC);
  if(ms>=basket.lastTime) {basket.lastTime=ms;basket.lastPrice=p;}
  double sl=PositionGetDouble(POSITION_SL);
  double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
  if(sl<=0 || (basketSL>0 && MathAbs(sl-basketSL)>tick*0.6)) basket.valid=false;
 }
 if(basket.volume>0) basket.average=weighted/basket.volume;
}
double GetBasketAveragePrice() {return basket.average;}
int GetBasketPositionCount() {return basket.count;}
double GetBasketProfit() {
 // Conservative net estimate: reserve full round-turn fees for all open lots.
 return basket.profit-CostReservePerLot*basket.volume;
}
double LossToStop(const int dir,const double volume,const double entry,const double sl) {
 double profit=0;
 if(!OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,volume,entry,sl,profit))
  return DBL_MAX;
 // Stress both entry and stop by the configured execution deviation. Gaps can exceed this.
 double adverse=0;
 if(!OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,volume,
                    entry,entry-dir*2.0*(double)DEVIATION_POINTS*_Point,adverse)) return DBL_MAX;
 return MathMax(0.0,-profit)+MathAbs(adverse)+CostReservePerLot*volume;
}
double CalculateBasketRisk() {
 double risk=0;
 for(int i=PositionsTotal()-1;i>=0;i--) {
  if(PositionGetTicket(i)==0 || !OwnPosition()) continue;
  double sl=PositionGetDouble(POSITION_SL);
  if(sl<=0) return DBL_MAX;
  int d=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
  double r=LossToStop(d,PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_PRICE_OPEN),sl);
  if(r==DBL_MAX) return DBL_MAX;
  risk+=r+MathMax(0.0,-PositionGetDouble(POSITION_SWAP));
 }
 return risk;
}
void ClearBasketState() {
 basketEquity=0;basketSL=0;levelLot=0;filledVolume=0;basketLevels=0;basketCap=0;basketDir=0;
 basketRange=false;basketStart=0;SaveState();
}

// ---------------- Risk engine (not gated by indicators/session/news) ----------------
double DailyDD() {
 if(dayEquity<=0) return 0;
 return MathMax(0.0,100.0*(dayEquity-AccountInfoDouble(ACCOUNT_EQUITY))/dayEquity);
}
double EquityDD() {
 if(peakEquity<=0) return 0;
 return MathMax(0.0,100.0*(peakEquity-AccountInfoDouble(ACCOUNT_EQUITY))/peakEquity);
}
void RiskProtection() {
 double equity=AccountInfoDouble(ACCOUNT_EQUITY);
 datetime today=TradingDay(TimeCurrent());
 if(today!=dayStart && today>0) {
  dayStart=today;dayEquity=equity;
  // Re-arm DD baseline ONLY after a triggered daily/equity lock, at a new day.
  if(dayLocked) {dayLocked=false;peakEquity=equity;}
  SaveState();
 }
 if(equity>peakEquity) {peakEquity=equity;SaveState();}
 if(!dayLocked && (DailyDD()>=DailyLossLimitPercent || EquityDD()>=MaxEquityDrawdownPercent)) {
  dayLocked=true;StartClosing("Daily/equity drawdown limit");
 }
 if(!closing && OwnOrderCount()>0) {fault=true;StartClosing("Unexpected owned order");}
 if(fault && !closing && (basket.count>0 || OwnOrderCount()>0)) StartClosing("Fault: close owned exposure");
 if(closing || basket.count==0) return;
 if(!basket.valid || basketSL<=0 || basketEquity<=0 || basket.dir!=basketDir ||
    basket.count!=basketLevels || basketLevels>basketCap || MathAbs(basket.volume-filledVolume)>1e-8) {
  fault=true;if(!closing) StartClosing("Basket state/SL/count mismatch");return;
 }
 if((basketDir>0 && quote.bid<=basketSL) || (basketDir<0 && quote.ask>=basketSL)) {
  if(!closing) StartClosing("Hard stop reached");return;
 }
 if(GetBasketProfit()<=-basketEquity*MaxBasketLossPercent/100.0) {
  if(!closing) StartClosing("Basket cash loss limit");return;
 }
 double limit=MathMin(basketEquity,equity)*MaxBasketRiskPercent/100.0;
 if(CalculateBasketRisk()>limit+0.01 && !closing) StartClosing("Actual stop risk exceeds budget");
}

// ---------------- Execution: close by ticket, retry partial failures ----------------
bool RetcodeOK() {
 uint r=trade.ResultRetcode();return r==TRADE_RETCODE_DONE || r==TRADE_RETCODE_DONE_PARTIAL;
}
void ExecutionError(const string operation) {
 Print(operation," failed/uncertain retcode=",trade.ResultRetcode()," ",
       trade.ResultRetcodeDescription()," terminal_error=",GetLastError());
}
void CloseBasket() {
 if(TimeCurrent()==lastCloseTry) return;lastCloseTry=TimeCurrent();
 for(int i=OrdersTotal()-1;i>=0;i--) {
  ulong ticket=OrderGetTicket(i);if(ticket==0 || !OwnOrder()) continue;
  bool ok=trade.OrderDelete(ticket);
  if(!ok || trade.ResultRetcode()!=TRADE_RETCODE_DONE) ExecutionError("OrderDelete");
 }
 for(int i=PositionsTotal()-1;i>=0;i--) {
  ulong ticket=PositionGetTicket(i);if(ticket==0 || !OwnPosition()) continue;
  bool ok=trade.PositionClose(ticket,DEVIATION_POINTS);
  if(!ok || !RetcodeOK()) ExecutionError("PositionClose");
 }
 ScanBasket();
 if(basket.count==0 && OwnOrderCount()==0) {
  closing=false;ClearBasketState();reason="Basket closed; wait for next M5 bar";
 }
}
double NormalizeLotDown(const double lot) {
 double minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
 double maximum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
 double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
 if(step<=0 || minimum<=0 || lot<minimum-1e-10) return 0;
 double v=NormalizeDouble(MathFloor((MathMin(lot,maximum)+1e-10)/step)*step,8);
 return v>=minimum-1e-10?v:0;
}
double StopPrice(const int d,const double entry,const double distance) {
 double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
 if(tick<=0) return 0;
 double raw=entry-d*distance;
 // Round towards entry; rounding must never increase the proposed loss.
 double stop=d>0?MathCeil(raw/tick)*tick:MathFloor(raw/tick)*tick;
 return NormalizeDouble(stop,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
}
bool ValidStops(const int d,const double sl) {
 double distance=d>0?quote.bid-sl:sl-quote.ask;
 long stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
 long freeze=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
 double minimum=(double)MathMax(stops,freeze)*_Point;
 return sl>0 && distance>=minimum+SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
}
bool AllowedDirection(const int d) {
 long mode=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
 if(mode==SYMBOL_TRADE_MODE_FULL) return true;
 return (d>0 && mode==SYMBOL_TRADE_MODE_LONGONLY) || (d<0 && mode==SYMBOL_TRADE_MODE_SHORTONLY);
}
bool MarginAndVolumeOK(const int d,const double v,const double entry) {
 double margin=0;
 if(!OrderCalcMargin(d>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,v,entry,margin)) return false;
 if(margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)*0.90) return false;
 double limit=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_LIMIT),all=0;
 if(limit<=0) return true;
 // Account-wide exposure only for broker volume-limit validation. No mutation of others.
 for(int i=PositionsTotal()-1;i>=0;i--) {
  if(PositionGetTicket(i)==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
  long type=PositionGetInteger(POSITION_TYPE);
  if((d>0 && type==POSITION_TYPE_BUY) || (d<0 && type==POSITION_TYPE_SELL)) all+=PositionGetDouble(POSITION_VOLUME);
 }
 for(int i=OrdersTotal()-1;i>=0;i--) {
  if(OrderGetTicket(i)==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
  ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
  bool buy=(type==ORDER_TYPE_BUY || type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT);
  if((d>0 && buy) || (d<0 && !buy)) all+=OrderGetDouble(ORDER_VOLUME_CURRENT);
 }
 return all+v<=limit+1e-10;
}

// ---------------- Optional news module ----------------
bool LoadNewsCSV() {
 if(NewsMode!=NEWS_CSV) return true;
 int file=FileOpen(NewsCSVFile,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
 if(file==INVALID_HANDLE) {Print("Cannot open news file: ",NewsCSVFile);return false;}
 int count=0;bool valid=true;
 while(!FileIsEnding(file)) {
  string line=FileReadString(file);StringTrimLeft(line);StringTrimRight(line);
  if(line=="" || StringSubstr(line,0,1)=="#") continue;
  datetime stamp=StringToTime(line);
  if(StringLen(line)!=16 || stamp<=0 || TimeToString(stamp,TIME_DATE|TIME_MINUTES)!=line) {valid=false;break;}
  if(ArrayResize(newsTimes,count+1)!=count+1) {valid=false;break;}
  newsTimes[count++]=stamp;
 }
 FileClose(file);
 if(!valid || count==0) {Print("News file invalid or empty");return false;}
 ArraySort(newsTimes);return true;
}
bool NewsBlocked() {
 if(NewsMode==NEWS_OFF) return false;
 datetime now=TimeCurrent(),from=now-NewsAfterMinutes*60,to=now+NewsBeforeMinutes*60;
 if(NewsMode==NEWS_CSV) {
  for(int i=0;i<ArraySize(newsTimes);i++) {
   if(newsTimes[i]>to) break;if(newsTimes[i]>=from) return true;
  }return false;
 }
 if(lastNewsCheck>0 && now-lastNewsCheck<30) return cachedNewsBlocked;
 lastNewsCheck=now;cachedNewsBlocked=true;
 MqlCalendarValue values[];ResetLastError();
 int n=CalendarValueHistory(values,from,to,NULL,"USD");
 if(n<0 || GetLastError()!=0) {Reject("Calendar unavailable: entries blocked");return true;}
 for(int i=0;i<n;i++) {
  MqlCalendarEvent e;
  if(!CalendarEventById(values[i].event_id,e)) return true;
  if(e.importance==CALENDAR_IMPORTANCE_HIGH) return true;
 }
 cachedNewsBlocked=false;return false;
}

// ---------------- Entry and grid engine ----------------
bool EntryGate(const int d) {
 if(fault || closing || dayLocked) {Reject("Risk lock");return false;}
 if(!ready || regime==REGIME_EXPANSION || regime==REGIME_NEUTRAL) {Reject("Regime/data blocks entry");return false;}
 if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) ||
    !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) {
  Reject("Algo trading disabled");return false;
 }
 if(!SymbolIsSynchronized(_Symbol) || !AllowedDirection(d) || !MarketSessionOpen()) {
  Reject("Symbol/direction/market unavailable");return false;
 }
 long orderMode=SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE);
 if((orderMode & SYMBOL_ORDER_MARKET)==0 || (orderMode & SYMBOL_ORDER_SL)==0) {
  Reject("Market orders or server SL unsupported");return false;
 }
 if(!InSession()) {Reject("Outside configured session");return false;}
 if(SpreadPoints()>MaxSpreadPoints) {Reject("Spread too wide");return false;}
 if(NewsBlocked()) {Reject("News block");return false;}
 if(OwnOrderCount()>0) {Reject("Owned order outstanding");return false;}
 return true;
}
bool CanAddGridPosition() {
 if(basket.count<=0 || basketLevels>=basketCap || !basket.valid) return false;
 if(!EntryGate(basketDir)) return false;
 if(basketRange) {if(regime!=REGIME_RANGE) return false;}
 else if((basketDir>0 && regime!=REGIME_TREND_UP) || (basketDir<0 && regime!=REGIME_TREND_DOWN)) return false;
 double entry=basketDir>0?quote.ask:quote.bid;
 if(basketDir*(basket.lastPrice-entry)<sig.atr[0]*GridATRMultiplier) return false;
 if(!ValidStops(basketDir,basketSL)) return false;
 double v=NormalizeLotDown(MathMin(levelLot,basket.minVolume));
 if(v<=0) return false;
 double added=LossToStop(basketDir,v,entry,basketSL),risk=CalculateBasketRisk();
 double budget=MathMin(basketEquity,AccountInfoDouble(ACCOUNT_EQUITY))*MaxBasketRiskPercent/100.0;
 return added!=DBL_MAX && risk!=DBL_MAX && risk+added<=budget && MarginAndVolumeOK(basketDir,v,entry);
}
void SendLevel(const int d,const double v) {
 // Re-read prices immediately before checking risk and submitting.
 if(!SymbolInfoTick(_Symbol,quote) || !EntryGate(d) || !ValidStops(d,basketSL)) return;
 double entry=d>0?quote.ask:quote.bid;
 if(basket.count>0 && d*(basket.lastPrice-entry)<sig.atr[0]*GridATRMultiplier) return;
 double added=LossToStop(d,v,entry,basketSL),risk=CalculateBasketRisk();
 double budget=MathMin(basketEquity,AccountInfoDouble(ACCOUNT_EQUITY))*MaxBasketRiskPercent/100.0;
 if(added==DBL_MAX || risk==DBL_MAX || added+risk>budget || !MarginAndVolumeOK(d,v,entry)) {
  Reject("Final risk/margin check");return;
 }
 // Persist a closing intent before request. A crash in the send window liquidates on restart.
 closing=true;SaveState();if(fault) return;
 ResetLastError();
 bool ok=trade.PositionOpen(_Symbol,d>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,v,entry,basketSL,0,
                           StringFormat("XARG1 %s L%d",basketRange?"R":"T",basketLevels+1));
 if(!ok || !RetcodeOK() || trade.ResultDeal()==0) {
  ExecutionError("PositionOpen");fault=true;reason="Uncertain/rejected entry: manual investigation";
  SaveState();return;
 }
 basketLevels++;
 filledVolume+=trade.ResultVolume();
 // Partial fills reduce subsequent levels; never compensate by increasing lot.
 if(trade.ResultVolume()>0) levelLot=MathMin(levelLot,trade.ResultVolume());
 closing=false;SaveState();ScanBasket();
 reason="Grid level filled";
 if(DebugMode) PrintFormat("ENTRY dir=%d level=%d volume=%.8f ATR=%.5f ADX=%.2f risk=%.2f",
                           d,basketLevels,v,sig.atr[0],sig.adx[1],CalculateBasketRisk());
 RiskProtection(); // actual fill risk may be greater than pre-trade estimate
}
void BeginBasket(const int d,const bool rangeMode) {
 if(!EntryGate(d)) return;
 double entry=d>0?quote.ask:quote.bid;
 int cap=rangeMode?(int)MathMin(RANGE_LEVELS,MaxGridLevels):MaxGridLevels;
 double sl=StopPrice(d,entry,HardStopATR*sig.atr[0]);
 if(!ValidStops(d,sl)) {Reject("Initial stop invalid");return;}
 double equity=AccountInfoDouble(ACCOUNT_EQUITY),perLot=LossToStop(d,1.0,entry,sl);
 if(perLot<=0 || perLot==DBL_MAX || equity<=0) {Reject("Cannot estimate stop loss");return;}
 // Conservative full-basket reservation: each future level charged the FIRST entry loss.
 double raw=LotMode==LOT_FIXED?FixedLot:equity*MaxBasketRiskPercent/100.0/(cap*perLot);
 double v=NormalizeLotDown(raw);
 if(v<=0 || v*perLot*cap>equity*MaxBasketRiskPercent/100.0) {
  Reject("Minimum/fixed lot cannot fit full basket budget");return;
 }
 if(!MarginAndVolumeOK(d,v,entry)) {Reject("Initial margin/volume limit");return;}
 basketEquity=equity;basketSL=sl;levelLot=v;basketCap=cap;basketDir=d;
 basketRange=rangeMode;basketStart=TimeCurrent();basketLevels=0;SaveState();
 SendLevel(d,v);
 if(!fault && !closing && basket.count==0) ClearBasketState();
}
void CheckEntry() {
 if(basket.count>0) {
  if(CanAddGridPosition()) SendLevel(basketDir,NormalizeLotDown(MathMin(levelLot,basket.minVolume)));
  else Reject("Grid blocked: spacing/regime/risk/level/filter");
  return;
 }
 int d=regime==REGIME_TREND_UP?1:(regime==REGIME_TREND_DOWN?-1:0);
 if(d!=0) {
  double executable=d>0?quote.ask:quote.bid;
  double vwapDist=d*(sig.close-sig.vwap)/sig.atr[0];
  double liveDist=d*(executable-sig.vwap)/sig.atr[0];
  bool touch=d>0?sig.low<=sig.e50[0]+PULLBACK_EMA_ATR*sig.atr[0]:
                       sig.high>=sig.e50[0]-PULLBACK_EMA_ATR*sig.atr[0];
  if(d*(sig.e50[0]-sig.e200[0])>0 && vwapDist>0 && vwapDist<=MAX_VWAP_EXTENSION_ATR &&
     liveDist>0 && liveDist<=MAX_VWAP_EXTENSION_ATR && touch &&
     MathAbs(sig.close-sig.e50[0])<=PULLBACK_EMA_ATR*sig.atr[0] &&
     MathAbs(executable-sig.e50[0])<=PULLBACK_EMA_ATR*sig.atr[0]) BeginBasket(d,false);
  else Reject("No non-extended trend pullback");
 } else if(EnableRangeMode && regime==REGIME_RANGE) {
  double distance=(sig.close-sig.vwap)/sig.atr[0];
  if(MathAbs(distance)>=RANGE_ENTRY_ATR && MathAbs(distance)<=RANGE_MAX_EXTENSION_ATR) {
   d=distance<0?1:-1;double p=d>0?quote.ask:quote.bid;
   double live=-d*(p-sig.vwap)/sig.atr[0];
   if(live>=RANGE_ENTRY_ATR && live<=RANGE_MAX_EXTENSION_ATR) BeginBasket(d,true);
  } else Reject("No range displacement");
 } else Reject("No enabled regime");
}

// ---------------- Basket exits ----------------
void BasketManagement() {
 if(closing || basket.count==0 || basketEquity<=0) return;
 if(BasketExitMode==EXIT_PROFIT_PERCENT) {
  double target=AccountInfoDouble(ACCOUNT_EQUITY)*BasketProfitPercent/100.0;
  if(GetBasketProfit()>=target) StartClosing("Basket net profit percent");
 } else {
  double atr=0; // Risk/exit remains available even during daily VWAP warm-up.
  if(BufferValue(hATR[0],0,1,atr) && atr>0) {
   double tp=GetBasketAveragePrice()+basketDir*atr*BasketTP_ATR;
   bool reached=basketDir>0?quote.bid>=tp:quote.ask<=tp;
   if(reached && GetBasketProfit()>0) StartClosing("ATR basket TP after estimated fees");
  }
 }
}

// ---------------- Panel / lifecycle ----------------
void Panel() {
 if(MQLInfoInteger(MQL_OPTIMIZATION)) return;
 state=fault?STATE_FAULT:(closing?STATE_CLOSING:(dayLocked?STATE_DAY_LOCK:
       (basket.count>0?STATE_ACTIVE:STATE_FLAT)));
 Comment("XAU Adaptive Regime Grid v1\nState: ",EnumToString(state),
         "\nRegime: ",EnumToString(regime)," | Direction: ",basketDir,
         "\nGrid: ",basket.count,"/",basketCap," | Net est: ",DoubleToString(GetBasketProfit(),2),
         "\nSpread: ",DoubleToString(SpreadPoints(),1)," points",
         "\nDaily DD: ",DoubleToString(DailyDD(),2),"% | Equity DD: ",DoubleToString(EquityDD(),2),"%",
         "\nTrading: ",(!fault && !closing && !dayLocked && ready)?"ARMED (filters apply)":"DISABLED",
         "\n",reason);
}
bool ValidateInputs() {
 if(MagicNumber==0 || FixedLot<=0 || ATRPeriod<2 || ATRPeriod>100 || SlopeLookback<1 ||
    SlopeLookback>100 || TrendADXThreshold<=RANGE_ADX || TrendADXThreshold>70 ||
    MinimumSlopeATR<=0 || GridATRMultiplier<=0 || MaxGridLevels<1 || MaxGridLevels>8 ||
    MaxBasketRiskPercent<=0 || MaxBasketLossPercent<MaxBasketRiskPercent ||
    DailyLossLimitPercent<=0 || DailyLossLimitPercent>=100 || MaxEquityDrawdownPercent<=0 ||
    MaxEquityDrawdownPercent>=100 || MaxBasketLossPercent>=100 || CostReservePerLot<0 ||
    HardStopATR<=(MaxGridLevels-1)*GridATRMultiplier+0.25 || BasketTP_ATR<=0 ||
    BasketProfitPercent<=0 || ExpansionATRMultiplier<=1 || ExpansionCandleMultiplier<=1 ||
    MaxSpreadPoints<=0 || NewsBeforeMinutes<0 || NewsAfterMinutes<0 ||
    NewsBeforeMinutes>1440 || NewsAfterMinutes>1440) return false;
 return ParseSession(AsianSession,0) && ParseSession(LondonSession,1) && ParseSession(NewYorkSession,2) &&
        (sessionEnabled[0] || sessionEnabled[1] || sessionEnabled[2]);
}
void ReleaseIndicators() {
 for(int i=0;i<3;i++) {
  if(hE50[i]!=INVALID_HANDLE) {if(!IndicatorRelease(hE50[i])) Print("Release EMA50 failed");}
  if(hE200[i]!=INVALID_HANDLE) {if(!IndicatorRelease(hE200[i])) Print("Release EMA200 failed");}
  if(hATR[i]!=INVALID_HANDLE) {if(!IndicatorRelease(hATR[i])) Print("Release ATR failed");}
  if(hADX[i]!=INVALID_HANDLE) {if(!IndicatorRelease(hADX[i])) Print("Release ADX failed");}
 }
}
int OnInit() {
 for(int i=0;i<3;i++) {hE50[i]=INVALID_HANDLE;hE200[i]=INVALID_HANDLE;hATR[i]=INVALID_HANDLE;hADX[i]=INVALID_HANDLE;}
 tester=(bool)MQLInfoInteger(MQL_TESTER);
 if(!ValidateInputs()) {Print("Invalid parameters/session or stop too close for grid geometry");return INIT_PARAMETERS_INCORRECT;}
 if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
  Print("v1 requires a HEDGING account to guarantee position ownership");return INIT_FAILED;
 }
 if(StringFind(_Symbol,"XAU")<0) {Print("Attach to an XAU symbol (broker suffix supported)");return INIT_FAILED;}
 if(tester && NewsMode==NEWS_NATIVE) {Print("Native calendar unsupported in tester: use OFF or supplied CSV");return INIT_PARAMETERS_INCORRECT;}
 if(!LoadNewsCSV()) return INIT_FAILED;
 string identity=StringFormat("%I64d|%s|%s|%I64u",AccountInfoInteger(ACCOUNT_LOGIN),
                              AccountInfoString(ACCOUNT_SERVER),_Symbol,MagicNumber);
 prefix=StringFormat("XARG1.%u.%u.",HashText(identity),HashText("namespace|"+identity));
 if(!AcquireLock()) {Print("Another instance owns this symbol/magic, or stale owner lock");return INIT_FAILED;}
 trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(DEVIATION_POINTS);trade.SetAsyncMode(false);
 if(!trade.SetTypeFillingBySymbol(_Symbol)) {Print("Cannot select symbol filling policy");ReleaseLock();return INIT_FAILED;}
 for(int i=0;i<3;i++) {
  hE50[i]=iMA(_Symbol,frames[i],50,0,MODE_EMA,PRICE_CLOSE);
  hE200[i]=iMA(_Symbol,frames[i],200,0,MODE_EMA,PRICE_CLOSE);
  hATR[i]=iATR(_Symbol,frames[i],ATRPeriod);hADX[i]=iADX(_Symbol,frames[i],14);
  if(hE50[i]==INVALID_HANDLE || hE200[i]==INVALID_HANDLE || hATR[i]==INVALID_HANDLE || hADX[i]==INVALID_HANDLE) {
   Print("Indicator handle creation failed");ReleaseLock();return INIT_FAILED;
  }
 }
 Print("Persistent state prefix: ",prefix);
 bool restored=LoadState();ScanBasket();
 if(!restored) {
  dayStart=TradingDay(TimeCurrent());dayEquity=AccountInfoDouble(ACCOUNT_EQUITY);peakEquity=dayEquity;
  if(basket.count>0 || OwnOrderCount()>0) {fault=true;closing=true;reason="Owned exposure without recovery metadata";}
 }
 if(OwnOrderCount()>0) {fault=true;closing=true;reason="Unexpected outstanding own order";}
 // Do not enter midway through a bar after attach/restart. Persisted bar prevents duplicates.
 datetime currentBar=iTime(_Symbol,PERIOD_M5,0);
 if(currentBar>lastBar) lastBar=currentBar;
 SaveState();Print("XARG1 initialized; research build; native compilation/testing required.");return INIT_SUCCEEDED;
}
void OnDeinit(const int why) {
 if(haveLock || tester) SaveState();
 ReleaseIndicators();ReleaseLock();Comment("");
}
void OnTick() {
 if(!SymbolInfoTick(_Symbol,quote) || quote.bid<=0 || quote.ask<quote.bid) return;
 ScanBasket();RiskProtection();
 if(closing) {CloseBasket();Panel();return;}
 if(basket.count==0 && basketLevels>0) ClearBasketState();
 BasketManagement();if(closing) {CloseBasket();Panel();return;}
 datetime bar=iTime(_Symbol,PERIOD_M5,0);
 if(bar>0 && bar!=lastBar) {
  lastBar=bar;SaveState(); // one attempt per bar even when broker rejects a request
  ready=RefreshIndicators();regime=DetectMarketRegime();
  if(DebugMode) PrintFormat("BAR regime=%s ATR=%.5f ADX=%.2f spread=%.1f levels=%d PL=%.2f risk=%.2f dailyDD=%.2f equityDD=%.2f",
      EnumToString(regime),sig.atr[0],sig.adx[1],SpreadPoints(),basketLevels,GetBasketProfit(),CalculateBasketRisk(),DailyDD(),EquityDD());
  if(ready && basket.count>0 && CloseOnRegimeFlip &&
     ((basketDir>0 && regime==REGIME_TREND_DOWN) || (basketDir<0 && regime==REGIME_TREND_UP)))
   StartClosing("Confirmed opposite regime");
  if(!closing && !fault && !dayLocked && ready) CheckEntry();
  if(closing) CloseBasket();
 }
 Panel();
}

// ---------------- Conservative optimization score ----------------
double OnTester() {
 double profit=TesterStatistics(STAT_PROFIT),pf=TesterStatistics(STAT_PROFIT_FACTOR);
 double equityLoss=TesterStatistics(STAT_EQUITY_DD);
 double recovery=equityLoss>0?profit/equityLoss:0; // equity recovery, never balance-only recovery
 double dd=TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
 double trades=TesterStatistics(STAT_TRADES);
 if(!MathIsValidNumber(pf) || !MathIsValidNumber(recovery) || profit<=0 || pf<1.0 || recovery<=0 || trades<=0) return -1.0;
 // Count here is MT5 position trades, not independent baskets. Evaluate basket counts offline.
 double quality=MathMin(1.0,trades/(double)MIN_FITNESS_TRADES);
 double score=MathMin(pf,5.0)*MathMin(recovery,10.0)*quality/(1.0+dd/5.0);
 if(dd>MaxEquityDrawdownPercent) score*=0.1;
 if(fault || closing || OwnOrderCount()>0) score*=0.01;
 return score;
}
