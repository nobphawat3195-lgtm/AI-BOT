//+------------------------------------------------------------------+
//|                                        XAU_StraddleCore_v1.mq5   |
//|                                                                  |
//|  สแตรดเดิลทองคำ - เขียนใหม่จากผลทดสอบจริง                        |
//|                                                                  |
//|  ที่มาของการออกแบบ (ทุกข้อมาจากผลทดสอบ ไม่ได้เดา):               |
//|                                                                  |
//|  1) โครงสร้างยึดตาม Scalper_TH_v3 (กันทุน -> ล็อกกำไรตามราคาสด)  |
//|     เพราะผ่าน walk-forward 8/8 ขณะที่แบบมีระบบกลับไม้ตก 0/8      |
//|  2) ตัดระบบกลับไม้ (Reverse) ออก - เพิ่มความซับซ้อนแต่ไม่เพิ่ม    |
//|     ความทนทาน                                                     |
//|  3) Time Filter เปิดเป็นค่าเริ่มต้น - เป็นพารามิเตอร์ที่ให้ผล     |
//|     มากที่สุด ค่าที่ดีที่สุด 15 อันดับแรกเปิดทุกชุด               |
//|  4) จำกัดจำนวนไม้ต่อวัน - ค่าคอมคือต้นทุนหลักของพอร์ตเล็ก         |
//|     (ไม่จำกัดเลย = จ่ายคอม 32% ของพอร์ต $300 ใน 5 วัน)           |
//|  5) เพดานล็อตบังคับเสมอ + ล็อตคงที่เป็นค่าเริ่มต้น                |
//|  6) ระบบหน่วยเป็นดอลลาร์/ออนซ์ ย้ายโบรกได้โดยไม่ต้องแก้ค่า        |
//|  7) ปิดการไล่ SL ตามแท่งเทียนและการพักหลังโดน SL เป็นค่าเริ่มต้น  |
//|     ทั้งสองอย่างวัดแล้วว่าไม่ช่วย (ดูคอมเมนต์ตรงอินพุตนั้นๆ)      |
//|                                                                  |
//|  *** ผลนอกกลุ่มตัวอย่าง = เสมอตัว (PF 1.00) ***                   |
//|  *** ยังไม่ผ่านการยืนยันด้วย real tick data ***                   |
//|  *** ยังไม่มีหลักฐานว่าทำกำไรได้ - ทดสอบ Demo ก่อนเสมอ ***        |
//+------------------------------------------------------------------+
#property copyright "XAU StraddleCore"
#property version   "1.00"
#property description "XAUUSD Straddle - โครงสร้างจากผล walk-forward"

#include <Trade/Trade.mqh>

CTrade trade;

//=================== ENUM ===========================================
enum ENUM_UNIT
  {
   UNIT_USD   = 0,   // ดอลลาร์ต่อออนซ์ ($) - แนะนำ ใช้ได้ทุกโบรก
   UNIT_POINT = 1    // จุด (Point) - ตามที่โบรกกำหนด
  };

enum ENUM_LOTMODE
  {
   LOT_FIXED = 0,    // ล็อตคงที่ - แนะนำสำหรับพอร์ตเล็ก
   LOT_RISK  = 1     // คำนวณจาก % ความเสี่ยง (มีเพดานบังคับเสมอ)
  };

//=================== การตั้งค่า =====================================
input group "───────── ⚙ พื้นฐาน ─────────"
input ENUM_UNIT InpUnit          = UNIT_USD;   // หน่วยที่ใช้วัดระยะทั้งหมด
input ulong    InpMagic          = 990200;     // เลขประจำตัว EA (ห้ามซ้ำกับตัวอื่น)
input int      InpSlippage       = 30;         // ค่าคลาดเคลื่อนราคาที่ยอมรับ (จุดโบรก)
input string   InpComment        = "SCv1";     // ข้อความกำกับออเดอร์
input bool     InpVerbose        = true;       // บันทึกรายละเอียดลง Journal

