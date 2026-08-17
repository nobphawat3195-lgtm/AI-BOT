//+------------------------------------------------------------------+
//|                                           GoldScalperPro_V2.mq5   |
//|                  StealthTrail SuperTrend ML Pro Signal Engine     |
//|                                                                   |
//|  EA สำหรับเทรด Gold (XAUUSD) แบบ Scalping                          |
//|  ใช้สัญญาณ SuperTrend ML Pro แปลงมาจาก Pine Script                 |
//+------------------------------------------------------------------+
#property copyright "GoldScalperPro"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| === การตั้งค่าหลัก (Core Settings) ===                            |
//+------------------------------------------------------------------+
input group "=== Core Settings ==="
input long   MagicNumber          = 20240526;   // Magic Number ระบุ EA
input int    Slippage             = 10;          // Slippage (points) ค่าคลาดเคลื่อนราคา
input double BaseLotSize          = 0.01;        // Lot เริ่มต้น
input int    MaxDailyTrades       = 20;          // จำนวนเทรดสูงสุดต่อวัน
input double MaxSpreadPips        = 3.0;         // Spread สูงสุดที่ยอมรับ (Pips)
input int    TakeProfitPoints     = 200;         // Take Profit (points)
input int    StopLossPoints       = 200;         // Stop Loss (points)
input bool   OneTradePerBar       = true;        // เปิดได้ 1 ออเดอร์ต่อ 1 แท่ง

//+------------------------------------------------------------------+
//| === การเฉลี่ยต้นทุน (Averaging / Martingale) ===                  |
//+------------------------------------------------------------------+
input group "=== Averaging / Martingale ==="
input bool   UseAveraging         = false;       // เปิดใช้การเฉลี่ยต้นทุน
input double AveragingDistPips    = 50.0;        // ระยะห่างการเฉลี่ย (Pips)
input double MartingaleMultiplier = 1.5;         // ตัวคูณ Martingale

//+------------------------------------------------------------------+
//| === StealthTrail SuperTrend Signal ===                           |
//+------------------------------------------------------------------+
input group "=== StealthTrail SuperTrend Signal ==="
input int    ST_AtrLength         = 13;          // ATR Length
input double ST_Multiplier        = 2.5;         // SuperTrend Multiplier
input int    ST_RsiLength         = 13;          // RSI Length
input double ST_RsiThresh         = 45.0;        // RSI Min สำหรับ BUY (SELL ใช้ 100 - thresh)
input int    ST_AdxMin            = 20;          // ค่า ADX ขั้นต่ำ
input bool   ST_UseMTF            = true;        // ใช้ H4 EMA20 vs EMA50 (MTF confluence)
input bool   ST_UseML             = true;        // เปิดใช้ตัวกรอง ML Score
input double ST_MLGate            = 55.0;        // ML Score ขั้นต่ำ (0-100)

//+------------------------------------------------------------------+
//| === ตัวแปร Global (Indicator Handles) ===                        |
//+------------------------------------------------------------------+
int h_atr      = INVALID_HANDLE;
int h_rsi      = INVALID_HANDLE;
int h_macd     = INVALID_HANDLE;
int h_adx      = INVALID_HANDLE;
int h_ema20_h4 = INVALID_HANDLE;
int h_ema50_h4 = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| === SuperTrend State (คงค่าข้ามแท่ง) ===                          |
//+------------------------------------------------------------------+
double   g_st_band     = 0.0;
int      g_st_dir      = 0;          // 0=ยังไม่ init, 1=ขาขึ้น, -1=ขาลง
datetime g_st_lastCalc = 0;

datetime g_lastBarTime = 0;          // สำหรับ OneTradePerBar

