//+------------------------------------------------------------------+
//|                                 XAU_StraddleReverse_v4_4.mq5     |
//|            XAUUSD Straddle Stop-&-Reverse Scalper  (เวอร์ชัน 4)   |
//|                                                                  |
//|  ใหม่ใน v4:                                                      |
//|   1) เมนูตั้งค่าเป็นภาษาไทยทั้งหมด อธิบายชัดทุกบรรทัด           |
//|   2) ระบบ "หน่วยระยะ" เลือกได้ระหว่าง ดอลลาร์/ออนซ์ กับ จุด      |
//|      -> ตั้งเป็นดอลลาร์แล้วย้ายโบรกไหนก็ใช้ค่าเดิมได้ทันที       |
//|      (Exness, VT Markets, IC, XM, Pepperstone ฯลฯ)               |
//|   3) ปรับตัวเองอัตโนมัติ: Digits, Point, StopLevel, FreezeLevel,  |
//|      Filling Mode, GMT Offset (รองรับ DST), Volume Min/Max/Step   |
//|   4) แดชบอร์ดเต็มรูปแบบ: ราคาเรียลไทม์, กราฟเส้นย่อ, แถบความคืบ  |
//|      หน้า, อนุภาคเคลื่อนไหว, หุ่นยนต์แอนิเมชัน 6 อารมณ์          |
//|                                                                  |
//|  *** ต้องใช้บัญชีแบบ HEDGING เท่านั้น / ทดสอบบัญชีเดโมก่อนเสมอ ***|
//+------------------------------------------------------------------+
//  ── ประวัติเวอร์ชัน ──────────────────────────────────────────────
//  4.4  แก้บั๊ก: ห้ามเชื่อ TimeGMT() ใน Strategy Tester
//  4.3  แก้ระบบกลับไม้ที่ยิงไม่ออกทางคณิตศาสตร์ (ReverseGap 1.20->0.60
//       + ResolveReverseGap) และให้ CalcLot รู้ว่า SL ถูกโบรกขยาย
//  4.2  เวอร์ชันเดิมจากผู้เขียน
#property copyright "Custom EA v4"
#property version   "4.4"
#property description "XAUUSD Straddle Stop & Reverse - รองรับทุกโบรกเกอร์"

#include <Trade/Trade.mqh>
#include <Canvas/Canvas.mqh>

CTrade  trade;
CCanvas hud;

#define HUD_W    384
#define HUD_H    446
#define HUD_NAME "SRv4_HUD"
#define PXN      92          // จำนวนจุดของกราฟเส้นย่อ

//=================== ENUM (แสดงผลภาษาไทยในเมนู) =====================
enum ENUM_DIST_UNIT
  {
   UNIT_USD   = 0,   // ดอลลาร์ต่อออนซ์ ($) - แนะนำ ใช้ได้ทุกโบรก
   UNIT_POINT = 1    // จุด (Point) - ตามที่โบรกกำหนด
  };

enum ENUM_LOT_MODE
  {
   LOT_AUTO  = 0,    // คำนวณอัตโนมัติจาก % ความเสี่ยง
   LOT_FIXED = 1     // ใช้ล็อตคงที่ที่กำหนดเอง
  };

//=================== การตั้งค่า =====================================
input group "───────── ⚙ พื้นฐาน ─────────"
input ENUM_DIST_UNIT InpDistUnit = UNIT_USD;   // หน่วยที่ใช้วัดระยะทั้งหมด
input ulong    InpMagic          = 990025;     // เลขประจำตัว EA (ห้ามซ้ำกับ EA ตัวอื่น)
input int      InpSlippage       = 30;         // ค่าคลาดเคลื่อนราคาที่ยอมรับได้ (จุด)
input bool     InpVerboseLog     = true;       // บันทึกรายละเอียดลง Journal (ช่วยหาปัญหา)

input group "───────── 📍 ระยะวางออเดอร์ ─────────"
input double   InpStraddleDist   = 0.50;   // ระยะคร่อมราคา: วางออเดอร์ห่างราคาปัจจุบันเท่าไร
input double   InpStopLoss       = 1.50;   // จุดตัดขาดทุน (SL): ยอมขาดทุนสูงสุดต่อไม้เท่าไร
input double   InpTakeProfit     = 10.00;  // เป้ากำไร (TP): ใส่ 0 = ไม่ตั้งเป้า ปล่อยให้ trailing จัดการ

input group "───────── 🔒 ล็อกกำไร ─────────"
input bool     InpUseBreakeven   = true;   // เปิดใช้การเลื่อน SL มาที่ทุน (กันกำไรหาย)
input double   InpBEStart        = 0.80;   // กำไรถึงเท่าไร จึงเริ่มเลื่อน SL มาที่ทุน
input double   InpBELock         = 0.20;   // เลื่อนแล้วล็อกกำไรขั้นต่ำไว้เท่าไร
input bool     InpUseTrailing    = true;   // เปิดใช้ SL วิ่งตามราคา (เก็บกำไรตอนราคาไหลแรง)
input double   InpTrailStart     = 1.50;   // กำไรถึงเท่าไร จึงเริ่มให้ SL วิ่งตาม
input double   InpTrailDist      = 1.00;   // ให้ SL ตามหลังราคาห่างเท่าไร

input group "───────── 🔄 ระบบกลับไม้ (Reverse) ─────────"
input bool     InpUseReverse     = true;   // เปิดใช้ระบบกลับไม้อัตโนมัติเมื่อราคาย้อนกลับ
input double   InpReverseStartPts= 1.00;   // กำไรถึงเท่าไร จึงวางออเดอร์ดักฝั่งตรงข้าม
input double   InpReverseGap     = 0.60;   // ออเดอร์ดักฝั่งตรงข้ามห่างจากราคาเท่าไร
input bool     InpAutoFixReverseGap = true; // บังคับให้ระยะไม้กลับแคบกว่า SL เสมอ (ถ้าปิด ระบบกลับไม้อาจไม่ทำงานเลย)
input bool     InpTrailOnNewBarOnly = false; // เลื่อนออเดอร์ดักเฉพาะตอนขึ้นแท่งใหม่ (ลดภาระเซิร์ฟเวอร์)

input group "───────── 🛑 คูลดาวน์ / หยุดพัก ─────────"
input bool     InpUseCooldown    = true;   // เปิดใช้การหยุดพักหลังโดน SL
input int      InpCooldownSec    = 60;     // หยุดพักกี่วินาทีหลังโดน SL
input bool     InpCooldownAnyLoss= false;  // หยุดพักทุกครั้งที่ปิดไม้ขาดทุน (ไม่ใช่แค่โดน SL)
input bool     InpCooldownKillPend = true; // ระหว่างหยุดพัก ให้ลบออเดอร์ที่ค้างอยู่ทิ้ง
input int      InpMaxSLPerDay    = 0;      // โดน SL กี่ครั้งต่อวันแล้วหยุดยาว (0 = ไม่จำกัด)

input group "───────── ⏰ Time Filter (ช่วงเวลาทำกำไรดีที่สุด) ─────────"
input bool     InpUseTimeFilter  = true;   // เปิดใช้ Time Filter (ปิด = เทรดตลอด 24 ชม.)
input bool     InpAutoGMTOffset  = true;   // ตรวจเขตเวลาเซิร์ฟเวอร์อัตโนมัติ (แนะนำเปิด)
input int      InpServerGMTOffset= 3;      // เขตเวลาเซิร์ฟเวอร์ (ใช้เมื่อปิดอัตโนมัติ)