input group "───────── 📍 ระยะวางออเดอร์ ─────────"
input double   InpEntryDist      = 0.50;   // ระยะคร่อมราคา (ผลทดสอบ: 0.50 ดีสุด)
input double   InpStopLoss       = 1.50;   // จุดตัดขาดทุน SL (ผลทดสอบ: 1.50 ดีสุด)
input double   InpTakeProfit     = 10.00;  // เป้ากำไร TP (0 = ไม่ตั้ง ให้ trailing พาออก)

input group "───────── 🔒 ล็อกกำไร ─────────"
input double   InpBEStart        = 0.60;   // กำไรถึงเท่าไร จึงเลื่อน SL มากันทุน
input double   InpBELock         = 0.30;   // กันทุนแล้วล็อกกำไรขั้นต่ำเท่าไร
input double   InpLockGap        = 1.00;   // ไล่ SL ตามราคาสด ห่างเท่าไร
//--- ทดสอบแล้ว: เมื่อ InpLockGap = 1.00 การไล่ตามราคาสดจะชิดกว่าการไล่ตาม
//    แท่งเทียนเกือบตลอดเวลา ทำให้ตัวไล่ตามแท่งชนะแค่ 2 ครั้งจาก 13,869 ครั้ง
//    = ไม่มีผลอะไรเลย จึงปิดไว้เป็นค่าเริ่มต้น เปิดได้ถ้าตั้ง InpLockGap กว้างขึ้น
input bool     InpUseCandleTrail = false;  // ไล่ SL ตามแท่งเทียนด้วย (ทำครั้งเดียวต่อแท่ง)
input double   InpCandleBuffer   = 0.50;   // ไล่ตามแท่งเทียน เผื่อห่างเท่าไร

input group "───────── 🚦 คุมความถี่ (สำคัญมากกับพอร์ตเล็ก) ─────────"
input int      InpMaxTradesDay   = 200;    // จำกัดกี่ไม้ต่อวัน (0 = ไม่จำกัด)
//--- ทดสอบแล้ว: การพักหลังโดน SL ทำให้ผลนอกกลุ่มตัวอย่างแย่ลง
//    (-1.24 -> -13.41) เพราะไปพลาดจังหวะที่ราคาเบรกจริงหลังหลอกครั้งแรก
//    จึงปิดไว้ ถ้าอยากกัน revenge trading ให้ใช้ InpMinSecsBetween แทน
input int      InpCooldownAfterSL= 0;      // หลังโดน SL พักกี่วินาที (0 = ไม่พัก)
input int      InpMinSecsBetween = 0;      // เว้นระยะระหว่างไม้อย่างน้อยกี่วินาที

input group "───────── ⏰ ช่วงเวลาเทรด (เวลาไทย) ─────────"
input bool     InpUseTimeFilter  = true;   // เปิดใช้ Time Filter (ผลทดสอบ: ต้องเปิด)
input bool     InpAutoGMT        = true;   // ตรวจเขตเวลาเซิร์ฟเวอร์อัตโนมัติ
input int      InpManualGMT      = 3;      // เขตเวลาเซิร์ฟเวอร์ (ใช้เมื่อปิดอัตโนมัติ)
input string   InpSess1          = "07:00-08:30";  // ช่วงที่ 1
input string   InpSess2          = "19:00-20:30";  // ช่วงที่ 2
input string   InpSess3          = "02:00-03:30";  // ช่วงที่ 3
input bool     InpCloseAtEnd     = true;   // หมดช่วงเวลาแล้วปิดไม้ทิ้ง

input group "───────── 💰 ขนาดไม้ ─────────"
input ENUM_LOTMODE InpLotMode    = LOT_FIXED; // วิธีกำหนดขนาดไม้
input double   InpFixedLot       = 0.01;   // ล็อตคงที่
input double   InpRiskPercent    = 1.0;    // เสี่ยงกี่ % ต่อไม้ (โหมด LOT_RISK)
input double   InpMaxLot         = 0.10;   // เพดานล็อตสูงสุด (บังคับเสมอ ห้ามใส่ 0)