//+------------------------------------------------------------------+
//| Helper: Clamp                                                    |
//+------------------------------------------------------------------+
double Clamp(double v, double lo, double hi)
{
   if(v < lo) return lo;
   if(v > hi) return hi;
   return v;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   //--- สร้าง Indicator Handles ทั้งหมด
   h_atr      = iATR(_Symbol, _Period, ST_AtrLength);
   h_rsi      = iRSI(_Symbol, _Period, ST_RsiLength, PRICE_CLOSE);
   h_macd     = iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE);
   h_adx      = iADX(_Symbol, _Period, 14);
   h_ema20_h4 = iMA(_Symbol, PERIOD_H4, 20, 0, MODE_EMA, PRICE_CLOSE);
   h_ema50_h4 = iMA(_Symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);

   if(h_atr == INVALID_HANDLE || h_rsi == INVALID_HANDLE || h_macd == INVALID_HANDLE ||
      h_adx == INVALID_HANDLE || h_ema20_h4 == INVALID_HANDLE || h_ema50_h4 == INVALID_HANDLE)
   {
      Print("ERROR: ไม่สามารถสร้าง Indicator Handle ได้");
      return(INIT_FAILED);
   }

   //--- รอให้ Indicator โหลดข้อมูลเสร็จ
   int waited = 0;
   while((BarsCalculated(h_atr)  < 2 || BarsCalculated(h_rsi)  < 2 ||
          BarsCalculated(h_macd) < 2 || BarsCalculated(h_adx)  < 2) && waited < 50)
   {
      Sleep(100);
      waited++;
   }

   //--- คำนวณ SuperTrend ย้อนหลังให้พร้อมใช้งาน
   InitSuperTrend();

   Print("GoldScalperPro_V2 เริ่มทำงานสำเร็จ");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(h_atr      != INVALID_HANDLE) IndicatorRelease(h_atr);
   if(h_rsi      != INVALID_HANDLE) IndicatorRelease(h_rsi);
   if(h_macd     != INVALID_HANDLE) IndicatorRelease(h_macd);
   if(h_adx      != INVALID_HANDLE) IndicatorRelease(h_adx);
   if(h_ema20_h4 != INVALID_HANDLE) IndicatorRelease(h_ema20_h4);
   if(h_ema50_h4 != INVALID_HANDLE) IndicatorRelease(h_ema50_h4);
}

//+------------------------------------------------------------------+
//| InitSuperTrend: คำนวณ SuperTrend ย้อนหลังเพื่อ warm up state      |
//+------------------------------------------------------------------+
void InitSuperTrend()
{
   int totalBars = Bars(_Symbol, _Period);
   if(totalBars < 3)
   {
      Print("InitSuperTrend: ข้อมูลแท่งไม่เพียงพอ");
      return;
   }

   int lookback = MathMin(200, totalBars - 1);

   //--- รีเซ็ตสถานะ
   g_st_band = 0.0;
   g_st_dir  = 0;

   //--- วนจากแท่งเก่าสุดมาหาแท่งที่ปิดล่าสุด (index 1)
   for(int i = lookback; i >= 1; i--)
   {
      double atrBuf[];
      if(CopyBuffer(h_atr, 0, i, 1, atrBuf) < 1)
         continue;
      double atr = atrBuf[0];

      double high  = iHigh(_Symbol, _Period, i);
      double low   = iLow(_Symbol, _Period, i);
      double close = iClose(_Symbol, _Period, i);

      UpdateSuperTrend(high, low, close, atr);
   }

   g_st_lastCalc = iTime(_Symbol, _Period, 1);
   Print("InitSuperTrend สำเร็จ | คำนวณ ", lookback, " แท่ง | Direction = ",
         (g_st_dir == 1 ? "BULL" : (g_st_dir == -1 ? "BEAR" : "NONE")),
         " | Band = ", DoubleToString(g_st_band, _Digits));
}