input bool     InpS1_On     = true;                              // ✅ ช่วงที่ 1 : 07:00 - 08:30 น.
input int      InpS1_StartH = 7;   input int InpS1_StartM = 0;   // ช่วง 1 เริ่ม (ชม. : นาที)
input int      InpS1_EndH   = 8;   input int InpS1_EndM   = 30;  // ช่วง 1 จบ  (ชม. : นาที)

input bool     InpS2_On     = true;                              // ✅ ช่วงที่ 2 : 19:00 - 20:30 น.
input int      InpS2_StartH = 19;  input int InpS2_StartM = 0;   // ช่วง 2 เริ่ม (ชม. : นาที)
input int      InpS2_EndH   = 20;  input int InpS2_EndM   = 30;  // ช่วง 2 จบ  (ชม. : นาที)

input bool     InpS3_On     = true;                              // ✅ ช่วงที่ 3 : 02:00 - 03:30 น.
input int      InpS3_StartH = 2;   input int InpS3_StartM = 0;   // ช่วง 3 เริ่ม (ชม. : นาที)
input int      InpS3_EndH   = 3;   input int InpS3_EndM   = 30;  // ช่วง 3 จบ  (ชม. : นาที)

input bool     InpCloseAllAtSessionEnd = false; // ปิดไม้ทั้งหมดทันทีเมื่อหมดช่วงเวลา

input group "───────── 💰 ขนาดไม้ / ความเสี่ยง ─────────"
input ENUM_LOT_MODE InpLotMode   = LOT_AUTO;  // วิธีกำหนดขนาดไม้
input double   InpRiskPercent    = 1.0;    // เสี่ยงกี่ % ของเงินทุนต่อไม้ (ใช้กับโหมดอัตโนมัติ)
input double   InpFixedLot       = 0.01;   // ขนาดล็อตคงที่ (ใช้กับโหมดล็อตคงที่)
input double   InpMaxLot         = 0.50;   // ขนาดล็อตสูงสุดที่ยอมให้เปิด (กันพลาด)

input group "───────── 🛡 ตัวกรองความปลอดภัย ─────────"
input double   InpMaxSpread      = 0.60;   // สเปรดกว้างเกินเท่านี้ = ไม่วางออเดอร์ใหม่

input group "───────── 🖥 หน้าจอแดชบอร์ด ─────────"
input bool     InpShowHUD        = true;   // แสดงหน้าจอแดชบอร์ดบนกราฟ
input int      InpHUD_X          = 16;     // ตำแหน่งแนวนอน (พิกเซลจากขอบซ้าย)
input int      InpHUD_Y          = 26;     // ตำแหน่งแนวตั้ง (พิกเซลจากขอบบน)
input int      InpHUD_FPS_ms     = 60;     // ความลื่นของภาพเคลื่อนไหว (มิลลิวินาที ยิ่งน้อยยิ่งลื่น)
input bool     InpHUD_Particles  = true;   // แสดงอนุภาคเคลื่อนไหวพื้นหลัง
input bool     InpHUD_Sparkline  = true;   // แสดงกราฟเส้นราคาย่อ

//=================== ตัวแปรระบบ =====================================
datetime g_lastBarTime   = 0;
datetime g_cooldownUntil = 0;
datetime g_lastPlaceTry  = 0;
int      g_slToday       = 0;
int      g_flipCount     = 0;
double   g_sessionPnL    = 0.0;
int      g_dayOfYear     = -1;
uint     g_frame         = 0;
bool     g_hudReady      = false;
int      g_gmtOffset     = 0;
double   g_revGap        = 0.0;  // ระยะไม้กลับที่ใช้จริง (หน่วยเดียวกับ InpReverseGap)

double   g_px[PXN];
int      g_pxCount       = 0;
double   g_lastBid       = 0.0;
int      g_priceDir      = 0;    // 1 ขึ้น, -1 ลง, 0 นิ่ง

#define MOOD_SLEEP 0
#define MOOD_WAIT  1
#define MOOD_ARMED 2
#define MOOD_WIN   3
#define MOOD_LOSE  4
#define MOOD_COOL  5

struct SBotState
  {
   int    posCount;
   int    pendCount;
   bool   inSession;
   bool   cooling;
   int    cooldownLeft;
   double spreadPts;
   double profitPts;
   double profitMoney;
   double lots;
   long   posType;
   int    mood;
   string statusText;
  };
SBotState g_st;

//=================== ตัวช่วยตัวเลข ==================================
int  Ri(const double v)             { return (int)MathRound(v); }
int  IMax(const int a, const int b) { return (a > b) ? a : b; }
int  IMin(const int a, const int b) { return (a < b) ? a : b; }
uint ARGB(const color c, const uchar a=255) { return ColorToARGB(c, a); }
uchar UC(const int v)               { return (uchar)IMin(255, IMax(0, v)); }

double Pt() { return SymbolInfoDouble(_Symbol, SYMBOL_POINT); }

//--- แปลงค่าที่ผู้ใช้กรอก (ดอลลาร์ หรือ จุด) -> จำนวนจุดของโบรกนี้
int ToPts(const double v)
  {
   if(v <= 0.0) return 0;
   if(InpDistUnit == UNIT_POINT) return (int)MathRound(v);
   double p = Pt();
   if(p <= 0.0) return (int)MathRound(v);
   return (int)MathRound(v / p);
  }

//--- แปลงจุด -> ดอลลาร์ (ใช้แสดงผลบนแดชบอร์ด)
double PtsToUSD(const double pts) { return pts * Pt(); }