input group "───────── 🛡 เบรกความเสียหาย ─────────"
input double   InpMaxSpread      = 0.50;   // สเปรดกว้างเกินนี้ ไม่วางออเดอร์
input bool     InpUseDailyLoss   = true;   // เปิดเพดานขาดทุนรายวัน
input double   InpDailyLossPct   = 5.0;    // ขาดทุนถึงกี่ % ของทุน แล้วหยุดถึงเที่ยงคืน
input bool     InpUseDailyProfit = false;  // เปิดเป้ากำไรรายวัน
input double   InpDailyProfitPct = 5.0;    // กำไรถึงกี่ % แล้วเก็บกำไรหยุด

input group "───────── 🖥 หน้าจอ ─────────"
input bool     InpShowPanel      = true;   // แสดงแผงสถานะบนกราฟ

//=================== ตัวแปรระบบ =====================================
int      g_gmt          = 0;
datetime g_lastCandle   = 0;
datetime g_cooldownTill = 0;
datetime g_lastCloseAt  = 0;
datetime g_haltDay      = 0;
string   g_haltWhy      = "";
int      g_tradesToday  = 0;
double   g_dayNet       = 0.0;
int      g_dayWin       = 0, g_dayLoss = 0;
datetime g_statCache    = 0;
bool     g_beDone       = false;   // ไม้ปัจจุบันเลื่อนมากันทุนแล้วหรือยัง

//=================== ตัวช่วยพื้นฐาน =================================
double Pt()    { return SymbolInfoDouble(_Symbol, SYMBOL_POINT); }
int    Digs()  { return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS); }
double Bid()   { return SymbolInfoDouble(_Symbol, SYMBOL_BID); }
double Ask()   { return SymbolInfoDouble(_Symbol, SYMBOL_ASK); }
double NP(const double p) { return NormalizeDouble(p, Digs()); }

//--- แปลงค่าที่ผู้ใช้กรอก -> ราคาจริง (ไม่ใช่จุด) เพื่อเลี่ยงปัญหาทศนิยมโบรก
double D2P(const double v)
  {
   if(v <= 0.0) return 0.0;
   if(InpUnit == UNIT_POINT) return v * Pt();
   return v;                       // UNIT_USD: กรอกมาเป็นราคาอยู่แล้ว
  }

//--- ระยะขั้นต่ำที่โบรกยอมรับ (คืนเป็นราคา)
double MinStop()
  {
   long s = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long f = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return (double)MathMax(s, f) * Pt();
  }

//--- ระยะ SL ที่ใช้จริง หลังโบรกบังคับขยาย
//    ต้องใช้ตัวเดียวกันทั้งตอนวางออเดอร์และตอนคิดล็อต ไม่งั้นเสี่ยงเกินที่ตั้งไว้
double EffSL()
  {
   double want = D2P(InpStopLoss);
   if(want <= 0.0) return 0.0;
   return MathMax(want, MinStop());
  }

double SpreadPrice() { return Ask() - Bid(); }

bool ResultOK(const string what)
  {
   uint rc = trade.ResultRetcode();
   if(rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED ||
      rc == TRADE_RETCODE_DONE_PARTIAL) return true;
   if(InpVerbose)
      PrintFormat("[ไม่สำเร็จ] %s -> %u : %s", what, rc, trade.ResultRetcodeDescription());
   return false;
  }

//=================== เขตเวลา / ช่วงเทรด =============================
int ServerGMT()
  {
   if(!InpAutoGMT) return InpManualGMT;
   long diff = (long)TimeCurrent() - (long)TimeGMT();
   int off = (int)MathRound((double)diff / 3600.0);
   if(off < -12 || off > 14) return InpManualGMT;
   return off;
  }

//--- แปลง "07:00-08:30" เป็นนาทีเริ่มและนาทีจบ
bool ParseSess(const string s, int &from, int &to)
  {
   from = -1; to = -1;
   string side[];
   if(StringSplit(s, '-', side) != 2) return false;
   string a[], b[];
   if(StringSplit(side[0], ':', a) != 2) return false;
   if(StringSplit(side[1], ':', b) != 2) return false;
   from = (int)StringToInteger(a[0]) * 60 + (int)StringToInteger(a[1]);
   to   = (int)StringToInteger(b[0]) * 60 + (int)StringToInteger(b[1]);
   return (from >= 0 && to >= 0);
  }

