//+------------------------------------------------------------------+
//|                  SynapseTrailPro_Scalper.mq5                     |
//|         XAUUSD High-Frequency Scalping Expert Advisor             |
//|   Signal Engine: Synapse Trail Pro [WillyAlgoTrader]              |
//|   Features: Order Split | Fast Breakeven | Basket Cut | Spread    |
//+------------------------------------------------------------------+
#property copyright "AI Trading Bot"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input groups
input group              "=== Trail Signal ==="
input int                InpATRPeriod     = 13;       // ATR Period
input double             InpATRMult       = 1.618;    // ATR Multiplier
input int                InpEMAPeriod     = 21;       // Trail EMA Period
input bool               InpUseRatchet    = true;     // Ratchet (tighten only)

input group              "=== Order Split ==="
input double             InpLotSplit      = 0.02;     // Lot size per split
input int                InpTP1Points     = 100;      // TP1 distance (points)
input int                InpTP2Points     = 250;      // TP2 distance (points)
input int                InpBEBuffer      = 10;       // Breakeven buffer (points)

input group              "=== Risk Management ==="
input double             InpBasketLossUSD = 50.0;     // Max basket loss (USD)
input int                InpMaxSpread     = 30;       // Max spread (points)

input group              "=== System ==="
input long               InpMagic         = 20240101; // Magic Number

//--- Trade object
CTrade g_trade;

//--- Indicator handles
int g_hATR = INVALID_HANDLE;
int g_hEMA = INVALID_HANDLE;

//--- Trail state (persistent between ticks)
double   g_upperBand = 0.0;
double   g_lowerBand = 0.0;
int      g_dir       = 0;         // 1=long, -1=short, 0=undefined
datetime g_lastBar   = 0;

//--- Order pair tracking for breakeven
struct SOrderPair
{
   ulong  tp1Ticket;
   ulong  tp2Ticket;
   double entryPrice;
   int    direction;   // 1=buy, -1=sell
   bool   tp1Done;     // true once TP1 order has closed
};