//+------------------------------------------------------------------+
//| UpdateSuperTrend: คำนวณ 1 แท่ง อัพเดท state (g_st_band, g_st_dir) |
//| คืนค่า true หากทิศทางเพิ่งกลับตัว (flip)                          |
//+------------------------------------------------------------------+
bool UpdateSuperTrend(double high, double low, double close, double atr)
{
   double hl2        = (high + low) / 2.0;
   double upper_band = hl2 + ST_Multiplier * atr;
   double lower_band = hl2 - ST_Multiplier * atr;

   int prev_dir       = g_st_dir;
   double prev_band   = g_st_band;

   //--- กรณียังไม่เคย init: กำหนดทิศเริ่มต้นจากตำแหน่ง close เทียบ hl2
   if(prev_dir == 0)
   {
      if(close >= hl2)
      {
         g_st_dir  = 1;
         g_st_band = lower_band;
      }
      else
      {
         g_st_dir  = -1;
         g_st_band = upper_band;
      }
      return(false);
   }

   //--- คำนวณ band โดยใช้กลไก ratchet
   if(prev_dir == 1)
   {
      //--- ขาขึ้น: ใช้ lower band, ยกตามได้แต่ลงไม่ได้
      double newBand = MathMax(lower_band, prev_band);

      if(close < newBand)
      {
         //--- ราคาตัดลงต่ำกว่า band → กลับเป็นขาลง
         g_st_dir  = -1;
         g_st_band = upper_band;
         return(true);
      }
      else
      {
         g_st_dir  = 1;
         g_st_band = newBand;
         return(false);
      }
   }
   else // prev_dir == -1
   {
      //--- ขาลง: ใช้ upper band, กดลงได้แต่ขึ้นไม่ได้
      double newBand = MathMin(upper_band, prev_band);

      if(close > newBand)
      {
         //--- ราคาตัดขึ้นเหนือ band → กลับเป็นขาขึ้น
         g_st_dir  = 1;
         g_st_band = lower_band;
         return(true);
      }
      else
      {
         g_st_dir  = -1;
         g_st_band = newBand;
         return(false);
      }
   }
}

//+------------------------------------------------------------------+
//| GetTradingSignal: คืน 1=BUY, -1=SELL, 0=ไม่มีสัญญาณ              |
//+------------------------------------------------------------------+
int GetTradingSignal()
{
   //--- ตรวจสอบว่าเป็นแท่งปิดใหม่หรือไม่
   datetime bar1Time = iTime(_Symbol, _Period, 1);
   if(bar1Time == g_st_lastCalc)
      return(0); // ยังไม่มีแท่งปิดใหม่

   //--- อ่านค่า indicator จากแท่ง index 1 (แท่งปิดล่าสุด)
   double atrBuf[], rsiBuf[], adxBuf[];
   double macdMain[], macdSig[];
   double ema20Buf[], ema50Buf[];

   if(CopyBuffer(h_atr, 0, 1, 1, atrBuf)  < 1) return(0);
   if(CopyBuffer(h_rsi, 0, 1, 1, rsiBuf)  < 1) return(0);
   if(CopyBuffer(h_adx, 0, 1, 1, adxBuf)  < 1) return(0);
   if(CopyBuffer(h_macd, 0, 1, 1, macdMain) < 1) return(0);
   if(CopyBuffer(h_macd, 1, 1, 1, macdSig)  < 1) return(0);

   double atr  = atrBuf[0];
   double rsi  = rsiBuf[0];
   double adx  = adxBuf[0];
   double macdHist = macdMain[0] - macdSig[0];

   //--- ราคาจากแท่ง index 1
   double high  = iHigh(_Symbol, _Period, 1);
   double low   = iLow(_Symbol, _Period, 1);
   double close = iClose(_Symbol, _Period, 1);

   //--- คำนวณ SuperTrend สำหรับแท่ง 1 และเช็คการกลับตัว
   bool flipped = UpdateSuperTrend(high, low, close, atr);
   g_st_lastCalc = bar1Time;

   //--- ไม่มีการกลับทิศ → ไม่มีสัญญาณ
   if(!flipped)
      return(0);

   int dir = g_st_dir; // ทิศทางใหม่หลัง flip

   //--- ค่า MTF (H4 EMA20 vs EMA50)
   double ema20_h4 = 0.0, ema50_h4 = 0.0;
   bool mtfBull = false, mtfBear = false;
   if(CopyBuffer(h_ema20_h4, 0, 1, 1, ema20Buf) >= 1 &&
      CopyBuffer(h_ema50_h4, 0, 1, 1, ema50Buf) >= 1)
   {
      ema20_h4 = ema20Buf[0];
      ema50_h4 = ema50Buf[0];
      mtfBull  = (ema20_h4 > ema50_h4);
      mtfBear  = (ema20_h4 < ema50_h4);
   }

   //--- 4) ตัวกรอง RSI Momentum
   if(dir == 1)
   {
      if(rsi < ST_RsiThresh) return(0);
   }
   else // dir == -1
   {
      if(rsi > (100.0 - ST_RsiThresh)) return(0);
   }

   //--- 5) ตัวกรอง ADX
   if(adx < ST_AdxMin)
      return(0);

   //--- 6) ตัวกรอง MTF
   if(ST_UseMTF)
   {
      if(dir == 1 && !mtfBull) return(0);
      if(dir == -1 && !mtfBear) return(0);
   }

   //--- 7) ตัวกรอง ML Score (แบบย่อ)
   if(ST_UseML)
   {
      //--- f1: คะแนน RSI momentum
      double f1;
      if(dir == 1) f1 = Clamp((rsi - 50.0) * 2.0 + 50.0, 0.0, 100.0);
      else         f1 = Clamp((50.0 - rsi) * 2.0 + 50.0, 0.0, 100.0);

      //--- f3: ความแรงเทรนด์จาก ADX
      double f3 = MathMin(adx * 2.5, 100.0);

      //--- f6: MACD alignment
      double f6;
      if((dir == 1 && macdHist > 0) || (dir == -1 && macdHist < 0))
         f6 = 80.0;
      else
         f6 = 30.0;

      //--- f9: MTF alignment
      double f9;
      if(!ST_UseMTF)
         f9 = 50.0;
      else
      {
         if((dir == 1 && mtfBull) || (dir == -1 && mtfBear))
            f9 = 100.0;
         else
            f9 = 0.0;
      }

      //--- f10: ความแรง ADX
      double f10 = MathMin(adx * 2.5, 100.0);

      double wSum = 0.15 + 0.15 + 0.08 + 0.12 + 0.10;
      double ml_score = (0.15 * f1 + 0.15 * f3 + 0.08 * f6 + 0.12 * f9 + 0.10 * f10) / wSum;

      if(ml_score < ST_MLGate)
         return(0);
   }

   //--- ผ่านตัวกรองทั้งหมด
   return(dir);
}