double NormPrice(const double p)
  {
   return NormalizeDouble(p, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
  }

double SpreadPts()
  {
   return (SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/Pt();
  }

//--- ระยะขั้นต่ำที่โบรกยอมรับ (ต่างกันมากระหว่างโบรก/ประเภทบัญชี)
int MinStopPts()
  {
   int s = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int f = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return IMax(s, f);
  }

//--- ระยะ SL ที่ "ใช้จริง" หลังโดนโบรกบังคับขยาย
//    ต้องใช้ตัวนี้ทั้งตอนวางออเดอร์และตอนคำนวณล็อต ไม่งั้นความเสี่ยงจริง
//    จะเกินเปอร์เซ็นต์ที่ผู้ใช้ตั้งไว้โดยไม่มีใครรู้
int EffectiveSLPts()
  {
   int want = ToPts(InpStopLoss);
   if(want <= 0) return 0;
   return IMax(want, MinStopPts());
  }

//--- หาระยะไม้กลับที่ยิงออกได้จริง
//    ระบบกลับไม้จะทำงานได้ก็ต่อเมื่อออเดอร์ดักอยู่ "ใกล้ราคามากกว่า" SL ที่คุ้มครองอยู่
//    ถ้าไม่ใช่ ราคาย้อนกลับมาก็จะโดน SL ก่อนเสมอ และไม้กลับจะไม่มีวันถูกชน
//      - ตอน trailing ทำงาน : SL ห่างราคา = InpTrailDist
//      - ตอนเพิ่งวางไม้กลับ : SL อยู่ที่ทุน+ล็อก ห่างราคา = InpReverseStartPts - InpBELock
void ResolveReverseGap()
  {
   g_revGap = InpReverseGap;
   if(!InpUseReverse) return;

   double cap = 1e9;
   if(InpUseTrailing)  cap = MathMin(cap, InpTrailDist);
   if(InpUseBreakeven) cap = MathMin(cap, InpReverseStartPts - InpBELock);
   if(cap >= 1e8) return;               // ไม่มี SL วิ่งตาม จึงไม่ต้องจำกัด

   double safe = cap * 0.75;            // เผื่อระยะกันชน 25%
   if(safe <= 0.0)
     {
      PrintFormat("⚠ ตั้งค่าไม้กลับขัดกันเอง: จุดล็อกทุน (%.2f) ไม่น้อยกว่าจุดวางไม้กลับ (%.2f) "
                  "-> ระบบกลับไม้ทำงานไม่ได้ ให้ลด InpBELock หรือเพิ่ม InpReverseStartPts",
                  InpBELock, InpReverseStartPts);
      return;
     }
   if(g_revGap <= safe) return;         // ตั้งมาถูกต้องอยู่แล้ว

   if(InpAutoFixReverseGap)
     {
      PrintFormat("⚠ ระยะไม้กลับ (%.2f) กว้างกว่าระยะ SL ที่คุ้มครองอยู่ (%.2f) "
                  "-> SL จะโดนก่อนเสมอ ระบบกลับไม้จะไม่ทำงานเลย | ปรับอัตโนมัติเป็น %.2f",
                  g_revGap, cap, safe);
      g_revGap = safe;
     }
   else
      PrintFormat("⚠ ระยะไม้กลับ (%.2f) กว้างกว่าระยะ SL ที่คุ้มครองอยู่ (%.2f) "
                  "-> ระบบกลับไม้จะไม่มีวันทำงาน | เปิด InpAutoFixReverseGap "
                  "หรือลด InpReverseGap ให้ต่ำกว่า %.2f",
                  g_revGap, cap, safe);
  }

bool CheckResult(const string what)
  {
   uint rc = trade.ResultRetcode();
   if(rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED ||
      rc == TRADE_RETCODE_DONE_PARTIAL) return true;
   if(InpVerboseLog)
      PrintFormat("[ไม่สำเร็จ] %s -> %u : %s", what, rc, trade.ResultRetcodeDescription());
   return false;
  }

bool InCooldown()
  {
   if(!InpUseCooldown) return false;
   return (TimeCurrent() < g_cooldownUntil);
  }

int CooldownLeft()
  {
   if(!InCooldown()) return 0;
   return (int)(g_cooldownUntil - TimeCurrent());
  }

bool DayLimitHit()
  {
   return (InpMaxSLPerDay > 0 && g_slToday >= InpMaxSLPerDay);
  }

void ResetDailyIfNeeded()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_year != g_dayOfYear)
     {
      g_dayOfYear  = dt.day_of_year;
      g_slToday    = 0;
      g_sessionPnL = 0.0;
     }
  }

//=================== เขตเวลาอัตโนมัติ ===============================
//--- ⚠ ใน Strategy Tester ค่า TimeGMT() มักคืนค่าเท่ากับ TimeCurrent()
//    ทำให้ตรวจได้ GMT+0 เสมอ และช่วงเวลาเทรดเลื่อนไปผิดหลายชั่วโมงเงียบๆ
//    (ยืนยันจากผลรันจริงของ EA พี่น้องกัน: ไม้ทุกไม้ตกในหน้าต่างของ GMT+0)
//    ในโหมดทดสอบจึงใช้ค่าที่ผู้ใช้ตั้งเองเท่านั้น
int ServerGMTOffset()
  {
   if(MQLInfoInteger(MQL_TESTER)) return InpServerGMTOffset;
   if(!InpAutoGMTOffset) return InpServerGMTOffset;
   long diff = (long)TimeCurrent() - (long)TimeGMT();
   int off = Ri((double)diff / 3600.0);
   if(off < -12 || off > 14) return InpServerGMTOffset;
   return off;
  }

//=================== ตัวกรองเวลา ====================================
bool InWindow(const int h, const int m, const int sh, const int sm,
              const int eh, const int em)
  {
   int now = h*60+m, s = sh*60+sm, e = eh*60+em;
   if(s <= e) return (now >= s && now < e);
   return (now >= s || now < e);
  }

bool SessionOK()
  {
   if(!InpUseTimeFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int thaiMin = (dt.hour*60 + dt.min) + (7 - g_gmtOffset)*60;
   while(thaiMin < 0)     thaiMin += 1440;
   while(thaiMin >= 1440) thaiMin -= 1440;
   int th = thaiMin/60, tm = thaiMin%60;

   if(InpS1_On && InWindow(th,tm, InpS1_StartH,InpS1_StartM, InpS1_EndH,InpS1_EndM)) return true;
   if(InpS2_On && InWindow(th,tm, InpS2_StartH,InpS2_StartM, InpS2_EndH,InpS2_EndM)) return true;
   if(InpS3_On && InWindow(th,tm, InpS3_StartH,InpS3_StartM, InpS3_EndH,InpS3_EndM)) return true;
   return false;
  }

string ThaiTimeStr()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int thaiMin = (dt.hour*60 + dt.min) + (7 - g_gmtOffset)*60;
   while(thaiMin < 0)     thaiMin += 1440;
   while(thaiMin >= 1440) thaiMin -= 1440;
   return StringFormat("%02d:%02d", thaiMin/60, thaiMin%60);
  }

//=================== สแกนออเดอร์ / โพซิชัน ==========================
int CountPositions()
  {
   int n = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == (long)InpMagic) n++;
     }
   return n;
  }

ulong GetPositionTicketByAge(const int index)
  {
   ulong tickets[];
   long  times[];
   int   n = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      ArrayResize(tickets, n+1);
      ArrayResize(times,   n+1);
      tickets[n] = tk;
      times[n]   = PositionGetInteger(POSITION_TIME_MSC);
      n++;
     }
   if(index < 0 || index >= n) return 0;
   for(int a = 0; a < n-1; a++)
      for(int b = 0; b < n-1-a; b++)
         if(times[b] > times[b+1])
           {
            long  t = times[b];   times[b]   = times[b+1];   times[b+1]   = t;
            ulong k = tickets[b]; tickets[b] = tickets[b+1]; tickets[b+1] = k;
           }
   return tickets[index];
  }

ulong GetPendingTicket()
  {
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != (long)InpMagic) continue;
      long t = OrderGetInteger(ORDER_TYPE);
      if(t == ORDER_TYPE_BUY_STOP || t == ORDER_TYPE_SELL_STOP) return tk;
     }
   return 0;
  }

int CountPendings()
  {
   int n = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
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

void DeleteAllPendings()
  {
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != (long)InpMagic) continue;
      long t = OrderGetInteger(ORDER_TYPE);
      if(t == ORDER_TYPE_BUY_STOP || t == ORDER_TYPE_SELL_STOP)
        {
         trade.OrderDelete(tk);
         CheckResult("ลบออเดอร์รอ");
        }
     }
  }

void CloseAllPositions()
  {
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      trade.PositionClose(tk);
      CheckResult("ปิดโพซิชัน");
     }
  }

//=================== คำนวณขนาดไม้ ===================================
double CalcLot()
  {
   double lot = InpFixedLot;
   if(InpLotMode == LOT_AUTO)
     {
      double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney = balance * InpRiskPercent / 100.0;
      double tickVal   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      int    slPts     = EffectiveSLPts();   // ใช้ระยะจริงที่โบรกยอมรับ ไม่ใช่ค่าที่กรอก
      if(tickVal > 0.0 && tickSize > 0.0 && slPts > 0)
        {
         double valPerPt   = tickVal * (Pt()/tickSize);
         double lossPerLot = slPts * valPerPt;
         if(lossPerLot > 0.0) lot = riskMoney / lossPerLot;
        }
     }
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0.0) lotStep = 0.01;
   if(minLot  <= 0.0) minLot  = 0.01;
   if(maxLot  <= 0.0) maxLot  = 100.0;

   lot = MathFloor(lot/lotStep)*lotStep;
   double cap = MathMin(InpMaxLot, maxLot);
   lot = MathMax(minLot, MathMin(cap, lot));

   int lotDigits = 2;
   if(lotStep >= 0.1)  lotDigits = 1;
   if(lotStep >= 1.0)  lotDigits = 0;
   if(lotStep <= 0.001) lotDigits = 3;
   return NormalizeDouble(lot, lotDigits);
  }