//--- เวลาไทยตอนนี้ คิดเป็นนาทีจากเที่ยงคืน
int ThaiMin()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int m = (dt.hour * 60 + dt.min) + (7 - g_gmt) * 60;
   while(m < 0)     m += 1440;
   while(m >= 1440) m -= 1440;
   return m;
  }

bool InRange(const int now, const int f, const int t)
  {
   if(f < 0 || t < 0) return false;
   if(f <= t) return (now >= f && now < t);
   return (now >= f || now < t);       // ข้ามเที่ยงคืน
  }

bool InSession()
  {
   if(!InpUseTimeFilter) return true;
   int now = ThaiMin(), f, t;
   if(ParseSess(InpSess1, f, t) && InRange(now, f, t)) return true;
   if(ParseSess(InpSess2, f, t) && InRange(now, f, t)) return true;
   if(ParseSess(InpSess3, f, t) && InRange(now, f, t)) return true;
   return false;
  }

//--- เที่ยงคืนไทยของวันนี้ แปลงเป็นเวลาเซิร์ฟเวอร์
datetime ThaiDayStart()
  {
   datetime gmt   = TimeGMT();
   long thaiSec   = (long)gmt + 7 * 3600;
   long secToday  = thaiSec % 86400;
   long startGMT  = (long)gmt - secToday;
   long offset    = (long)TimeCurrent() - (long)gmt;
   return (datetime)(startGMT + offset);
  }

//=================== สถิติรายวัน ====================================
void RefreshStats(const bool force)
  {
   if(!force && g_statCache > 0 && TimeCurrent() - g_statCache < 2) return;
   g_statCache = TimeCurrent();

   datetime from = ThaiDayStart();
   if(!HistorySelect(from, TimeCurrent() + 3600)) return;

   g_dayNet = 0.0; g_dayWin = 0; g_dayLoss = 0; g_tradesToday = 0;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0) continue;
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != (long)InpMagic) continue;
      if(HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol) continue;

      long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT &&
         entry != DEAL_ENTRY_OUT_BY) continue;

      double pl = HistoryDealGetDouble(tk, DEAL_PROFIT)
                + HistoryDealGetDouble(tk, DEAL_SWAP)
                + HistoryDealGetDouble(tk, DEAL_COMMISSION);
      g_dayNet += pl;
      g_tradesToday++;
      if(pl >= 0) g_dayWin++; else g_dayLoss++;
     }
  }

double Floating()
  {
   double sum = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == (long)InpMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         sum += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return sum;
  }

bool Halted() { return (g_haltDay != 0 && g_haltDay == ThaiDayStart()); }

void CheckDailyLimits()
  {
   if(Halted()) return;
   double bal   = AccountInfoDouble(ACCOUNT_BALANCE);
   double today = g_dayNet + Floating();

   if(InpUseDailyLoss && today <= -bal * InpDailyLossPct / 100.0)
     {
      g_haltDay = ThaiDayStart();
      g_haltWhy = StringFormat("ขาดทุน %.2f$ ถึงเพดาน %.1f%%", today, InpDailyLossPct);
      PrintFormat("🛑 หยุดเทรดถึงเที่ยงคืน: %s", g_haltWhy);
      return;
     }
   if(InpUseDailyProfit && today >= bal * InpDailyProfitPct / 100.0)
     {
      g_haltDay = ThaiDayStart();
      g_haltWhy = StringFormat("กำไร %.2f$ ถึงเป้า %.1f%%", today, InpDailyProfitPct);
      PrintFormat("🏆 เก็บกำไร หยุดเทรดถึงเที่ยงคืน: %s", g_haltWhy);
     }
  }