//+------------------------------------------------------------------+
//| IsDailyLimitReached: เช็คว่าถึงลิมิตเทรดต่อวันหรือยัง            |
//| นับทั้ง position ที่เปิดวันนี้ + deal DEAL_ENTRY_IN วันนี้         |
//+------------------------------------------------------------------+
bool IsDailyLimitReached()
{
   //--- หาเวลาเริ่มต้นของวันนี้
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   datetime dayStart = StructToTime(dt);

   int count = 0;

   //--- 1) นับ position ที่ active และเปิดวันนี้
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(openTime >= dayStart)
         count++;
   }

   //--- 2) นับ deal DEAL_ENTRY_IN จากประวัติของวันนี้
   if(HistorySelect(dayStart, TimeCurrent()))
   {
      int totalDeals = HistoryDealsTotal();
      for(int i = 0; i < totalDeals; i++)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket == 0) continue;

         if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) continue;
         if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber) continue;

         long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN)
            count++;
      }
   }

   return(count >= MaxDailyTrades);
}

//+------------------------------------------------------------------+
//| CalculateLotSize: คำนวณขนาด Lot                                  |
//| Fix: หา position ที่มี POSITION_TIME ล่าสุด (ไม่ใช่ตัวสุดท้ายใน loop)|
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double current_lot = BaseLotSize;

   if(UseAveraging)
   {
      //--- หา position ที่เปิดล่าสุด (POSITION_TIME มากสุด) ของ symbol + magic นี้
      bool found = false;
      datetime latestTime = 0;
      double   latestVolume = 0.0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;

         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

         datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
         if(openTime > latestTime)
         {
            latestTime   = openTime;
            latestVolume = PositionGetDouble(POSITION_VOLUME);
            found        = true;
         }
      }

      if(found)
         current_lot = latestVolume * MartingaleMultiplier;
   }

   //--- ปรับให้อยู่ในขอบเขตที่โบรกเกอร์ยอมรับ
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lotStep > 0)
      current_lot = MathFloor(current_lot / lotStep) * lotStep;

   if(current_lot < minLot) current_lot = minLot;
   if(current_lot > maxLot) current_lot = maxLot;

   return(current_lot);
}