//=================== วางออเดอร์ =====================================
bool PlaceBuyStop(double price)
  {
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minD = MinStopPts()*Pt();
   if(price < ask + minD) price = ask + minD;
   price = NormPrice(price);

   int slP = EffectiveSLPts();
   int tpP = IMax(ToPts(InpTakeProfit), MinStopPts());
   double sl = (slP > 0) ? NormPrice(price - slP*Pt()) : 0.0;
   double tp = (ToPts(InpTakeProfit) > 0) ? NormPrice(price + tpP*Pt()) : 0.0;

   trade.BuyStop(CalcLot(), price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "SRv4");
   return CheckResult("วาง Buy Stop");
  }

bool PlaceSellStop(double price)
  {
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minD = MinStopPts()*Pt();
   if(price > bid - minD) price = bid - minD;
   price = NormPrice(price);

   int slP = EffectiveSLPts();
   int tpP = IMax(ToPts(InpTakeProfit), MinStopPts());
   double sl = (slP > 0) ? NormPrice(price + slP*Pt()) : 0.0;
   double tp = (ToPts(InpTakeProfit) > 0) ? NormPrice(price - tpP*Pt()) : 0.0;

   trade.SellStop(CalcLot(), price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "SRv4");
   return CheckResult("วาง Sell Stop");
  }

void PlaceStraddle()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double d   = IMax(ToPts(InpStraddleDist), MinStopPts()) * Pt();
   PlaceBuyStop(ask + d);
   PlaceSellStop(bid - d);
  }

//=================== เลื่อน SL ======================================
void ManageStops(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return;
   long   type = PositionGetInteger(POSITION_TYPE);
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double tp   = PositionGetDouble(POSITION_TP);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double profitPts = (type == POSITION_TYPE_BUY) ? (bid-open)/Pt() : (open-ask)/Pt();
   double newSL = 0.0;

   if(InpUseTrailing && profitPts >= ToPts(InpTrailStart))
      newSL = (type == POSITION_TYPE_BUY) ? bid - ToPts(InpTrailDist)*Pt()
                                          : ask + ToPts(InpTrailDist)*Pt();
   else if(InpUseBreakeven && profitPts >= ToPts(InpBEStart))
      newSL = (type == POSITION_TYPE_BUY) ? open + ToPts(InpBELock)*Pt()
                                          : open - ToPts(InpBELock)*Pt();
   if(newSL == 0.0) return;

   double minD = MinStopPts()*Pt();
   if(type == POSITION_TYPE_BUY  && newSL > bid - minD) return;
   if(type == POSITION_TYPE_SELL && newSL < ask + minD) return;

   newSL = NormPrice(newSL);
   bool improve = (type == POSITION_TYPE_BUY)
                  ? (sl == 0.0 || newSL > sl + Pt()*0.5)
                  : (sl == 0.0 || newSL < sl - Pt()*0.5);
   if(improve)
     {
      trade.PositionModify(ticket, newSL, tp);
      CheckResult("เลื่อน SL");
     }
  }

//=================== เก็บราคาไว้ทำกราฟ ==============================
void PushPrice(const double p)
  {
   if(p <= 0.0) return;
   for(int i = 0; i < PXN-1; i++) g_px[i] = g_px[i+1];
   g_px[PXN-1] = p;
   if(g_pxCount < PXN) g_pxCount++;
  }

//=================== อ่านสถานะ ======================================
void UpdateState()
  {
   g_gmtOffset       = ServerGMTOffset();
   g_st.posCount     = CountPositions();
   g_st.pendCount    = CountPendings();
   g_st.inSession    = SessionOK();
   g_st.cooling      = InCooldown();
   g_st.cooldownLeft = CooldownLeft();
   g_st.spreadPts    = SpreadPts();
   g_st.profitPts    = 0.0;
   g_st.profitMoney  = 0.0;
   g_st.lots         = 0.0;
   g_st.posType      = -1;

   if(g_st.posCount > 0)
     {
      ulong tk = GetPositionTicketByAge(0);
      if(tk > 0 && PositionSelectByTicket(tk))
        {
         g_st.posType = PositionGetInteger(POSITION_TYPE);
         g_st.lots    = PositionGetDouble(POSITION_VOLUME);
         double open  = PositionGetDouble(POSITION_PRICE_OPEN);
         double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         g_st.profitPts   = (g_st.posType == POSITION_TYPE_BUY)
                            ? (bid-open)/Pt() : (open-ask)/Pt();
         g_st.profitMoney = PositionGetDouble(POSITION_PROFIT)
                          + PositionGetDouble(POSITION_SWAP);
        }
     }

   if(DayLimitHit())
     { g_st.mood = MOOD_SLEEP; g_st.statusText = "หยุดยาว: โดน SL ครบโควตาวันนี้แล้ว"; }
   else if(g_st.cooling)
     { g_st.mood = MOOD_COOL;  g_st.statusText = "กำลังพักฟื้น รอครบเวลาแล้วลุยต่อ"; }
   else if(g_st.posCount > 0)
     {
      if(g_st.profitPts >= 0.0)
        { g_st.mood = MOOD_WIN;  g_st.statusText = "กำไรกำลังวิ่ง! ระบบล็อกกำไรทำงานอยู่"; }
      else
        { g_st.mood = MOOD_LOSE; g_st.statusText = "ติดลบอยู่ รอ SL หรือระบบกลับไม้"; }
     }
   else if(!g_st.inSession)
     { g_st.mood = MOOD_SLEEP; g_st.statusText = "นอกช่วงเวลาเทรด ขอพักก่อนนะ"; }
   else if(g_st.pendCount >= 2)
     { g_st.mood = MOOD_ARMED; g_st.statusText = "วางกับดักคร่อมราคาแล้ว รอราคาชน!"; }
   else
     { g_st.mood = MOOD_WAIT;  g_st.statusText = "กำลังสแกนตลาด รอจังหวะเข้า"; }
  }

//=================== ตัวช่วยวาดแดชบอร์ด =============================
void PanelRounded(const int x1, const int y1, const int x2, const int y2,
                  const uint clr, const int r=10)
  {
   if(x2-x1 < r*2 || y2-y1 < r*2)
     { hud.FillRectangle(x1, y1, x2, y2, clr); return; }
   hud.FillRectangle(x1+r, y1,   x2-r, y2,   clr);
   hud.FillRectangle(x1,   y1+r, x2,   y2-r, clr);
   hud.FillCircle(x1+r, y1+r, r, clr);
   hud.FillCircle(x2-r, y1+r, r, clr);
   hud.FillCircle(x1+r, y2-r, r, clr);
   hud.FillCircle(x2-r, y2-r, r, clr);
  }

//--- กรอบเรืองแสง วาดซ้อนหลายชั้นแบบจางลง
void GlowFrame(const int x1, const int y1, const int x2, const int y2,
               const color c, const int layers, const int r)
  {
   for(int i = layers; i >= 1; i--)
     {
      uchar a = UC(14 + (layers-i)*6);
      PanelRounded(x1-i, y1-i, x2+i, y2+i, ARGB(c, a), r+i);
     }
  }