//=================== ขนาดไม้ ========================================
double CalcLot()
  {
   double lot;
   if(InpLotMode == LOT_FIXED)
      lot = InpFixedLot;
   else
     {
      double bal      = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskCash = bal * InpRiskPercent / 100.0;
      double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSz   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double slPrice  = EffSL();                    // ใช้ SL จริง ไม่ใช่ค่าที่กรอก
      if(tickVal <= 0 || tickSz <= 0 || slPrice <= 0) return 0;
      double lossPerLot = (slPrice / tickSz) * tickVal;
      if(lossPerLot <= 0) return 0;
      lot = riskCash / lossPerLot;
     }

   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(st <= 0) st = 0.01;
   if(mn <= 0) mn = 0.01;
   if(mx <= 0) mx = 100.0;

   //--- เพดานผู้ใช้มาก่อนเพดานโบรกเสมอ
   double cap = (InpMaxLot > 0) ? MathMin(InpMaxLot, mx) : mx;

   lot = MathFloor(lot / st) * st;
   lot = MathMax(mn, MathMin(cap, lot));

   int dg = 2;
   if(st >= 1.0) dg = 0; else if(st >= 0.1) dg = 1; else if(st <= 0.001) dg = 3;
   return NormalizeDouble(lot, dg);
  }

bool MarginOK(const double lot)
  {
   double need;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, Ask(), need)) return false;
   return (AccountInfoDouble(ACCOUNT_MARGIN_FREE) > need * 2.0);
  }

//=================== นับออเดอร์ =====================================
int CountPend()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != (long)InpMagic) continue;
      long t = OrderGetInteger(ORDER_TYPE);
      if(t == ORDER_TYPE_BUY_STOP || t == ORDER_TYPE_SELL_STOP) n++;
     }
   return n;
  }

void KillPend()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != (long)InpMagic) continue;
      long t = OrderGetInteger(ORDER_TYPE);
      if(t == ORDER_TYPE_BUY_STOP || t == ORDER_TYPE_SELL_STOP)
        { trade.OrderDelete(tk); ResultOK("ลบออเดอร์รอ"); }
     }
  }

bool PickPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      if(PositionSelectByTicket(tk)) return true;
     }
   return false;
  }

bool HasPosition() { return PickPosition(); }

void ClosePosition(const string why)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      trade.PositionClose(tk);
      if(ResultOK("ปิดไม้: " + why) && InpVerbose)
         PrintFormat("ปิดไม้ (%s)", why);
     }
  }

//=================== วางกับดักสองข้าง ===============================
void PlaceStraddle()
  {
   if(HasPosition() || CountPend() > 0) return;
   if(SpreadPrice() > D2P(InpMaxSpread)) return;

   double dist = MathMax(D2P(InpEntryDist), MinStop() + Pt());
   double slD  = EffSL();
   double tpD  = D2P(InpTakeProfit);
   if(tpD > 0) tpD = MathMax(tpD, MinStop() + Pt());

   double bp = NP(Ask() + dist);
   double sp = NP(Bid() - dist);

   double bSL = (slD > 0) ? NP(bp - slD) : 0.0;
   double sSL = (slD > 0) ? NP(sp + slD) : 0.0;
   double bTP = (tpD > 0) ? NP(bp + tpD) : 0.0;
   double sTP = (tpD > 0) ? NP(sp - tpD) : 0.0;

   double lot = CalcLot();
   if(lot <= 0)      { Print("คำนวณล็อตไม่สำเร็จ"); return; }
   if(!MarginOK(lot)){ PrintFormat("มาร์จิ้นไม่พอสำหรับ %.2f ล็อต", lot); return; }

   bool okB = trade.BuyStop(lot, bp, _Symbol, bSL, bTP, ORDER_TIME_GTC, 0, InpComment);
   okB = okB && ResultOK("วาง Buy Stop");
   bool okS = trade.SellStop(lot, sp, _Symbol, sSL, sTP, ORDER_TIME_GTC, 0, InpComment);
   okS = okS && ResultOK("วาง Sell Stop");

   //--- ต้องได้ครบคู่เท่านั้น ไม่งั้นลบทิ้งแล้วเริ่มใหม่รอบหน้า
   if(okB != okS)
     {
      Print("วางกับดักได้ไม่ครบคู่ -> ลบทิ้ง");
      KillPend();
      return;
     }
   if(okB && okS && InpVerbose)
      PrintFormat("✅ วางกับดัก ล็อต=%.2f | Buy=%.2f | Sell=%.2f", lot, bp, sp);
  }