#define MAX_PAIRS 100
SOrderPair g_pairs[MAX_PAIRS];
int        g_pairCount = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Alert("ERROR: Hedging account required for split orders.");
      return INIT_FAILED;
   }

   if(InpTP1Points >= InpTP2Points)
   {
      Alert("ERROR: TP1 must be smaller than TP2.");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   g_hATR = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_hATR == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create ATR handle");
      return INIT_FAILED;
   }

   g_hEMA = iMA(_Symbol, _Period, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hEMA == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create EMA handle");
      return INIT_FAILED;
   }

   InitTrailState();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_hATR != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hEMA != INVALID_HANDLE) IndicatorRelease(g_hEMA);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // PRIORITY 1: basket drawdown — runs every tick, no exceptions
   if(CheckBasketDrawdown()) return;

   // PRIORITY 2: breakeven check — runs every tick
   CheckBreakeven();

   // PRIORITY 3: one-signal-per-bar guard via bar time
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == g_lastBar) return;
   g_lastBar = barTime;

   // PRIORITY 4: spread filter
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
   {
      PrintFormat("Spread %d > max %d — bar skipped", (int)spread, InpMaxSpread);
      return;
   }

   // PRIORITY 5: trail update + signal detection (on closed bar[1])
   bool buySignal  = false;
   bool sellSignal = false;
   UpdateTrail(buySignal, sellSignal);

   // PRIORITY 6: execute
   if(buySignal)       OpenSplitOrder(ORDER_TYPE_BUY);
   else if(sellSignal) OpenSplitOrder(ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
//| Warm-up: compute trail bands over recent history                  |
//+------------------------------------------------------------------+
void InitTrailState()
{
   int barsNeeded = MathMax(InpATRPeriod, InpEMAPeriod) * 3 + 50;
   int calcBars   = BarsCalculated(g_hATR);
   if(calcBars < barsNeeded) barsNeeded = calcBars - 2;
   if(barsNeeded < 5) { Print("Not enough bars for trail init"); return; }

   double atrBuf[], emaBuf[], closeBuf[];
   ArraySetAsSeries(atrBuf,   false);
   ArraySetAsSeries(emaBuf,   false);
   ArraySetAsSeries(closeBuf, false);

   // Copy from bar[1] backwards (skip bar[0] which is incomplete)
   // With AS_SERIES=false: array[0]=oldest, array[N-1]=bar[1] (just closed)
   int c1 = CopyBuffer(g_hATR, 0, 1, barsNeeded, atrBuf);
   int c2 = CopyBuffer(g_hEMA, 0, 1, barsNeeded, emaBuf);
   int c3 = CopyClose(_Symbol, _Period, 1, barsNeeded, closeBuf);

   int bars = MathMin(c1, MathMin(c2, c3));
   if(bars < 3) { Print("CopyBuffer failed in InitTrailState"); return; }

   // Seed from oldest bar
   g_upperBand = emaBuf[0] + atrBuf[0] * InpATRMult;
   g_lowerBand = emaBuf[0] - atrBuf[0] * InpATRMult;
   g_dir       = (closeBuf[0] > g_upperBand) ? 1 : (closeBuf[0] < g_lowerBand) ? -1 : 0;

   // Walk chronologically from i=1 (older) to i=bars-1 (bar[1])
   for(int i = 1; i < bars; i++)
   {
      double rawUpper = emaBuf[i] + atrBuf[i] * InpATRMult;
      double rawLower = emaBuf[i] - atrBuf[i] * InpATRMult;

      int prevDir = g_dir;
      int newDir  = g_dir;
      if(closeBuf[i] > g_upperBand) newDir = 1;
      else if(closeBuf[i] < g_lowerBand) newDir = -1;

      ApplyRatchet(rawUpper, rawLower, newDir, prevDir);
      g_dir = newDir;
   }

   PrintFormat("Trail init OK: Dir=%d Upper=%.5f Lower=%.5f", g_dir, g_upperBand, g_lowerBand);
}

//+------------------------------------------------------------------+
//| Apply ratchet logic and update g_upperBand / g_lowerBand          |
//+------------------------------------------------------------------+
void ApplyRatchet(double rawUpper, double rawLower, int newDir, int prevDir)
{
   if(InpUseRatchet)
   {
      if(newDir == 1)
      {
         // Long mode: lower band only moves UP (ratchet), upper band free
         g_lowerBand = (newDir != prevDir) ? rawLower : MathMax(rawLower, g_lowerBand);
         g_upperBand = rawUpper;
      }
      else if(newDir == -1)
      {
         // Short mode: upper band only moves DOWN (ratchet), lower band free
         g_upperBand = (newDir != prevDir) ? rawUpper : MathMin(rawUpper, g_upperBand);
         g_lowerBand = rawLower;
      }
      else
      {
         g_upperBand = rawUpper;
         g_lowerBand = rawLower;
      }
   }
   else
   {
      g_upperBand = rawUpper;
      g_lowerBand = rawLower;
   }
}

//+------------------------------------------------------------------+
//| Update trail on each new bar and detect direction flips           |
//+------------------------------------------------------------------+
void UpdateTrail(bool &buySignal, bool &sellSignal)
{
   buySignal  = false;
   sellSignal = false;

   double atrBuf[1], emaBuf[1], closeBuf[1];

   if(CopyBuffer(g_hATR, 0, 1, 1, atrBuf)         < 1) return;
   if(CopyBuffer(g_hEMA, 0, 1, 1, emaBuf)         < 1) return;
   if(CopyClose(_Symbol, _Period, 1, 1, closeBuf)  < 1) return;

   double rawUpper = emaBuf[0]  + atrBuf[0]  * InpATRMult;
   double rawLower = emaBuf[0]  - atrBuf[0]  * InpATRMult;
   double close1   = closeBuf[0];

   int prevDir = g_dir;
   int newDir  = g_dir;

   if(close1 > g_upperBand) newDir = 1;
   else if(close1 < g_lowerBand) newDir = -1;

   ApplyRatchet(rawUpper, rawLower, newDir, prevDir);
   g_dir = newDir;

   // Signal = explicit direction FLIP only (short→long or long→short)
   buySignal  = (newDir ==  1 && prevDir == -1);
   sellSignal = (newDir == -1 && prevDir ==  1);
}

//+------------------------------------------------------------------+
//| Open 2 split orders: TP1 (fast scalp) + TP2 (runner)             |
//+------------------------------------------------------------------+
void OpenSplitOrder(ENUM_ORDER_TYPE orderType)
{
   double pt     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double entry = (orderType == ORDER_TYPE_BUY) ?
                  SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
                  SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double tp1, tp2;
   if(orderType == ORDER_TYPE_BUY)
   {
      tp1 = NormalizeDouble(entry + InpTP1Points * pt, digits);
      tp2 = NormalizeDouble(entry + InpTP2Points * pt, digits);
   }
   else
   {
      tp1 = NormalizeDouble(entry - InpTP1Points * pt, digits);
      tp2 = NormalizeDouble(entry - InpTP2Points * pt, digits);
   }

   // Place TP1 order
   if(!g_trade.PositionOpen(_Symbol, orderType, InpLotSplit, entry, 0.0, tp1, "STP_TP1"))
   {
      PrintFormat("TP1 open FAILED: %d %s", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return;
   }
   ulong t1 = g_trade.ResultOrder();

   // Place TP2 order
   if(!g_trade.PositionOpen(_Symbol, orderType, InpLotSplit, entry, 0.0, tp2, "STP_TP2"))
   {
      PrintFormat("TP2 open FAILED: %d %s — closing TP1 #%I64u", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription(), t1);
      g_trade.PositionClose(t1);
      return;
   }
   ulong t2 = g_trade.ResultOrder();

   if(g_pairCount < MAX_PAIRS)
   {
      g_pairs[g_pairCount].tp1Ticket  = t1;
      g_pairs[g_pairCount].tp2Ticket  = t2;
      g_pairs[g_pairCount].entryPrice = entry;
      g_pairs[g_pairCount].direction  = (orderType == ORDER_TYPE_BUY) ? 1 : -1;
      g_pairs[g_pairCount].tp1Done    = false;
      g_pairCount++;
   }

   PrintFormat("%s SPLIT | Entry=%.5f | TP1=#%I64u @ %.5f | TP2=#%I64u @ %.5f",
               (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL",
               entry, t1, tp1, t2, tp2);
}

//+------------------------------------------------------------------+
//| Check if TP1 has closed; if so, activate breakeven on TP2        |
//+------------------------------------------------------------------+
void CheckBreakeven()
{
   double pt     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // Step 1: detect TP1 closure and move TP2 SL to breakeven
   for(int i = 0; i < g_pairCount; i++)
   {
      if(g_pairs[i].tp1Done) continue;

      if(!PositionSelectByTicket(g_pairs[i].tp1Ticket))
      {
         // TP1 position gone — activate breakeven on TP2
         g_pairs[i].tp1Done = true;

         if(PositionSelectByTicket(g_pairs[i].tp2Ticket))
         {
            double be;
            if(g_pairs[i].direction == 1)
               be = NormalizeDouble(g_pairs[i].entryPrice + InpBEBuffer * pt, digits);
            else
               be = NormalizeDouble(g_pairs[i].entryPrice - InpBEBuffer * pt, digits);

            double curTP = PositionGetDouble(POSITION_TP);

            if(g_trade.PositionModify(g_pairs[i].tp2Ticket, be, curTP))
               PrintFormat("BREAKEVEN activated | TP2 #%I64u | SL → %.5f", g_pairs[i].tp2Ticket, be);
            else
               PrintFormat("BREAKEVEN modify FAILED: %s", g_trade.ResultRetcodeDescription());
         }
      }
   }

   // Step 2: remove fully closed pairs from tracking array
   for(int i = g_pairCount - 1; i >= 0; i--)
   {
      bool t1Open = PositionSelectByTicket(g_pairs[i].tp1Ticket);
      bool t2Open = PositionSelectByTicket(g_pairs[i].tp2Ticket);

      if(!t1Open && !t2Open)
      {
         for(int j = i; j < g_pairCount - 1; j++)
            g_pairs[j] = g_pairs[j + 1];
         g_pairCount--;
      }
   }
}

//+------------------------------------------------------------------+
//| Sum all floating PnL; close all if loss exceeds threshold         |
//+------------------------------------------------------------------+
bool CheckBasketDrawdown()
{
   double totalPnL = 0.0;
   int    total    = PositionsTotal();

   for(int i = 0; i < total; i++)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      totalPnL += PositionGetDouble(POSITION_PROFIT);
   }

   if(totalPnL <= -InpBasketLossUSD)
   {
      PrintFormat("BASKET CUT | PnL=%.2f <= -%.2f | Closing all positions", totalPnL, InpBasketLossUSD);
      CloseAllPositions();
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Close all EA positions on this symbol                             |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      if(!g_trade.PositionClose(ticket))
         PrintFormat("Close FAILED #%I64u: %s", ticket, g_trade.ResultRetcodeDescription());
   }
   g_pairCount = 0;
}
//+------------------------------------------------------------------+