void HudRow(const int y, const string label, const string val, const color vc)
  {
   hud.FontSet("Tahoma", -100, FW_NORMAL);
   hud.TextOut(18, y, label, ARGB(C'118,138,170'), TA_LEFT|TA_TOP);
   hud.FontSet("Tahoma", -105, FW_BOLD);
   hud.TextOut(HUD_W-18, y, val, ARGB(vc), TA_RIGHT|TA_TOP);
  }

//--- แถบความคืบหน้า
void ProgressBar(const int x1, const int y, const int x2, const int h,
                 const double ratio, const color c, const string caption)
  {
   double r = MathMax(0.0, MathMin(1.0, ratio));
   hud.FontSet("Tahoma", -85, FW_NORMAL);
   hud.TextOut(x1, y-13, caption, ARGB(C'110,130,160'), TA_LEFT|TA_TOP);
   hud.TextOut(x2, y-13, StringFormat("%.0f%%", r*100.0),
               ARGB(c), TA_RIGHT|TA_TOP);
   PanelRounded(x1, y, x2, y+h, ARGB(C'26,34,52'), h/2);
   int fillTo = x1 + Ri((double)(x2-x1) * r);
   if(fillTo > x1 + h)
     {
      PanelRounded(x1, y, fillTo, y+h, ARGB(c, 235), h/2);
      hud.FillCircle(fillTo-h/2, y+h/2, h/2-1, ARGB(clrWhite, 180));
     }
  }

color MoodColor(const int mood)
  {
   switch(mood)
     {
      case MOOD_WIN:   return C'0,235,150';
      case MOOD_LOSE:  return C'255,86,86';
      case MOOD_ARMED: return C'0,229,255';
      case MOOD_COOL:  return C'255,184,44';
      case MOOD_SLEEP: return C'112,128,156';
     }
   return C'150,170,200';
  }

//--- อนุภาคพื้นหลัง (คำนวณจากเฟรม ไม่ต้องเก็บสถานะ)
void DrawParticles(const uint f, const color c)
  {
   if(!InpHUD_Particles) return;
   for(int i = 0; i < 16; i++)
     {
      double ph = (double)i * 1.37;
      int px = 20 + (int)((MathSin(ph) * 0.5 + 0.5) * (HUD_W - 40));
      int py = (int)(((double)((f/2 + (uint)(i*23)) % 400)) / 400.0 * (HUD_H - 60)) + 30;
      uchar a = UC(20 + (int)(MathSin((double)f*0.05 + ph) * 18 + 18));
      hud.FillCircle(px, py, (i % 3 == 0) ? 2 : 1, ARGB(c, a));
     }
  }

//--- กราฟเส้นราคาย่อ
void DrawSparkline(const int x1, const int y1, const int x2, const int y2,
                   const color c)
  {
   PanelRounded(x1, y1, x2, y2, ARGB(C'14,20,34', 220), 8);
   if(!InpHUD_Sparkline || g_pxCount < 3) 
     {
      hud.FontSet("Tahoma", -85, FW_NORMAL);
      hud.TextOut((x1+x2)/2, (y1+y2)/2-6, "กำลังเก็บข้อมูลราคา...",
                  ARGB(C'80,96,124'), TA_CENTER|TA_TOP);
      return;
     }

   int start = PXN - g_pxCount;
   double mn = g_px[start], mx = g_px[start];
   for(int i = start; i < PXN; i++)
     {
      if(g_px[i] < mn) mn = g_px[i];
      if(g_px[i] > mx) mx = g_px[i];
     }
   double rng = mx - mn;
   if(rng <= 0.0) rng = Pt() * 10.0;

   int   w = x2 - x1 - 12;
   int   h = y2 - y1 - 14;
   int   prevX = 0, prevY = 0;
   bool  first = true;

   // เส้นกึ่งกลางจางๆ
   hud.FillRectangle(x1+6, (y1+y2)/2, x2-6, (y1+y2)/2, ARGB(C'34,44,66'));

   for(int i = start; i < PXN; i++)
     {
      double t = (double)(i - start) / (double)MathMax(1, g_pxCount - 1);
      int cx = x1 + 6 + Ri(t * (double)w);
      int cy = y2 - 7 - Ri(((g_px[i] - mn) / rng) * (double)h);
      if(!first)
        {
         hud.LineAA(prevX, prevY, cx, cy, ARGB(c, 230));
         hud.LineAA(prevX, prevY+1, cx, cy+1, ARGB(c, 70));
        }
      prevX = cx; prevY = cy; first = false;
     }
   // จุดหัวเส้นกระพริบ
   uchar pa = UC(150 + (int)(MathSin((double)g_frame*0.2)*100));
   hud.FillCircle(prevX, prevY, 4, ARGB(c, pa));
   hud.FillCircle(prevX, prevY, 2, ARGB(clrWhite));

   hud.FontSet("Tahoma", -80, FW_NORMAL);
   hud.TextOut(x1+8, y1+4, StringFormat("สูง %.2f", mx), ARGB(C'90,108,138'), TA_LEFT|TA_TOP);
   hud.TextOut(x2-8, y1+4, StringFormat("ต่ำ %.2f", mn), ARGB(C'90,108,138'), TA_RIGHT|TA_TOP);
  }