//=================== ดูแลไม้ที่เปิดอยู่ ==============================
void ManagePosition()
  {
   if(!PickPosition()) return;

   long   type  = PositionGetInteger(POSITION_TYPE);
   ulong  tk    = PositionGetInteger(POSITION_TICKET);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double tp    = PositionGetDouble(POSITION_TP);
   double bid   = Bid(), ask = Ask();
   bool   isBuy = (type == POSITION_TYPE_BUY);

   //--- กำไรปัจจุบัน วัดจากราคาที่ไม้นี้จะถูกปิดจริง
   double profit = isBuy ? (bid - entry) : (entry - ask);

   double beLevel = isBuy ? NP(entry + D2P(InpBELock)) : NP(entry - D2P(InpBELock));
   double minD    = MinStop();
   double newSL   = 0.0;

   if(profit >= D2P(InpBEStart))
     {
      //--- ขั้นที่ 1: กันทุน
      newSL = beLevel;
      g_beDone = true;

      //--- ขั้นที่ 2: ไล่ตามราคาสด
      //    ไม้ซื้อปิดที่ Bid ไม้ขายปิดที่ Ask ซึ่งรวมสเปรดแล้ว
      //    จึงวัดจากราคาปิดของแต่ละฝั่งด้วยระยะเท่ากัน ไม่ต้องชดเชยสเปรดซ้ำ
      double lock = isBuy ? NP(bid - D2P(InpLockGap)) : NP(ask + D2P(InpLockGap));
      if(isBuy  && lock > newSL) newSL = lock;
      if(!isBuy && lock < newSL) newSL = lock;
     }

   //--- ขั้นที่ 3: ไล่ตามแท่งเทียน ทำครั้งเดียวต่อแท่ง และเฉพาะหลังกันทุนแล้ว
   datetime cur = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(InpUseCandleTrail && g_beDone && cur != g_lastCandle)
     {
      g_lastCandle = cur;
      double buf = D2P(InpCandleBuffer);
      double cand;
      if(isBuy)
        {
         cand = NP(iLow(_Symbol, PERIOD_CURRENT, 1) - buf);
         if(cand > newSL) newSL = cand;
        }
      else
        {
         //--- แท่งเทียน MT5 อ้างอิง Bid แต่ไม้ขายปิดที่ Ask
         //    จึงต้องบวกสเปรดจริงตอนนี้เพื่อแปลงหน่วยให้ถูก
         cand = NP(iHigh(_Symbol, PERIOD_CURRENT, 1) + buf + SpreadPrice());
         if(newSL == 0.0 || cand < newSL) newSL = cand;
        }
      //--- ห้ามแย่กว่าจุดกันทุน
      if(isBuy  && newSL < beLevel) newSL = beLevel;
      if(!isBuy && newSL > beLevel) newSL = beLevel;
     }

   if(newSL == 0.0) return;
   newSL = NP(newSL);

   //--- โบรกยอมรับไหม และเลื่อนไปข้างหน้าเท่านั้น
   if(isBuy  && newSL > bid - minD) return;
   if(!isBuy && newSL < ask + minD) return;
   bool better = isBuy ? (sl == 0.0 || newSL > sl + Pt() * 0.5)
                       : (sl == 0.0 || newSL < sl - Pt() * 0.5);
   if(!better) return;

   if(trade.PositionModify(tk, newSL, tp))
     {
      if(InpVerbose) PrintFormat("🔒 เลื่อน SL -> %.2f (กำไร %.2f)", newSL, profit);
     }
   else ResultOK("เลื่อน SL");
  }