//+------------------------------------------------------------------+
//| CountMyPositions: นับ position ของ EA นี้                        |
//+------------------------------------------------------------------+
int CountMyPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      count++;
   }
   return(count);
}

//+------------------------------------------------------------------+
//| GetSpreadPips: คืนค่า spread ปัจจุบันเป็น Pips                    |
//+------------------------------------------------------------------+
double GetSpreadPips()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   //--- 1 Pip = 10 points สำหรับ symbol 3/5 digits
   double pipFactor = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   return((double)spreadPts / pipFactor);
}

//+------------------------------------------------------------------+
//| OpenTrade: เปิดออเดอร์ตามทิศทางสัญญาณ                            |
//+------------------------------------------------------------------+
void OpenTrade(int dir)
{
   double lot = CalculateLotSize();
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double price, sl, tp;

   if(dir == 1)
   {
      price = ask;
      sl = (StopLossPoints   > 0) ? price - StopLossPoints   * point : 0.0;
      tp = (TakeProfitPoints > 0) ? price + TakeProfitPoints * point : 0.0;
      if(trade.Buy(lot, _Symbol, price, sl, tp, "GSPv2 BUY [ST flip]"))
         Print("เปิด BUY สำเร็จ | Lot=", lot);
      else
         Print("เปิด BUY ล้มเหลว | code=", trade.ResultRetcode());
   }
   else if(dir == -1)
   {
      price = bid;
      sl = (StopLossPoints   > 0) ? price + StopLossPoints   * point : 0.0;
      tp = (TakeProfitPoints > 0) ? price - TakeProfitPoints * point : 0.0;
      if(trade.Sell(lot, _Symbol, price, sl, tp, "GSPv2 SELL [ST flip]"))
         Print("เปิด SELL สำเร็จ | Lot=", lot);
      else
         Print("เปิด SELL ล้มเหลว | code=", trade.ResultRetcode());
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- สถานะ SuperTrend สำหรับแสดงผล
   string stText = (g_st_dir == 1 ? "BULL" : (g_st_dir == -1 ? "BEAR" : "NONE"));
   double spread = GetSpreadPips();

   //--- 1) ตัวกรอง Spread
   if(spread > MaxSpreadPips)
   {
      Comment("Status: SPREAD TOO HIGH [ST: ", stText, "] | Spread: ",
              DoubleToString(spread, 1), " Pips");
      return;
   }

   //--- 2) เช็คลิมิตเทรดต่อวัน
   if(IsDailyLimitReached())
   {
      Comment("Status: DAILY LIMIT REACHED [ST: ", stText, "] | Spread: ",
              DoubleToString(spread, 1), " Pips");
      return;
   }

   //--- 3) OneTradePerBar
   datetime curBarTime = iTime(_Symbol, _Period, 0);
   if(OneTradePerBar && curBarTime == g_lastBarTime)
   {
      Comment("Status: WAIT NEXT BAR [ST: ", stText, "] | Spread: ",
              DoubleToString(spread, 1), " Pips");
      return;
   }

   //--- 4) ขอสัญญาณเทรด
   int signal = GetTradingSignal();

   //--- อัพเดทข้อความ ST หลังคำนวณสัญญาณ (ทิศอาจเปลี่ยน)
   stText = (g_st_dir == 1 ? "BULL" : (g_st_dir == -1 ? "BEAR" : "NONE"));

   if(signal == 0)
   {
      Comment("Status: SCANNING [ST: ", stText, "] | Spread: ",
              DoubleToString(spread, 1), " Pips");
      return;
   }

   //--- กรณีไม่ใช้ averaging และมี position อยู่แล้ว → ไม่เปิดเพิ่ม
   if(!UseAveraging && CountMyPositions() > 0)
   {
      Comment("Status: IN POSITION [ST: ", stText, "] | Spread: ",
              DoubleToString(spread, 1), " Pips");
      return;
   }

   //--- 5) เปิดออเดอร์
   OpenTrade(signal);
   g_lastBarTime = curBarTime;

   Comment("Status: ", (signal == 1 ? "OPENED BUY" : "OPENED SELL"),
           " [ST: ", stText, "] | Spread: ", DoubleToString(spread, 1), " Pips");
}
//+------------------------------------------------------------------+