//=================== หุ่นยนต์ =======================================
void DrawMascot(const int cx, const int baseY, const int mood, const uint f)
  {
   color body  = MoodColor(mood);
   uint  cBody = ARGB(body);
   uint  cDark = ARGB(C'18,26,42');

   double bob = MathSin((double)f * 0.11) * 3.5;
   if(mood == MOOD_COOL || mood == MOOD_SLEEP)
      bob = MathSin((double)f * 0.045) * 2.0;
   int cy = baseY + Ri(bob);

   // วงแหวนพลังงานหมุนรอบตัว
   if(mood != MOOD_SLEEP)
     {
      double ang = (double)f * 0.09;
      for(int i = 0; i < 3; i++)
        {
         double a = ang + (double)i * 2.094;
         int rx = cx + Ri(MathCos(a) * 30.0);
         int ry = cy + 6 + Ri(MathSin(a) * 9.0);
         uchar al = UC(60 + (int)(MathSin(a) * 90 + 90));
         hud.FillCircle(rx, ry, 2, ARGB(body, al));
        }
     }

   // เงา
   int shW = 20 - Ri(bob);
   hud.FillEllipse(cx-shW, baseY+32, cx+shW, baseY+38, ARGB(C'0,0,0', 80));

   // เสาอากาศ + ไฟ
   hud.LineAA(cx, cy-21, cx, cy-31, cBody);
   bool  ledOn = ((f/4) % 2 == 0);
   color led   = (mood == MOOD_LOSE) ? clrRed
               : ((mood == MOOD_WIN) ? clrLime : body);
   hud.FillCircle(cx, cy-33, (ledOn ? 5 : 3), ARGB(led, UC(ledOn ? 110 : 60)));
   hud.FillCircle(cx, cy-33, 3, ARGB(led));

   // หัว
   PanelRounded(cx-21, cy-21, cx+21, cy+9, cBody, 9);
   PanelRounded(cx-16, cy-16, cx+16, cy+4, cDark, 6);

   // ตา
   bool blink = ((f % 48) < 3);
   int  eyeY  = cy - 7;
   if(mood == MOOD_SLEEP || mood == MOOD_COOL || blink)
     {
      hud.LineAA(cx-12, eyeY, cx-4,  eyeY, ARGB(clrWhite));
      hud.LineAA(cx+4,  eyeY, cx+12, eyeY, ARGB(clrWhite));
     }
   else
     {
      int look = 0;
      if(mood == MOOD_WAIT || mood == MOOD_ARMED)
         look = Ri(MathSin((double)f * 0.07) * 3.0);
      hud.FillCircle(cx-8+look, eyeY, 4, ARGB(clrWhite, 90));
      hud.FillCircle(cx+8+look, eyeY, 4, ARGB(clrWhite, 90));
      hud.FillCircle(cx-8+look, eyeY, 3, ARGB(clrWhite));
      hud.FillCircle(cx+8+look, eyeY, 3, ARGB(clrWhite));
     }

   // ปาก
   int mY = cy - 1;
   switch(mood)
     {
      case MOOD_WIN:
         hud.LineAA(cx-7, mY,   cx-2, mY+4, ARGB(clrWhite));
         hud.LineAA(cx-2, mY+4, cx+2, mY+4, ARGB(clrWhite));
         hud.LineAA(cx+2, mY+4, cx+7, mY,   ARGB(clrWhite));
         break;
      case MOOD_LOSE:
         hud.LineAA(cx-7, mY+4, cx-2, mY,   ARGB(clrWhite));
         hud.LineAA(cx-2, mY,   cx+2, mY,   ARGB(clrWhite));
         hud.LineAA(cx+2, mY,   cx+7, mY+4, ARGB(clrWhite));
         break;
      case MOOD_ARMED:
         hud.FillCircle(cx, mY+2, 3, ARGB(clrWhite));
         break;
      default:
         hud.LineAA(cx-6, mY+2, cx+6, mY+2, ARGB(clrWhite));
         break;
     }

   // ลำตัว + แถบสแกน
   PanelRounded(cx-15, cy+11, cx+15, cy+32, cBody, 7);
   int barX = cx - 11 + Ri((double)(f % 44) * 0.5);
   hud.FillRectangle(cx-11, cy+18, cx+11, cy+22, ARGB(C'18,26,42'));
   hud.FillRectangle(barX, cy+18, IMin(barX+7, cx+11), cy+22, ARGB(clrWhite, 210));

   // แขน
   int wave = 0;
   if(mood != MOOD_SLEEP && mood != MOOD_COOL)
      wave = Ri(MathSin((double)f * 0.24) * 7.0);
   hud.LineAA(cx-15, cy+15, cx-24, cy+21 - wave, cBody);
   hud.LineAA(cx+15, cy+15, cx+24, cy+21 + wave, cBody);

   // zZz ตอนพัก
   if(mood == MOOD_SLEEP || mood == MOOD_COOL)
     {
      hud.FontSet("Tahoma", -95, FW_BOLD);
      int   step = (int)((f/6) % 10);
      uchar al   = UC(210 - step*19);
      hud.TextOut(cx+24, cy-34-step,    "z", ARGB(C'200,220,255', al), TA_LEFT|TA_TOP);
      hud.TextOut(cx+33, cy-45-step, "Z", ARGB(C'200,220,255', UC(al/2)), TA_LEFT|TA_TOP);
     }
  }

//=================== วาดแดชบอร์ดทั้งหน้า ============================
void DrawHUD()
  {
   if(!g_hudReady) return;

   color acc = MoodColor(g_st.mood);
   hud.Erase(ARGB(clrBlack, 0));

   // ---- พื้นหลัง + ขอบเรืองแสง ----
   GlowFrame(4, 4, HUD_W-5, HUD_H-5, acc, 3, 14);
   PanelRounded(4, 4, HUD_W-5, HUD_H-5, ARGB(C'9,13,23', 243), 14);
   DrawParticles(g_frame, acc);

   // แถบไฟวิ่งด้านบน
   int lightX = 14 + Ri((double)(g_frame % 120) / 120.0 * (double)(HUD_W-28));
   hud.FillRectangle(14, 5, HUD_W-14, 7, ARGB(C'30,40,60'));
   hud.FillRectangle(IMax(14, lightX-28), 5, IMin(HUD_W-14, lightX+28), 7, ARGB(acc, 255));

   // ---- ส่วนหัว ----
   hud.FontSet("Tahoma", -130, FW_BOLD);
   hud.TextOut(18, 16, "XAU", ARGB(C'255,203,64'), TA_LEFT|TA_TOP);
   hud.TextOut(58, 16, "STRADDLE", ARGB(clrWhite), TA_LEFT|TA_TOP);
   hud.FontSet("Tahoma", -105, FW_BOLD);
   hud.TextOut(HUD_W-18, 19, "SAR v4", ARGB(acc), TA_RIGHT|TA_TOP);

   hud.FontSet("Tahoma", -83, FW_NORMAL);
   hud.TextOut(18, 36, _Symbol + "  •  " + AccountInfoString(ACCOUNT_COMPANY),
               ARGB(C'96,114,146'), TA_LEFT|TA_TOP);
   hud.TextOut(HUD_W-18, 36, "ไทย " + ThaiTimeStr() +
               StringFormat("  (GMT%+d)", g_gmtOffset),
               ARGB(C'96,114,146'), TA_RIGHT|TA_TOP);

   hud.FillRectangle(16, 52, HUD_W-16, 53, ARGB(C'36,48,72'));

   // ---- บล็อกราคา ----
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   color  pc  = (g_priceDir > 0) ? C'0,235,150' : ((g_priceDir < 0) ? C'255,86,86' : C'200,215,235');
   PanelRounded(16, 60, HUD_W-16, 108, ARGB(C'15,21,36', 235), 10);

   hud.FontSet("Tahoma", -230, FW_BOLD);
   hud.TextOut(26, 66, StringFormat("%.2f", bid), ARGB(pc), TA_LEFT|TA_TOP);

   string arrow = (g_priceDir > 0) ? "▲" : ((g_priceDir < 0) ? "▼" : "—");
   hud.FontSet("Tahoma", -140, FW_BOLD);
   hud.TextOut(152, 72, arrow, ARGB(pc), TA_LEFT|TA_TOP);

   hud.FontSet("Tahoma", -85, FW_NORMAL);
   hud.TextOut(HUD_W-26, 68, "สเปรด", ARGB(C'96,114,146'), TA_RIGHT|TA_TOP);
   hud.FontSet("Tahoma", -115, FW_BOLD);
   color spc = (g_st.spreadPts > ToPts(InpMaxSpread)) ? C'255,86,86' : C'0,235,150';
   hud.TextOut(HUD_W-26, 80, StringFormat("$%.2f", PtsToUSD(g_st.spreadPts)),
               ARGB(spc), TA_RIGHT|TA_TOP);

   // ---- กราฟเส้นย่อ ----
   DrawSparkline(16, 114, HUD_W-16, 168, acc);

   // ---- แถวข้อมูล ----
   int y = 178;
   HudRow(y, "Time Filter", (g_st.inSession ? "● ในช่วงเทรด" : "○ นอกช่วงเทรด"),
          (g_st.inSession ? C'0,235,150' : C'112,128,156'));
   y += 21;

   string posTxt = "ยังไม่มีไม้";
   color  posClr = C'112,128,156';
   if(g_st.posCount > 0)
     {
      posTxt = ((g_st.posType == POSITION_TYPE_BUY) ? "ซื้อ (BUY)" : "ขาย (SELL)")
             + StringFormat("  %.2f", g_st.lots);
      posClr = (g_st.posType == POSITION_TYPE_BUY) ? C'0,200,255' : C'255,140,90';
     }
   HudRow(y, "ไม้ที่ถืออยู่", posTxt, posClr);
   y += 21;

   HudRow(y, "ออเดอร์ดักไว้", IntegerToString(g_st.pendCount) + " ไม้",
          (g_st.pendCount > 0) ? C'0,229,255' : C'112,128,156');
   y += 21;

   string plTxt = (g_st.posCount > 0)
                  ? StringFormat("$%.2f  (%.2f)", PtsToUSD(g_st.profitPts), g_st.profitMoney)
                  : "—";
   HudRow(y, "กำไรไม้นี้", plTxt,
          (g_st.profitPts >= 0.0) ? C'0,235,150' : C'255,86,86');
   y += 21;

   HudRow(y, "กำไร/ขาดทุนวันนี้", StringFormat("%.2f", g_sessionPnL),
          (g_sessionPnL >= 0.0) ? C'0,235,150' : C'255,86,86');
   y += 21;

   string slTxt = "โดน SL " + IntegerToString(g_slToday) + " ครั้ง";
   if(InpMaxSLPerDay > 0) slTxt += "/" + IntegerToString(InpMaxSLPerDay);
   slTxt += "  •  กลับไม้ " + IntegerToString(g_flipCount);
   HudRow(y, "สถิติวันนี้", slTxt,
          (g_slToday > 0) ? C'255,184,44' : C'190,206,232');
   y += 21;

   HudRow(y, "ระยะขั้นต่ำโบรก", StringFormat("$%.2f", PtsToUSD(MinStopPts())),
          (MinStopPts() > ToPts(InpStraddleDist)) ? C'255,184,44' : C'190,206,232');
   y += 28;

   // ---- แถบความคืบหน้า ----
   int px1 = 20, px2 = HUD_W-20;
   if(g_st.posCount > 0)
     {
      double toRev = (ToPts(InpReverseStartPts) > 0)
                     ? g_st.profitPts / (double)ToPts(InpReverseStartPts) : 0.0;
      ProgressBar(px1, y, px2, 9, toRev, C'0,229,255', "ความคืบหน้าสู่จุดวางไม้กลับ");
      y += 26;

      double toBE = (ToPts(InpBEStart) > 0)
                    ? g_st.profitPts / (double)ToPts(InpBEStart) : 0.0;
      ProgressBar(px1, y, px2, 9, toBE, C'0,235,150', "ความคืบหน้าสู่จุดล็อกทุน");
      y += 26;
     }
   else if(g_st.cooling)
     {
      double r = (InpCooldownSec > 0)
                 ? (double)g_st.cooldownLeft / (double)InpCooldownSec : 0.0;
      ProgressBar(px1, y, px2, 9, r, C'255,184,44',
                  "พักฟื้นอีก " + IntegerToString(g_st.cooldownLeft) + " วินาที");
      y += 26;
      ProgressBar(px1, y, px2, 9, 0.0, C'40,52,76', " ");
      y += 26;
     }
   else
     {
      ProgressBar(px1, y, px2, 9, 1.0, acc, "ระบบพร้อมทำงาน");
      y += 26;
      ProgressBar(px1, y, px2, 9, 0.0, C'40,52,76', " ");
      y += 26;
     }

   // ---- หุ่นยนต์ + กล่องคำพูด ----
   int mascotY = HUD_H - 58;
   DrawMascot(50, mascotY, g_st.mood, g_frame);

   PanelRounded(88, HUD_H-84, HUD_W-16, HUD_H-32, ARGB(C'20,28,46', 246), 9);
   hud.FillRectangle(83, HUD_H-62, 89, HUD_H-54, ARGB(C'20,28,46', 246));
   hud.FontSet("Tahoma", -95, FW_NORMAL);
   hud.TextOut(98, HUD_H-74, g_st.statusText, ARGB(C'214,228,250'), TA_LEFT|TA_TOP);
   hud.FontSet("Tahoma", -80, FW_NORMAL);
   hud.TextOut(98, HUD_H-52, "หน่วยระยะ: " +
               ((InpDistUnit == UNIT_USD) ? "ดอลลาร์/ออนซ์" : "จุด") +
               StringFormat("  •  1 จุด = %.5f", Pt()),
               ARGB(C'96,114,146'), TA_LEFT|TA_TOP);

   hud.Update();
  }