//=================== สมองหลัก =======================================
void Core()
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return;
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL) return;

   g_gmt = ServerGMT();
   RefreshStats(false);

   bool hasPos = HasPosition();
   int  pend   = CountPend();

   //--- OCO: มีไม้แล้วต้องไม่เหลือกับดักค้าง
   if(hasPos && pend > 0) { KillPend(); pend = 0; }
   if(!hasPos) g_beDone = false;

   //--- ด่าน 1: เพดานรายวัน
   CheckDailyLimits();
   if(Halted())
     {
      if(pend > 0) KillPend();
      if(hasPos)   ClosePosition("ถึงเพดานรายวัน");
      return;
     }

   //--- ด่าน 2: ช่วงเวลา
   if(!InSession())
     {
      if(pend > 0) KillPend();
      if(hasPos)
        {
         if(InpCloseAtEnd) ClosePosition("หมดช่วงเวลาเทรด");
         else              ManagePosition();
        }
      return;
     }

   //--- ด่าน 3: มีไม้อยู่ -> ดูแลไม้
   if(hasPos) { ManagePosition(); return; }

   //--- ด่าน 4: คุมความถี่ (ค่าคอมคือต้นทุนหลักของพอร์ตเล็ก)
   if(InpMaxTradesDay > 0 && g_tradesToday >= InpMaxTradesDay)
     { if(pend > 0) KillPend(); return; }
   if(g_cooldownTill > 0 && TimeCurrent() < g_cooldownTill)
     { if(pend > 0) KillPend(); return; }
   if(InpMinSecsBetween > 0 && g_lastCloseAt > 0 &&
      TimeCurrent() - g_lastCloseAt < InpMinSecsBetween)
     { if(pend > 0) KillPend(); return; }

   //--- ด่าน 5: วางกับดักใหม่
   if(pend >= 2) return;
   if(pend == 1) KillPend();
   PlaceStraddle();
  }

//=================== แผงสถานะ =======================================
void Panel()
  {
   if(!InpShowPanel) return;

   string state;
   if(Halted())            state = "หยุดแล้ววันนี้: " + g_haltWhy;
   else if(HasPosition())  state = "ถือไม้อยู่ กำลังดูแล";
   else if(!InSession())   state = "นอกช่วงเวลาเทรด";
   else if(InpMaxTradesDay > 0 && g_tradesToday >= InpMaxTradesDay)
                           state = "ครบโควตาไม้วันนี้แล้ว";
   else if(g_cooldownTill > TimeCurrent())
                           state = StringFormat("พักหลังโดน SL อีก %d วิ",
                                   (int)(g_cooldownTill - TimeCurrent()));
   else if(CountPend() >= 2) state = "วางกับดักแล้ว รอราคาชน";
   else                    state = "รอจังหวะวางกับดัก";

   string quota = (InpMaxTradesDay > 0)
                ? StringFormat("%d/%d", g_tradesToday, InpMaxTradesDay)
                : StringFormat("%d (ไม่จำกัด)", g_tradesToday);

   string txt = StringFormat(
      "\n  XAU StraddleCore v1   [%s]\n"
      "  ─────────────────────────────────\n"
      "  สถานะ      : %s\n"
      "  เวลาไทย    : %02d:%02d   (เซิร์ฟเวอร์ GMT%+d)\n"
      "  ราคา       : %.2f    สเปรด $%.2f\n"
      "  ไม้วันนี้   : %s   (ชนะ %d / แพ้ %d)\n"
      "  กำไรวันนี้  : %.2f   ลอย %.2f\n"
      "  ล็อตถัดไป   : %.2f   (เพดาน %.2f)\n"
      "  SL ที่ใช้จริง: $%.2f\n",
      _Symbol, state, ThaiMin() / 60, ThaiMin() % 60, g_gmt,
      Bid(), SpreadPrice(), quota, g_dayWin, g_dayLoss,
      g_dayNet, Floating(), CalcLot(), InpMaxLot, EffSL());
   Comment(txt);
  }