//=================== เริ่มต้น / ปิด =================================
int OnInit()
  {
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Alert("EA นี้ต้องใช้บัญชีแบบ HEDGING เท่านั้น\n"
            "บัญชีปัจจุบันเป็นแบบ Netting ซึ่งเปิดไม้สวนทางพร้อมกันไม่ได้\n"
            "กรุณาเปิดบัญชี MT5 แบบ Hedging (Exness/VT Markets เป็น Hedging อยู่แล้ว)");
      return(INIT_FAILED);
     }

   ArrayInitialize(g_px, 0.0);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);   // ปรับ Filling Mode ตามโบรกอัตโนมัติ

   ResetDailyIfNeeded();
   g_gmtOffset = ServerGMTOffset();
   ResolveReverseGap();

   PrintFormat("════ ตรวจสเปกโบรก: %s ════", AccountInfoString(ACCOUNT_COMPANY));
   PrintFormat("สัญลักษณ์=%s  ทศนิยม=%d  1จุด=%.5f  ขนาดสัญญา=%.0f",
               _Symbol,
               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
               Pt(),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE));
   PrintFormat("ระยะขั้นต่ำ Stop=%d จุด  Freeze=%d จุด  ($%.2f)",
               (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
               (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL),
               PtsToUSD(MinStopPts()));
   PrintFormat("ล็อต ต่ำสุด=%.2f  สูงสุด=%.2f  ขั้น=%.2f  เขตเวลาเซิร์ฟเวอร์=GMT%+d",
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
               g_gmtOffset);
   PrintFormat("ระยะที่ใช้จริง: คร่อม=%d  SL=%d  TP=%d  ไม้กลับ=%d จุด",
               ToPts(InpStraddleDist), EffectiveSLPts(),
               ToPts(InpTakeProfit), ToPts(g_revGap));

   if(ToPts(InpStraddleDist) < MinStopPts())
      PrintFormat("⚠ เตือน: ระยะคร่อมที่ตั้งไว้ ($%.2f) แคบกว่าระยะขั้นต่ำของโบรก ($%.2f) "
                  "-> EA จะขยายระยะให้อัตโนมัติ ซึ่งทำให้พฤติกรรมต่างจากที่ตั้งใจ",
                  InpDistUnit == UNIT_USD ? InpStraddleDist : PtsToUSD(InpStraddleDist),
                  PtsToUSD(MinStopPts()));

   bool tester   = (bool)MQLInfoInteger(MQL_TESTER);
   bool visual   = (bool)MQLInfoInteger(MQL_VISUAL_MODE);
   bool optimize = (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   bool hudAllow = InpShowHUD && !optimize && (!tester || visual);

   if(hudAllow)
     {
      if(hud.CreateBitmapLabel(0, 0, HUD_NAME, InpHUD_X, InpHUD_Y,
                               HUD_W, HUD_H, COLOR_FORMAT_ARGB_NORMALIZE))
        {
         ObjectSetInteger(0, HUD_NAME, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
         ObjectSetInteger(0, HUD_NAME, OBJPROP_BACK,       false);
         ObjectSetInteger(0, HUD_NAME, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, HUD_NAME, OBJPROP_HIDDEN,     true);
         g_hudReady = true;
         EventSetMillisecondTimer(IMax(25, InpHUD_FPS_ms));
        }
      else
         PrintFormat("[แดชบอร์ด] สร้างไม่สำเร็จ: %d", GetLastError());
     }

   UpdateState();
   DrawHUD();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_hudReady)
     {
      hud.Destroy();
      g_hudReady = false;
     }
   ObjectDelete(0, HUD_NAME);
   ChartRedraw();
  }

//=================== จับ SL เพื่อเริ่มคูลดาวน์ =======================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest    &request,
                        const MqlTradeResult     &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong dt = trans.deal;
   if(dt == 0) return;
   if(!HistoryDealSelect(dt)) return;

   if(HistoryDealGetString(dt, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(dt, DEAL_MAGIC) != (long)InpMagic) return;

   long entry = HistoryDealGetInteger(dt, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;

   long   reason = HistoryDealGetInteger(dt, DEAL_REASON);
   double pnl    = HistoryDealGetDouble(dt, DEAL_PROFIT)
                 + HistoryDealGetDouble(dt, DEAL_SWAP)
                 + HistoryDealGetDouble(dt, DEAL_COMMISSION);

   g_sessionPnL += pnl;

   if(reason == DEAL_REASON_EXPERT) g_flipCount++;

   bool isSL = (reason == DEAL_REASON_SL);
   if(isSL || (InpCooldownAnyLoss && pnl < 0.0 && reason != DEAL_REASON_EXPERT))
     {
      g_slToday++;
      g_cooldownUntil = TimeCurrent() + InpCooldownSec;
      if(InpVerboseLog)
         PrintFormat("[คูลดาวน์] โดน SL (ดีล #%I64u กำไร %.2f) -> พัก %d วินาที ถึง %s | วันนี้โดนแล้ว %d ครั้ง",
                     dt, pnl, InpCooldownSec,
                     TimeToString(g_cooldownUntil, TIME_SECONDS), g_slToday);
     }
  }

//=================== ตัวจับเวลา (ภาพเคลื่อนไหว) =====================
void OnTimer()
  {
   if(!g_hudReady) return;
   g_frame++;
   UpdateState();
   DrawHUD();
  }

//=================== ลูปหลัก ========================================
void OnTick()
  {
   ResetDailyIfNeeded();

   // เก็บราคาไว้ทำกราฟ + ทิศทางราคา
   double bidNow = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(g_lastBid > 0.0)
     {
      if(bidNow > g_lastBid)      g_priceDir = 1;
      else if(bidNow < g_lastBid) g_priceDir = -1;
     }
   g_lastBid = bidNow;
   PushPrice(bidNow);

   bool     newBar = false;
   datetime bt     = iTime(_Symbol, _Period, 0);
   if(bt != g_lastBarTime)
     {
      g_lastBarTime = bt;
      newBar = true;
     }

   UpdateState();

   if(g_hudReady && MQLInfoInteger(MQL_TESTER))
     {
      g_frame++;
      DrawHUD();
     }

   int  posCount  = g_st.posCount;
   int  pendCount = g_st.pendCount;
   bool inSession = g_st.inSession;

   //--- มี 2 ไม้ = เพิ่งกลับไม้ -> ปิดไม้เก่าทันที
   if(posCount >= 2)
     {
      ulong oldT = GetPositionTicketByAge(0);
      if(oldT > 0)
        {
         trade.PositionClose(oldT);
         CheckResult("ปิดไม้เก่าตอนกลับไม้");
        }
      return;
     }

   //--- ยังไม่มีไม้
   if(posCount == 0)
     {
      if(InCooldown() || DayLimitHit())
        {
         if(InpCooldownKillPend && pendCount > 0) DeleteAllPendings();
         return;
        }
      if(!inSession)
        {
         if(pendCount > 0) DeleteAllPendings();
         return;
        }
      if(pendCount >= 2) return;
      if(pendCount == 1) DeleteAllPendings();
      if(SpreadPts() > ToPts(InpMaxSpread)) return;

      if(TimeCurrent() - g_lastPlaceTry < 2) return;
      g_lastPlaceTry = TimeCurrent();

      PlaceStraddle();
      return;
     }

   //--- มี 1 ไม้
   ulong posT = GetPositionTicketByAge(0);
   if(posT == 0 || !PositionSelectByTicket(posT)) return;

   if(!inSession && InpCloseAllAtSessionEnd)
     {
      DeleteAllPendings();
      CloseAllPositions();
      return;
     }

   ManageStops(posT);

   if(!PositionSelectByTicket(posT)) return;
   long   posType   = PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double profitPts = (posType == POSITION_TYPE_BUY)
                      ? (bid-openPrice)/Pt() : (openPrice-ask)/Pt();

   //--- ลบออเดอร์ดักฝั่งเดียวกับไม้ที่ถืออยู่
   ulong pendT = GetPendingTicket();
   if(pendT > 0 && OrderSelect(pendT))
     {
      long pt2 = OrderGetInteger(ORDER_TYPE);
      bool sameSide = (posType == POSITION_TYPE_BUY  && pt2 == ORDER_TYPE_BUY_STOP) ||
                      (posType == POSITION_TYPE_SELL && pt2 == ORDER_TYPE_SELL_STOP);
      if(sameSide)
        {
         trade.OrderDelete(pendT);
         CheckResult("ลบออเดอร์ฝั่งซ้ำ");
         pendT = 0;
        }
     }

   if(!InpUseReverse) return;

   double gap  = IMax(ToPts(g_revGap), MinStopPts()) * Pt();
   double minD = MinStopPts() * Pt();

   //--- ยังไม่มีออเดอร์ดักฝั่งตรงข้าม
   if(pendT == 0)
     {
      if(profitPts >= ToPts(InpReverseStartPts))
        {
         if(SpreadPts() > ToPts(InpMaxSpread)) return;
         if(posType == POSITION_TYPE_BUY) PlaceSellStop(bid - gap);
         else                             PlaceBuyStop(ask + gap);
        }
      return;
     }

   //--- เลื่อนออเดอร์ดักตามราคา
   if(InpTrailOnNewBarOnly && !newBar) return;
   if(!OrderSelect(pendT)) return;
   double pPrice = OrderGetDouble(ORDER_PRICE_OPEN);
   long   pType  = OrderGetInteger(ORDER_TYPE);
   int    slP    = EffectiveSLPts();
   int    tpP    = ToPts(InpTakeProfit);

   if(posType == POSITION_TYPE_BUY && pType == ORDER_TYPE_SELL_STOP)
     {
      double np = NormPrice(bid - gap);
      if(np > pPrice + Pt()*0.5 && np < bid - minD)
        {
         double sl = (slP > 0) ? NormPrice(np + slP*Pt()) : 0.0;
         double tp = (tpP > 0) ? NormPrice(np - tpP*Pt()) : 0.0;
         trade.OrderModify(pendT, np, sl, tp, ORDER_TIME_GTC, 0);
         CheckResult("เลื่อนออเดอร์ดัก (ขาย)");
        }
     }
   else if(posType == POSITION_TYPE_SELL && pType == ORDER_TYPE_BUY_STOP)
     {
      double np = NormPrice(ask + gap);
      if(np < pPrice - Pt()*0.5 && np > ask + minD)
        {
         double sl = (slP > 0) ? NormPrice(np - slP*Pt()) : 0.0;
         double tp = (tpP > 0) ? NormPrice(np + tpP*Pt()) : 0.0;
         trade.OrderModify(pendT, np, sl, tp, ORDER_TIME_GTC, 0);
         CheckResult("เลื่อนออเดอร์ดัก (ซื้อ)");
        }
     }
  }
//+------------------------------------------------------------------+