//=================== เริ่มต้น =======================================
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_gmt = ServerGMT();
   RefreshStats(true);

   PrintFormat("═══ XAU StraddleCore v1 | %s ═══", AccountInfoString(ACCOUNT_COMPANY));
   PrintFormat("สัญลักษณ์=%s ทศนิยม=%d 1จุด=%.5f ขนาดสัญญา=%.0f เซิร์ฟเวอร์=GMT%+d",
               _Symbol, Digs(), Pt(),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE), g_gmt);
   PrintFormat("ระยะที่ใช้จริง: คร่อม=$%.2f  SL=$%.2f  TP=$%.2f  ขั้นต่ำโบรก=$%.2f",
               MathMax(D2P(InpEntryDist), MinStop() + Pt()), EffSL(),
               D2P(InpTakeProfit), MinStop());
   PrintFormat("ล็อตไม้แรก=%.2f (เพดาน %.2f) | โหมด=%s",
               CalcLot(), InpMaxLot,
               (InpLotMode == LOT_FIXED ? "ล็อตคงที่" : "ตาม % ความเสี่ยง"));

   //--- ตรวจค่าที่ตั้งมาว่าสมเหตุสมผลไหม ตอนที่ยังแก้ทัน
   bool warn = false;

   if(InpMaxLot <= 0.0)
     {
      Print("❌ InpMaxLot ต้องมากกว่า 0 เสมอ - เพดานล็อตคือตาข่ายกันพอร์ตแตก");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(D2P(InpEntryDist) < MinStop())
     {
      PrintFormat("⚠ ระยะคร่อม ($%.2f) แคบกว่าขั้นต่ำโบรก ($%.2f) -> EA จะขยายให้เอง "
                  "ซึ่งทำให้พฤติกรรมต่างจากที่ตั้งใจ",
                  D2P(InpEntryDist), MinStop()); warn = true;
     }
   if(D2P(InpBEStart) <= D2P(InpBELock))
     {
      Print("⚠ InpBEStart ต้องมากกว่า InpBELock ไม่งั้นกันทุนจะสั่งเลื่อน SL "
            "ไปเหนือราคาปัจจุบัน"); warn = true;
     }
   if(InpLotMode == LOT_RISK && InpRiskPercent > 2.0)
     {
      PrintFormat("⚠ เสี่ยง %.1f%% ต่อไม้สูงมาก | แพ้ติดกัน %d ไม้ = เสียครึ่งพอร์ต",
                  InpRiskPercent, (int)MathCeil(50.0 / InpRiskPercent)); warn = true;
     }
   if(!InpUseTimeFilter)
      Print("⚠ ปิด Time Filter อยู่ | ผลทดสอบชี้ว่านี่คือพารามิเตอร์ที่สำคัญที่สุด "
            "และค่าที่ดีที่สุดทุกชุดเปิดไว้");
   if(InpMaxTradesDay <= 0)
      Print("⚠ ไม่จำกัดจำนวนไม้ต่อวัน | บนพอร์ตเล็กค่าคอมจะกินหนัก "
            "(ทดสอบแล้ว: จ่ายคอม 32% ของพอร์ต $300 ใน 5 วัน)");
   if(!InpUseDailyLoss)
      Print("⚠ ไม่ได้เปิดเพดานขาดทุนรายวัน | วันที่แย่จริงๆ จะไม่มีอะไรหยุด");

   int f, t;
   if(InpUseTimeFilter && !ParseSess(InpSess1, f, t) && !ParseSess(InpSess2, f, t)
      && !ParseSess(InpSess3, f, t))
     {
      Print("❌ อ่านช่วงเวลาไม่ออกสักช่วง | รูปแบบต้องเป็น \"07:00-08:30\"");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(!warn) Print("✅ ตรวจค่าตั้งต้นผ่าน");
   Print("⚠ ยังไม่ผ่านการยืนยันด้วย real tick data - ทดสอบ Demo ก่อนเสมอ");

   Panel();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   Comment("");
  }

//=================== จับ SL เพื่อเริ่มพัก ============================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   ulong d = trans.deal;
   if(d == 0 || !HistoryDealSelect(d)) return;
   if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(d, DEAL_MAGIC) != (long)InpMagic) return;

   long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;

   g_statCache  = 0;                     // บังคับคิดสถิติใหม่
   g_lastCloseAt = TimeCurrent();
   g_beDone      = false;

   if(HistoryDealGetInteger(d, DEAL_REASON) == DEAL_REASON_SL &&
      InpCooldownAfterSL > 0)
     {
      g_cooldownTill = TimeCurrent() + InpCooldownAfterSL;
      if(InpVerbose)
         PrintFormat("[พัก] โดน SL -> หยุด %d วินาที", InpCooldownAfterSL);
     }
  }

//=================== ลูปหลัก ========================================
void OnTick()
  {
   Core();
   Panel();
  }
//+------------------------------------------------------------------+
