//+------------------------------------------------------------------+
//|                            XAUUSD_Straddle_Scalper_TH_v3.mq5     |
//|          อีเอสแตรดเดิลสแกลป์ทองคำ XAUUSD — เวอร์ชัน 3.0 (ภาษาไทย)  |
//|                                                                  |
//|  หลักการทำงาน (อ่านง่ายๆ 7 ข้อ)                                    |
//|   1. วางกับดัก 2 ข้าง: Buy Stop เหนือราคา + Sell Stop ใต้ราคา       |
//|      (ห่างข้างละ 100 จุด) รอราคาวิ่งชนข้างใดข้างหนึ่ง                 |
//|   2. ข้างไหนชนก่อน → ลบอีกข้างทิ้งทันที (ระบบ OCO)                  |
//|   3. ตั้ง SL ตายตัว 250 จุด และ TP 1000 จุด ตั้งแต่วางออเดอร์         |
//|   4. กำไรถึง +60 จุด → เลื่อน SL มากันทุนทันที (ล็อกกำไรขั้นต่ำ)      |
//|   5. หลังกันทุนแล้ว → ไล่ SL ตามแท่งเทียน + ไล่ตามราคาสด            |
//|   6. ไม้ปิดเมื่อไหร่ (ไม่ว่าเหตุผลใด) → วางกับดักใหม่ทันที วนไปเรื่อยๆ  |
//|   7. ถือได้ครั้งละ 1 ไม้เท่านั้น ไม่มีการถัวเฉลี่ย ไม่มีมาร์ติงเกล      |
//|                                                                  |
//|  ★ กฎประจำเครื่อง (ค่าเริ่มต้นของเวอร์ชันนี้) ★                       |
//|   • โหมดจำกัดเวลา = ปิดไว้  →  รันต่อเนื่อง 24 ชั่วโมง                |
//|   • ขาดทุนหนักแค่ไหนก็ไม่หยุดพัก (เพดานรายวันปิดไว้ทั้งหมด)           |
//|   • ถือได้ครั้งละ 1 ไม้เท่านั้นเสมอ                                  |
//|   • TP 1000 จุด / SL 250 จุด / ล็อตอัตโนมัติจากยอดเงิน               |
//|                                                                  |
//|  ฟีเจอร์เสริม (ปิดไว้ เปิดเองได้ทีหลัง)                              |
//|   • จำกัดช่วงเวลาเทรด 3 ช่วง (เวลาไทย GMT+7)                        |
//|   • ถ้าเปิดโหมดเวลา → หมดเวลาแล้วปิดออเดอร์ทิ้งทุกครั้ง               |
//|   • เพดานขาดทุน/กำไรรายวัน → หยุดเทรดถึงเที่ยงคืนไทย                 |
//|                                                                  |
//|  วิธีใช้: ลากใส่กราฟ XAUUSD ไทม์เฟรม M1 หรือ M2                     |
//|  *** คำเตือน: ระบบความเสี่ยงสูง ทดสอบใน Demo ก่อนใช้เงินจริงเสมอ ***  |
//+------------------------------------------------------------------+
#property copyright "AUTO1 Trading Lab"
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>

//====================================================================
//                        ค่าตั้งต้นทั้งหมด
//====================================================================
input group "🎯 การวางออเดอร์ดักสองข้าง (Straddle)"
input long     InpMagicNumber      = 990125;   // เลขประจำตัวอีเอ (Magic Number)
input int      InpBuyStopDistance  = 100;      // ระยะวาง Buy Stop เหนือราคา (จุด)
input int      InpSellStopDistance = 100;      // ระยะวาง Sell Stop ใต้ราคา (จุด)
input int      InpStopLoss         = 250;      // จุดตัดขาดทุน SL ตายตัว (จุด)
input int      InpTakeProfit       = 1000;     // เป้ากำไร TP (จุด) — ใส่ 0 = ไม่ตั้ง TP ปล่อยให้ trailing ตัดสินใจ

input group "⏱ Time-Stop (ฆ่าไม้ที่ไม่ไปไหน ก่อนจะแพงขึ้น)"
input int      InpTimeStopMinutes  = 0;        // เปิดไม้เกินกี่นาทีแล้วยังไม่ไปไหน ให้ปิดทิ้ง (0 = ปิดฟีเจอร์)
input int      InpTimeStopMinPts   = 30;       // "ไปไหน" หมายถึงกำไรต้องถึงกี่จุด

input group "🕐 ช่วงเวลาเทรด (เวลาประเทศไทย GMT+7)"
input bool     InpUseTimeFilter    = false;    // ค่าเริ่มต้น ปิด = เทรด 24 ชม. (เปิด = เทรดเฉพาะ 3 ช่วงล่าง)
input string   InpSession1Start    = "07:00";  // ช่วงที่ 1 เริ่มเทรด
input string   InpSession1End      = "08:30";  // ช่วงที่ 1 หยุดเทรด
input string   InpSession2Start    = "19:00";  // ช่วงที่ 2 เริ่มเทรด
input string   InpSession2End      = "20:30";  // ช่วงที่ 2 หยุดเทรด
input string   InpSession3Start    = "02:00";  // ช่วงที่ 3 เริ่มเทรด
input string   InpSession3End      = "03:30";  // ช่วงที่ 3 หยุดเทรด

input group "⏰ เมื่อหมดเวลาเทรด (สำคัญ)"
input bool     InpCloseOnSessionEnd = true;    // เปิด = หมดเวลาแล้วปิดออเดอร์ทิ้งทุกครั้ง
input int      InpGraceMinutes      = 0;       // ผ่อนผันก่อนปิด (นาที) 0 = ปิดทันที

input group "🔒 การกันทุน และ การไล่ SL ตามแท่งเทียน"
input int      InpBreakEvenTrigger = 60;       // กำไรถึงกี่จุด จึงเลื่อนมากันทุน (จุด)
input int      InpBreakEvenOffset  = 30;       // กันทุนแล้วล็อกกำไรขั้นต่ำ (จุด)
input int      InpProfitLockGap    = 100;      // ไล่ SL ตามราคาสด ห่างเท่าไร (จุด)
input int      InpTrailBufferPts   = 50;       // ไล่ SL ตามแท่งเทียน เผื่อห่าง (จุด)
input int      InpSpreadCompPts    = 0;        // บัฟเฟอร์เสริมตอนไล่ SL (ใส่เท่ากันทั้ง 2 ฝั่ง) 0 = ปิด

input group "💰 การคำนวณขนาดล็อต"
input bool     InpUseAutoLot       = true;     // เปิด = คำนวณล็อตจากยอดเงินอัตโนมัติ
input double   InpRiskPercent      = 5.0;      // ความเสี่ยงต่อไม้ (% ของยอดเงิน)
input double   InpFixedLot         = 0.01;     // ล็อตคงที่ (ใช้เมื่อปิดโหมดอัตโนมัติ)
input double   InpMaxLot           = 0.50;     // เพดานล็อตสูงสุดต่อไม้ (0 = ใช้เพดานของโบรก) กันล็อตบานจากการทบต้น

input group "🛡 ตัวกรองความปลอดภัย"
input int      InpMaxSpread        = 50;       // สเปรดกว้างเกินนี้ ไม่วางออเดอร์ (จุด)
input int      InpSlippage         = 30;       // ค่าคลาดเคลื่อนราคาที่ยอมรับ (จุด)
input int      InpMaxRetries       = 3;        // จำนวนครั้งที่ลองส่งคำสั่งซ้ำ
input string   InpComment          = "XAU_TH_v3"; // ข้อความกำกับออเดอร์

input group "🚨 เพดานกำไร-ขาดทุนรายวัน (ค่าเริ่มต้นปิดทั้งหมด = รันไม่หยุด 24 ชม.)"
input bool     InpUseDailyLossStop  = false;   // ปิดไว้ = ขาดทุนหนักแค่ไหนก็เทรดต่อ ไม่หยุดพัก
input double   InpDailyLossPct      = 5.0;     // เพดานขาดทุนต่อวัน (% ของยอดเงิน)
input bool     InpUseDailyProfitStop= false;   // เปิด = กำไรถึงเป้า เก็บกำไรหยุดเทรด
input double   InpDailyProfitPct    = 5.0;     // เป้ากำไรต่อวัน (% ของยอดเงิน)

input group "🖥 หน้าจอแดชบอร์ด"
input bool     InpShowDashboard    = true;     // แสดงแดชบอร์ดบนกราฟ
input bool     InpShowRobot        = true;     // แสดงหุ่นยนต์โยนเงิน (แอนิเมชัน)
input bool     InpCompactMode      = false;    // เปิด = โหมดย่อ (ซ่อนหุ่นยนต์และกราฟย่อ)
input int      InpPanelX           = 12;       // ตำแหน่งแผงจากขอบซ้าย (พิกเซล)
input int      InpPanelY           = 28;       // ตำแหน่งแผงจากขอบบน (พิกเซล)

//====================================================================
//                    ตัวแปรสถานะภายในของอีเอ
//====================================================================
enum ENUM_EA_STATE
{
   STATE_IDLE,             // ว่าง ยังไม่มีอะไรในตลาด
   STATE_PENDING_PLACED,   // วางกับดัก 2 ข้างแล้ว รอราคาชน
   STATE_POSITION_OPEN,    // ออเดอร์เปิดแล้ว ยังไม่ถึงจุดกันทุน
   STATE_BREAKEVEN_SET,    // เลื่อน SL มากันทุนเรียบร้อย
   STATE_TRAILING_ACTIVE   // กำลังไล่ SL ตามแท่งเทียน
};

CTrade         trade;
ENUM_EA_STATE  g_state          = STATE_IDLE;
datetime       g_lastCandleTime = 0;      // แท่งเทียนล่าสุดที่ไล่ SL ไปแล้ว
datetime       g_haltDay        = 0;      // วันที่ถูกสั่งหยุดเทรด (เที่ยงคืนไทย)
string         g_haltReason     = "";     // เหตุผลที่หยุดเทรด

//--- สถิติผลงานของวันนี้ (คำนวณจากประวัติการเทรดจริง)
double         g_dayProfit   = 0;   // รวมเฉพาะไม้ที่กำไร (บวก)
double         g_dayLoss     = 0;   // รวมเฉพาะไม้ที่ขาดทุน (ค่าติดลบ)
double         g_dayNet      = 0;   // สุทธิของวัน
int            g_dayWins     = 0;   // จำนวนไม้ชนะ
int            g_dayLosses   = 0;   // จำนวนไม้แพ้
double         g_dayBest     = 0;   // ไม้ที่กำไรสูงสุดของวัน
double         g_dayWorst    = 0;   // ไม้ที่ขาดทุนหนักสุดของวัน
double         g_accountNet  = 0;   // สุทธิของวันทั้งบัญชี (ทุกอีเอ ทุกคู่เงิน)
double         g_lastPL[12];        // ผลไม้ล่าสุด 12 ไม้ (ไว้วาดกราฟย่อ)
int            g_lastCount   = 0;
datetime       g_lastStatCalc= 0;   // เวลาที่คำนวณสถิติครั้งล่าสุด

//--- ตัวปรับสเกลจุดอัตโนมัติ (สำคัญมาก)
//    โบรกบางเจ้าใช้ทศนิยม 3 ตำแหน่ง (เช่น XAUUSDm ของ Exness = 4050.054)
//    ทำให้ 1 จุดของโบรก = 0.001 ไม่ใช่ 0.01 ค่าทุกอย่างจะเพี้ยนไป 10 เท่า
//    ระบบจะตรวจเองแล้วปรับให้ "จุด" ที่กรอกในอินพุตหมายถึง 0.01 เสมอ
int            g_mult        = 1;   // ตัวคูณ: 10 เมื่อโบรกใช้ 3 หรือ 5 ทศนิยม
double         g_pt          = 0;   // ขนาด 1 จุดมาตรฐาน (0.01 สำหรับทองคำ)

//--- ตัวแปรสำหรับแอนิเมชัน
int            g_frame       = 0;   // เฟรมแอนิเมชัน เพิ่มขึ้นทุก 100 มิลลิวินาที
int            g_panelH      = 500; // ความสูงแผง (ปรับอัตโนมัติ)

//+------------------------------------------------------------------+
//| เริ่มต้นการทำงานของอีเอ                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage * ((_Digits == 3 || _Digits == 5) ? 10 : 1));
   trade.SetTypeFillingBySymbol(_Symbol);

   //--- ตรวจทศนิยมของโบรก แล้วปรับสเกลจุดให้อัตโนมัติ
   g_mult = (_Digits == 3 || _Digits == 5) ? 10 : 1;
   g_pt   = _Point * g_mult;
   PrintFormat("ตรวจพบสัญลักษณ์ %s ทศนิยม %d ตำแหน่ง | 1 จุดในอินพุต = %.5f (ตัวคูณ ×%d)",
               _Symbol, _Digits, g_pt, g_mult);
   if(g_mult == 10)
      Print("ℹ โบรกนี้ใช้ 3 ทศนิยม ระบบปรับสเกลให้แล้ว SL 250 จุด = ราคาขยับ 2.50$ ตามปกติ");

   ArrayInitialize(g_lastPL, 0);

   //--- กู้สถานะกลับมาหลังปิด-เปิดโปรแกรมใหม่
   RecoverState();
   RefreshDayStats(true);
   UpdateDashboard();

   //--- ตั้งจับเวลา 100 มิลลิวินาที ไว้ขยับแอนิเมชันและเฝ้าเวลาปิดรอบ
   EventSetMillisecondTimer(100);

   Print("═══ เริ่มทำงาน: อีเอสแตรดเดิลทองคำ v3.0 (ไทย) ═══");
   Print("สถานะเริ่มต้น = ", StateToThai(g_state));
   Print("⚠ ระบบความเสี่ยงสูง กรุณาทดสอบใน Demo ก่อนเสมอ");

   //--- เตือนค่าความเสี่ยงที่อันตราย ตอนที่ยังแก้ทัน
   PrintFormat("ล็อตที่จะเปิดไม้แรก = %.2f (เพดานที่ตั้งไว้ %.2f)",
               CalcLot(), InpMaxLot);
   if(InpUseAutoLot && InpRiskPercent > 2.0)
      PrintFormat("⚠ ความเสี่ยงต่อไม้ %.1f%% สูงมาก | โดนติดกัน %d ไม้ = เสียครึ่งพอร์ต "
                  "| แนะนำ 0.5-1.0%% (เพดานล็อต %.2f ช่วยจำกัดไว้ให้ระดับหนึ่งแล้ว)",
                  InpRiskPercent, (int)MathCeil(50.0/InpRiskPercent), InpMaxLot);
   if(!InpUseDailyLossStop)
      Print("⚠ ไม่ได้เปิดเพดานขาดทุนรายวัน (InpUseDailyLossStop) "
            "-> วันที่แย่จริงๆ จะไม่มีอะไรหยุดการเทรดเลย");
   if(!InpUseTimeFilter)
      Print("ℹ ปิด Time Filter อยู่ = เทรด 24 ชม. รวมช่วงสภาพคล่องต่ำและช่วง rollover ที่สเปรดกาง");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| ปิดการทำงานของอีเอ                                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteDashboard();
   Comment("");
   Print("หยุดทำงาน รหัสเหตุผล = ", reason);
}

//+------------------------------------------------------------------+
//| ทำงานทุกครั้งที่ราคาขยับ                                          |
//+------------------------------------------------------------------+
void OnTick()
{
   RefreshDayStats(false);
   TradingCore();
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| ทำงานทุก 100 มิลลิวินาที (แอนิเมชัน + เฝ้าเวลาปิดรอบ)              |
//| จำเป็นเพราะบางช่วงราคาอาจไม่ขยับเลย แต่เวลาเทรดหมดแล้ว              |
//+------------------------------------------------------------------+
void OnTimer()
{
   g_frame++;
   RefreshDayStats(false);
   SessionEndGuard();      // ยามเฝ้าเวลา: หมดเวลาแล้วปิดให้แน่นอน
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| มีดีลใหม่เข้ามา -> บังคับคำนวณสถิติใหม่ทันที                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      g_lastStatCalc = 0;   // ล้างแคช ให้คำนวณใหม่รอบหน้า
}

//====================================================================
//                      สมองหลักของระบบเทรด
//====================================================================
void TradingCore()
{
   if(!IsTradingAllowed()) return;

   int  pendings = CountMyPendings();
   bool hasPos   = HasMyPosition();

   //--- OCO: ถ้ามีออเดอร์เปิดแล้ว แต่ยังเหลือกับดักอีกข้าง ให้ลบทิ้ง
   if(hasPos && pendings > 0)
   {
      DeleteAllMyPendings();
      pendings = 0;
   }

   //=== ด่านที่ 1: เพดานกำไร-ขาดทุนรายวัน ===========================
   CheckDailyLimits();
   if(IsHaltedToday())
   {
      if(pendings > 0) DeleteAllMyPendings();
      if(hasPos)       CloseMyPosition("ถึงเพดานรายวัน: " + g_haltReason);
      g_state = STATE_IDLE;
      return;
   }

   //=== ด่านที่ 2: ช่วงเวลาเทรด =====================================
   if(InpUseTimeFilter && !InSession())
   {
      //--- หมดเวลาแล้ว: ไม่มีการวางออเดอร์ใหม่เด็ดขาด
      if(pendings > 0) DeleteAllMyPendings();

      if(hasPos)
      {
         if(InpCloseOnSessionEnd && !InGracePeriod())
         {
            CloseMyPosition("หมดเวลาเทรดตามรอบ");
         }
         else
         {
            //--- ยังอยู่ในช่วงผ่อนผัน (หรือปิดฟีเจอร์นี้) → ดูแลไม้ต่อไป
            ManagePosition();
            return;
         }
      }
      g_state = STATE_IDLE;
      return;
   }

   //=== ด่านที่ 3: มีออเดอร์เปิดอยู่ → ดูแลไม้ =======================
   if(hasPos)
   {
      if(g_state == STATE_IDLE || g_state == STATE_PENDING_PLACED)
      {
         g_state = STATE_POSITION_OPEN;
         g_lastCandleTime = iTime(_Symbol, PERIOD_CURRENT, 0);
      }
      ManagePosition();
      return;
   }

   //=== ด่านที่ 4: ไม่มีออเดอร์ → วางกับดักใหม่ (วงจรวนไม่รู้จบ) ======
   if(pendings >= 2)
   {
      g_state = STATE_PENDING_PLACED;   // กับดักครบคู่แล้ว รอราคาชน
      return;
   }
   if(pendings == 1) DeleteAllMyPendings();   // เหลือข้างเดียว ลบทิ้งแล้ววางใหม่

   g_state = STATE_IDLE;
   PlaceStraddle();
}

//+------------------------------------------------------------------+
//| ยามเฝ้าเวลา: เรียกจากตัวจับเวลา ไม่ต้องรอราคาขยับ                  |
//+------------------------------------------------------------------+
void SessionEndGuard()
{
   if(!InpUseTimeFilter || !InpCloseOnSessionEnd) return;
   if(!IsTradingAllowed()) return;
   if(InSession() || InGracePeriod()) return;

   if(CountMyPendings() > 0) DeleteAllMyPendings();
   if(HasMyPosition())
   {
      CloseMyPosition("หมดเวลาเทรดตามรอบ");
      g_state = STATE_IDLE;
   }
}

//====================================================================
//                    ระบบเวลาไทย และช่วงเทรด
//====================================================================

//--- แปลงข้อความ "07:30" เป็นจำนวนนาทีนับจากเที่ยงคืน
int ParseHHMM(const string s)
{
   string parts[];
   if(StringSplit(s, ':', parts) != 2) return(-1);
   return((int)StringToInteger(parts[0]) * 60 + (int)StringToInteger(parts[1]));
}

//--- เวลาปัจจุบันของประเทศไทย คิดเป็นนาทีนับจากเที่ยงคืน
int ThaiMinutesNow()
{
   datetime thai = TimeGMT() + 7 * 3600;   // ไทย = GMT+7 ไม่มีปรับเวลาตามฤดูกาล
   MqlDateTime dt;
   TimeToStruct(thai, dt);
   return(dt.hour * 60 + dt.min);
}

//--- เช็กว่านาที now อยู่ในช่วง s ถึง e หรือไม่ (รองรับช่วงที่ข้ามเที่ยงคืน)
bool InRange(const int now, const int s, const int e)
{
   if(s < 0 || e < 0) return(false);
   if(s <= e) return(now >= s && now < e);
   return(now >= s || now < e);          // เช่น 22:00-01:00
}

//--- อยู่ในช่วงเวลาเทรดหรือไม่
bool InSession()
{
   int now = ThaiMinutesNow();
   if(InRange(now, ParseHHMM(InpSession1Start), ParseHHMM(InpSession1End))) return(true);
   if(InRange(now, ParseHHMM(InpSession2Start), ParseHHMM(InpSession2End))) return(true);
   if(InRange(now, ParseHHMM(InpSession3Start), ParseHHMM(InpSession3End))) return(true);
   return(false);
}

//--- อยู่ในช่วงผ่อนผันหลังหมดเวลาหรือไม่
bool InGracePeriod()
{
   if(InpGraceMinutes <= 0) return(false);
   int now = ThaiMinutesNow();
   int e1 = ParseHHMM(InpSession1End), e2 = ParseHHMM(InpSession2End), e3 = ParseHHMM(InpSession3End);
   if(e1 >= 0 && InRange(now, e1, (e1 + InpGraceMinutes) % 1440)) return(true);
   if(e2 >= 0 && InRange(now, e2, (e2 + InpGraceMinutes) % 1440)) return(true);
   if(e3 >= 0 && InRange(now, e3, (e3 + InpGraceMinutes) % 1440)) return(true);
   return(false);
}

//--- เหลืออีกกี่นาทีจะหมดรอบเทรดปัจจุบัน (ถ้าไม่ได้อยู่ในรอบ คืน -1)
int MinutesToSessionEnd()
{
   int now = ThaiMinutesNow();
   int s[3], e[3];
   s[0] = ParseHHMM(InpSession1Start); e[0] = ParseHHMM(InpSession1End);
   s[1] = ParseHHMM(InpSession2Start); e[1] = ParseHHMM(InpSession2End);
   s[2] = ParseHHMM(InpSession3Start); e[2] = ParseHHMM(InpSession3End);
   for(int i = 0; i < 3; i++)
      if(InRange(now, s[i], e[i]))
         return((e[i] - now + 1440) % 1440);
   return(-1);
}

//--- อีกกี่นาทีจะถึงรอบเทรดถัดไป
int MinutesToNextSession()
{
   int now = ThaiMinutesNow();
   int best = 99999;
   int s[3];
   s[0] = ParseHHMM(InpSession1Start);
   s[1] = ParseHHMM(InpSession2Start);
   s[2] = ParseHHMM(InpSession3Start);
   for(int i = 0; i < 3; i++)
   {
      if(s[i] < 0) continue;
      int d = (s[i] - now + 1440) % 1440;
      if(d < best) best = d;
   }
   return(best == 99999 ? -1 : best);
}

//--- เที่ยงคืนของวันนี้ตามเวลาไทย แปลงเป็นเวลาเซิร์ฟเวอร์โบรกเกอร์
datetime ThaiDayStartServer()
{
   datetime gmt      = TimeGMT();
   long     thaiSec  = (long)(gmt + 7 * 3600);
   long     secToday = thaiSec % 86400;
   datetime startGMT = (datetime)((long)gmt - secToday);
   long     offset   = (long)TimeCurrent() - (long)gmt;   // ส่วนต่างเวลาโบรกกับ GMT
   return((datetime)((long)startGMT + offset));
}

//====================================================================
//                 สถิติกำไร-ขาดทุนของวันนี้
//====================================================================
void RefreshDayStats(const bool force)
{
   //--- คำนวณใหม่ทุก 2 วินาที เพื่อไม่ให้กินซีพียู
   if(!force && g_lastStatCalc > 0 && TimeCurrent() - g_lastStatCalc < 2) return;
   g_lastStatCalc = TimeCurrent();

   datetime from = ThaiDayStartServer();
   if(!HistorySelect(from, TimeCurrent() + 3600)) return;

   g_dayProfit = 0; g_dayLoss = 0; g_dayNet = 0;
   g_dayWins = 0;   g_dayLosses = 0;
   g_dayBest = 0;   g_dayWorst = 0;
   g_accountNet = 0;
   g_lastCount = 0;
   ArrayInitialize(g_lastPL, 0);

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY)
         continue;                                  // นับเฉพาะดีลที่ "ปิด" ไม้

      double pl = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                + HistoryDealGetDouble(ticket, DEAL_SWAP)
                + HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      g_accountNet += pl;                           // ยอดรวมทั้งบัญชี

      //--- กรองเฉพาะไม้ของอีเอตัวนี้ บนคู่เงินนี้
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)        continue;

      g_dayNet += pl;
      if(pl >= 0) { g_dayProfit += pl; g_dayWins++;   if(pl > g_dayBest)  g_dayBest  = pl; }
      else        { g_dayLoss   += pl; g_dayLosses++; if(pl < g_dayWorst) g_dayWorst = pl; }

      //--- เก็บผล 12 ไม้ล่าสุดไว้วาดกราฟย่อ (เลื่อนซ้ายทีละช่อง)
      if(g_lastCount < 12) g_lastPL[g_lastCount++] = pl;
      else
      {
         for(int k = 0; k < 11; k++) g_lastPL[k] = g_lastPL[k + 1];
         g_lastPL[11] = pl;
      }
   }
}

//--- กำไรลอยของไม้ที่เปิดอยู่ตอนนี้
double FloatingPL()
{
   double sum = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         sum += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return(sum);
}

//====================================================================
//               เพดานกำไร-ขาดทุนรายวัน (หยุดเทรดถึงเที่ยงคืน)
//====================================================================
bool IsHaltedToday()
{
   return(g_haltDay != 0 && g_haltDay == ThaiDayStartServer());
}

void CheckDailyLimits()
{
   if(IsHaltedToday()) return;

   double bal   = AccountInfoDouble(ACCOUNT_BALANCE);
   double today = g_dayNet + FloatingPL();     // นับรวมกำไรลอยด้วย

   if(InpUseDailyLossStop)
   {
      double maxLoss = bal * InpDailyLossPct / 100.0;
      if(today <= -maxLoss)
      {
         g_haltDay    = ThaiDayStartServer();
         g_haltReason = StringFormat("ขาดทุน %.2f$ ถึงเพดาน %.1f%%", today, InpDailyLossPct);
         PrintFormat("🛑 หยุดเทรดถึงเที่ยงคืน: %s", g_haltReason);
      }
   }
   if(!IsHaltedToday() && InpUseDailyProfitStop)
   {
      double target = bal * InpDailyProfitPct / 100.0;
      if(today >= target)
      {
         g_haltDay    = ThaiDayStartServer();
         g_haltReason = StringFormat("กำไร %.2f$ ถึงเป้า %.1f%%", today, InpDailyProfitPct);
         PrintFormat("🏆 เก็บกำไร หยุดเทรดถึงเที่ยงคืน: %s", g_haltReason);
      }
   }
}

//====================================================================
//                       วางกับดักสองข้าง
//====================================================================
void PlaceStraddle()
{
   //--- กฎเหล็ก: ห้ามมีเกิน 1 ไม้เด็ดขาด และห้ามวางซ้อนกับดักเดิม
   if(HasMyPosition())        return;
   if(CountMyPendings() > 0)  return;

   //--- สเปรดกว้างเกินไป ไม่วางออเดอร์
   long spread = SpreadPts();          // แปลงเป็นจุดมาตรฐานก่อนเทียบ
   if(spread > InpMaxSpread) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pt  = g_pt;

   //--- เคารพระยะขั้นต่ำที่โบรกเกอร์กำหนด
   double minStop  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;  // ค่านี้เป็นจุดดิบของโบรก
   double distBuy  = MathMax(InpBuyStopDistance  * pt, minStop + pt);
   double distSell = MathMax(InpSellStopDistance * pt, minStop + pt);

   double buyPrice  = NormalizeDouble(ask + distBuy,  _Digits);
   double sellPrice = NormalizeDouble(bid - distSell, _Digits);

   double buySL  = NormalizeDouble(buyPrice  - InpStopLoss   * pt, _Digits);
   double sellSL = NormalizeDouble(sellPrice + InpStopLoss   * pt, _Digits);
   //--- TP = 0 แปลว่าไม่ตั้งเป้า ปล่อยให้ระบบไล่ SL เป็นคนพาออก
   double buyTP  = (InpTakeProfit > 0) ? NormalizeDouble(buyPrice  + InpTakeProfit * pt, _Digits) : 0.0;
   double sellTP = (InpTakeProfit > 0) ? NormalizeDouble(sellPrice - InpTakeProfit * pt, _Digits) : 0.0;

   double lot = CalcLot();
   if(lot <= 0)        { Print("คำนวณล็อตไม่สำเร็จ"); return; }
   if(!CheckMargin(lot)){ Print("มาร์จิ้นไม่พอสำหรับล็อต ", lot); return; }

   bool okBuy = false, okSell = false;
   for(int i = 0; i < InpMaxRetries && !okBuy; i++)
   {
      okBuy = trade.BuyStop(lot, buyPrice, _Symbol, buySL, buyTP, ORDER_TIME_GTC, 0, InpComment);
      if(!okBuy) { PrintFormat("วาง Buy Stop ไม่สำเร็จ (%d): %s",
                   trade.ResultRetcode(), trade.ResultRetcodeDescription()); Sleep(300); }
   }
   for(int i = 0; i < InpMaxRetries && !okSell; i++)
   {
      okSell = trade.SellStop(lot, sellPrice, _Symbol, sellSL, sellTP, ORDER_TIME_GTC, 0, InpComment);
      if(!okSell){ PrintFormat("วาง Sell Stop ไม่สำเร็จ (%d): %s",
                   trade.ResultRetcode(), trade.ResultRetcodeDescription()); Sleep(300); }
   }

   //--- ต้องได้ครบคู่เท่านั้น ถ้าได้ข้างเดียวให้ลบทิ้ง
   if(okBuy != okSell)
   {
      Print("วางกับดักได้ไม่ครบคู่ → ลบทิ้งแล้วเริ่มใหม่");
      DeleteAllMyPendings();
      return;
   }
   if(okBuy && okSell)
   {
      g_state = STATE_PENDING_PLACED;
      PrintFormat("✅ วางกับดักสำเร็จ ล็อต=%.2f | BuyStop=%.2f | SellStop=%.2f",
                  lot, buyPrice, sellPrice);
   }
}

//====================================================================
//        ดูแลไม้ที่เปิดอยู่: กันทุน → ล็อกกำไร → ไล่ตามแท่งเทียน
//====================================================================
void ManagePosition()
{
   if(!PositionSelectByMagic()) return;

   long   type  = PositionGetInteger(POSITION_TYPE);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double tp    = PositionGetDouble(POSITION_TP);
   double pt    = g_pt;
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double profitPts = (type == POSITION_TYPE_BUY) ? (bid - entry) / pt
                                                  : (entry - ask) / pt;

   //=== Time-Stop: เปิดมานานแล้วยังไม่ไปไหน → ปิดทิ้งตั้งแต่ยังไม่แพง ===
   if(InpTimeStopMinutes > 0)
   {
      datetime opened  = (datetime)PositionGetInteger(POSITION_TIME);
      int      minsOld = (int)((TimeCurrent() - opened) / 60);
      if(minsOld >= InpTimeStopMinutes && profitPts < InpTimeStopMinPts)
      {
         CloseMyPosition(StringFormat("Time-Stop: %d นาทีแล้วได้แค่ %.0f จุด", minsOld, profitPts));
         g_state = STATE_IDLE;
         return;
      }
   }

   //--- ระดับกันทุน = ราคาเข้า ± ระยะล็อกกำไรขั้นต่ำ
   double bePrice = (type == POSITION_TYPE_BUY)
                  ? NormalizeDouble(entry + InpBreakEvenOffset * pt, _Digits)
                  : NormalizeDouble(entry - InpBreakEvenOffset * pt, _Digits);

   //=== ขั้นที่ 1: เลื่อน SL มากันทุน (พยายามทุกทิกจนกว่าจะสำเร็จ) ====
   if(profitPts >= InpBreakEvenTrigger)
   {
      double minStopBE = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;  // ค่านี้เป็นจุดดิบของโบรก

      bool needMove = (type == POSITION_TYPE_BUY) ? (sl < bePrice) : (sl > bePrice || sl == 0);
      bool brokerOK = (type == POSITION_TYPE_BUY) ? (bePrice < bid - minStopBE)
                                                  : (bePrice > ask + minStopBE);
      if(needMove && brokerOK)
      {
         if(trade.PositionModify(_Symbol, bePrice, tp))
         {
            sl = bePrice;
            if(g_state == STATE_POSITION_OPEN) g_state = STATE_BREAKEVEN_SET;
            PrintFormat("🔒 กันทุนแล้วที่ %.2f (กำไร %.0f จุด)", bePrice, profitPts);
         }
      }
      else if(!needMove && g_state == STATE_POSITION_OPEN)
         g_state = STATE_BREAKEVEN_SET;

      //=== ขั้นที่ 2: ล็อกกำไรตามราคาสด (ทำทุกทิก ไม่ต่ำกว่าจุดกันทุน) ===
      //--- ไม้ซื้อปิดที่ Bid ไม้ขายปิดที่ Ask ซึ่ง "รวมสเปรดอยู่ในตัวแล้ว"
      //    เดิมฝั่งขายบวกค่าชดเชยสเปรดเข้าไปอีก = นับซ้ำ ทำให้ไม้ขายถูกไล่หลวมกว่า
      //    ไม้ซื้อราว 30 จุดโดยไม่ตั้งใจ ตอนนี้วัดจากราคาปิดของแต่ละฝั่งเท่ากัน
      double gapPts = InpProfitLockGap + InpSpreadCompPts;
      double lockSL;
      if(type == POSITION_TYPE_BUY)
      {
         lockSL = NormalizeDouble(bid - gapPts * pt, _Digits);
         if(lockSL < bePrice) lockSL = bePrice;
         if(g_state != STATE_POSITION_OPEN && lockSL > sl)
            if(trade.PositionModify(_Symbol, lockSL, tp)) sl = lockSL;
      }
      else
      {
         lockSL = NormalizeDouble(ask + gapPts * pt, _Digits);
         if(lockSL > bePrice) lockSL = bePrice;
         if(g_state != STATE_POSITION_OPEN && (lockSL < sl || sl == 0))
            if(trade.PositionModify(_Symbol, lockSL, tp)) sl = lockSL;
      }
   }

   //=== ขั้นที่ 3: ไล่ SL ตามแท่งเทียน (ทำครั้งเดียวต่อแท่ง) ==========
   datetime curCandle = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(curCandle == g_lastCandleTime) return;
   g_lastCandleTime = curCandle;

   //--- ก่อนกันทุน SL ยังคงอยู่ที่ -250 จุดตายตัว ไม่ขยับ
   if(g_state != STATE_BREAKEVEN_SET && g_state != STATE_TRAILING_ACTIVE) return;
   g_state = STATE_TRAILING_ACTIVE;

   //--- แท่งเทียนของ MT5 อ้างอิงราคา Bid แต่ไม้ขายถูกปิดที่ Ask
   //    จึงต้องบวก "สเปรดจริง ณ ตอนนี้" เพื่อแปลงระดับ Bid ให้เทียบกับ Ask ได้ถูกต้อง
   //    (ไม่ใช่บวกค่าคงที่ทับลงไปอีก ซึ่งเป็นที่มาของความไม่สมมาตรเดิม)
   double spreadNowPts = (ask - bid) / pt;
   double minStop    = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;  // ค่านี้เป็นจุดดิบของโบรก
   double newSL;

   if(type == POSITION_TYPE_BUY)
   {
      //--- ฝั่งซื้อปิดที่ราคา Bid จึงไม่ต้องเผื่อสเปรด
      newSL = NormalizeDouble(iLow(_Symbol, PERIOD_CURRENT, 1)
                              - (InpTrailBufferPts + InpSpreadCompPts) * pt, _Digits);
      if(newSL < bePrice) newSL = bePrice;              // ห้ามต่ำกว่าจุดกันทุน
      if(newSL > sl && newSL < bid - minStop)           // เลื่อนไปข้างหน้าเท่านั้น
      {
         for(int r = 0; r < InpMaxRetries; r++)
         {
            if(trade.PositionModify(_Symbol, newSL, tp))
            {
               PrintFormat("🚀 ไล่ SL ฝั่งซื้อ → %.2f", newSL);
               break;
            }
            Sleep(200);
         }
      }
   }
   else
   {
      //--- ฝั่งขายปิดที่ราคา Ask จึงต้องเผื่อสเปรดกันโดนเขี่ย
      newSL = NormalizeDouble(iHigh(_Symbol, PERIOD_CURRENT, 1)
                              + (InpTrailBufferPts + InpSpreadCompPts + spreadNowPts) * pt, _Digits);
      if(newSL > bePrice) newSL = bePrice;
      if((newSL < sl || sl == 0) && newSL > ask + minStop)
      {
         for(int r = 0; r < InpMaxRetries; r++)
         {
            if(trade.PositionModify(_Symbol, newSL, tp))
            {
               PrintFormat("🚀 ไล่ SL ฝั่งขาย → %.2f", newSL);
               break;
            }
            Sleep(200);
         }
      }
   }
}

//====================================================================
//                        ฟังก์ชันช่วยเหลือ
//====================================================================

//--- สเปรดปัจจุบัน แปลงเป็น "จุดมาตรฐาน" (0.01) แล้ว
long SpreadPts()
{
   return(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) / g_mult);
}

//--- คำนวณขนาดล็อต (จากความเสี่ยง % เทียบกับระยะ SL)
double CalcLot()
{
   double lot;
   if(!InpUseAutoLot)
      lot = InpFixedLot;
   else
   {
      double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney = balance * InpRiskPercent / 100.0;
      double tickVal   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickVal <= 0 || tickSize <= 0) return(0);

      double lossPerLot = (InpStopLoss * g_pt / tickSize) * tickVal;
      if(lossPerLot <= 0) return(0);
      lot = riskMoney / lossPerLot;
   }

   //--- ปัดให้ตรงกับข้อกำหนดของโบรกเกอร์
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0) stepLot = 0.01;

   //--- เพดานของผู้ใช้ต้องมาก่อนเพดานของโบรก ไม่งั้นพอร์ตโตแล้วล็อตจะบานจนอันตราย
   double cap = (InpMaxLot > 0) ? MathMin(InpMaxLot, maxLot) : maxLot;

   lot = MathFloor(lot / stepLot) * stepLot;
   lot = MathMax(minLot, MathMin(cap, lot));
   return(NormalizeDouble(lot, 2));
}

//--- เช็กว่ามาร์จิ้นพอไหม (เผื่อความปลอดภัย 1.5 เท่า)
bool CheckMargin(const double lot)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double marginNeeded;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, ask, marginNeeded)) return(false);
   return(AccountInfoDouble(ACCOUNT_MARGIN_FREE) > marginNeeded * 1.5);
}

//--- เทรดได้หรือไม่ (เช็กปุ่ม AutoTrading และสถานะคู่เงิน)
bool IsTradingAllowed()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return(false);
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))           return(false);
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL) return(false);
   return(true);
}

//--- นับกับดักที่ยังรออยู่
int CountMyPendings()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) == InpMagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol) count++;
   }
   return(count);
}

//--- มีออเดอร์เปิดอยู่ไหม
bool HasMyPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol) return(true);
   }
   return(false);
}

//--- เลือกออเดอร์ของอีเอตัวนี้
bool PositionSelectByMagic()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol) return(true);
   }
   return(false);
}

//--- ลบกับดักทั้งหมดของอีเอตัวนี้
void DeleteAllMyPendings()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) == InpMagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol)
      {
         for(int r = 0; r < InpMaxRetries; r++)
            if(trade.OrderDelete(ticket)) break; else Sleep(200);
      }
   }
}

//--- ปิดออเดอร์ของอีเอตัวนี้ทั้งหมด พร้อมเหตุผล
void CloseMyPosition(const string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber ||
         PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double pl = PositionGetDouble(POSITION_PROFIT);
      for(int r = 0; r < InpMaxRetries; r++)
      {
         if(trade.PositionClose(ticket))
         {
            PrintFormat("⛔ ปิดออเดอร์ #%I64u (%.2f$) เหตุผล: %s", ticket, pl, reason);
            break;
         }
         PrintFormat("ปิดออเดอร์ไม่สำเร็จ (%d): %s",
                     trade.ResultRetcode(), trade.ResultRetcodeDescription());
         Sleep(200);
      }
   }
   g_lastStatCalc = 0;   // ให้คำนวณสถิติใหม่ทันที
}

//--- กู้สถานะหลังเปิดโปรแกรมใหม่
void RecoverState()
{
   if(HasMyPosition() && PositionSelectByMagic())
   {
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      long   type  = PositionGetInteger(POSITION_TYPE);
      bool   beDone= (type == POSITION_TYPE_BUY) ? (sl >= entry && sl > 0)
                                                 : (sl <= entry && sl > 0);
      g_state = beDone ? STATE_BREAKEVEN_SET : STATE_POSITION_OPEN;
      g_lastCandleTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   }
   else if(CountMyPendings() >= 2) g_state = STATE_PENDING_PLACED;
   else                            g_state = STATE_IDLE;
}

//--- แปลงสถานะเป็นข้อความไทย
string StateToThai(const ENUM_EA_STATE s)
{
   switch(s)
   {
      case STATE_PENDING_PLACED:  return("รอราคาชนกับดัก");
      case STATE_POSITION_OPEN:   return("ออเดอร์เปิดอยู่");
      case STATE_BREAKEVEN_SET:   return("กันทุนแล้ว");
      case STATE_TRAILING_ACTIVE: return("กำลังไล่กำไร");
   }
   return("ว่าง รอจังหวะ");
}

//====================================================================
//        ตัววัดผลตอนทดสอบย้อนหลัง (Strategy Tester)
//  ใช้ "ค่าคาดหวังต่อไม้" แทนกำไรรวม เพราะกำไรรวมโกหกได้ด้วยจำนวนไม้
//  วิธีใช้: ในหน้า Settings ของ Tester เลือก Optimization criterion
//           = "Custom max" ระบบจะใช้คะแนนจากฟังก์ชันนี้จัดอันดับให้
//====================================================================
double OnTester()
{
   if(!HistorySelect(0, TimeCurrent() + 3600)) return(0.0);

   int    trades = 0, wins = 0, losses = 0;
   int    consecLoss = 0, maxConsecLoss = 0;
   double sumWin = 0, sumLoss = 0, sumWinPts = 0, sumLossPts = 0;
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;

      double pl  = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket, DEAL_SWAP)
                 + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double vol = HistoryDealGetDouble(ticket, DEAL_VOLUME);

      //--- แปลงกำไรเป็น "จุด" เพื่อเทียบกันได้แม้ล็อตจะต่างกัน
      double pts = (vol > 0 && tickVal > 0) ? pl / (vol * tickVal) / g_mult : 0;

      trades++;
      if(pl >= 0) { wins++;  sumWin  += pl;           sumWinPts  += pts;           consecLoss = 0; }
      else        { losses++; sumLoss += MathAbs(pl); sumLossPts += MathAbs(pts);  consecLoss++;
                    if(consecLoss > maxConsecLoss) maxConsecLoss = consecLoss; }
   }
   if(trades < 30) return(0.0);   // ไม้น้อยเกินไป ไม่มีความหมายทางสถิติ

   double avgWin    = (wins   > 0) ? sumWin  / wins   : 0;
   double avgLoss   = (losses > 0) ? sumLoss / losses : 0;
   double avgWinP   = (wins   > 0) ? sumWinPts  / wins   : 0;
   double avgLossP  = (losses > 0) ? sumLossPts / losses : 0;
   double winRate   = (double)wins / trades;
   double payoff    = (avgLoss > 0) ? avgWin / avgLoss : 0;
   double profFact  = (sumLoss > 0) ? sumWin / sumLoss : 0;
   double expectPts = winRate * avgWinP - (1.0 - winRate) * avgLossP;
   double expectUSD = (sumWin - sumLoss) / trades;
   double ddPct     = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);

   //--- คะแนน = ค่าคาดหวังต่อไม้ × √จำนวนไม้ ÷ โทษจาก Drawdown
   double score = expectPts * MathSqrt((double)trades) / (1.0 + ddPct / 20.0);
   if(payoff < 0.35)      score *= 0.5;   // ไม้แพ้ใหญ่กว่าไม้ชนะเกิน 3 เท่า = เปราะบาง
   if(maxConsecLoss > 15) score *= 0.5;   // แพ้ติดกันเกิน 15 ไม้ = พอร์ตอาจไม่รอด

   Print("╔═════════ สรุปผลทดสอบ (ภาษาไทย) ═════════");
   PrintFormat("║ จำนวนไม้ทั้งหมด    : %d ไม้ (ชนะ %d / แพ้ %d)", trades, wins, losses);
   PrintFormat("║ อัตราชนะ          : %.1f%%", winRate * 100);
   PrintFormat("║ ไม้ชนะเฉลี่ย       : %.2f$  (%.0f จุด)", avgWin, avgWinP);
   PrintFormat("║ ไม้แพ้เฉลี่ย        : %.2f$  (%.0f จุด)", avgLoss, avgLossP);
   PrintFormat("║ สัดส่วน ชนะ:แพ้     : %.2f %s", payoff,
               (payoff < 0.5 ? "← ไม้แพ้ใหญ่กว่าไม้ชนะมาก" : ""));
   PrintFormat("║ Profit Factor     : %.2f", profFact);
   PrintFormat("║ ★ ค่าคาดหวังต่อไม้  : %.1f จุด  (%.2f$)", expectPts, expectUSD);
   PrintFormat("║ แพ้ติดกันสูงสุด     : %d ไม้", maxConsecLoss);
   PrintFormat("║ Drawdown สูงสุด   : %.2f%%", ddPct);
   PrintFormat("║ ⇒ คะแนนรวม        : %.2f", score);
   Print("╚══════════════════════════════════════════");

   return(score);
}

//====================================================================
//                  แดชบอร์ดไฮเทค + หุ่นยนต์โยนเงิน
//====================================================================
#define DB_PREFIX  "XDB_"
#define DB_ROW     20

//--- สร้าง/อัปเดตข้อความ
void DBText(const string name, const int x, const int y, const string text,
            const color clr, const int fontsize = 9, const string font = "Consolas")
{
   string obj = DB_PREFIX + name;
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, obj, OBJPROP_TEXT, text);
   ObjectSetString (0, obj, OBJPROP_FONT, font);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, fontsize);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
}

//--- สร้าง/อัปเดตสี่เหลี่ยม (แผง แถบ เส้นตกแต่ง)
void DBRect(const string name, const int x, const int y,
            const int w, const int h, const color bg, const color border)
{
   string obj = DB_PREFIX + name;
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_BACK, false);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, MathMax(w, 1));
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, MathMax(h, 1));
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, border);
}

//--- แถบวัดระดับแบบแบ่งช่อง (สไตล์ HUD)
void DBSegBar(const string name, const int x, const int y, const int w, const int h,
              double fraction, const int segs, const color fillClr, const color trackClr)
{
   fraction = MathMax(0.0, MathMin(1.0, fraction));
   int gap  = 2;
   int segW = (w - gap * (segs - 1)) / segs;
   int lit  = (int)MathRound(fraction * segs);
   for(int i = 0; i < segs; i++)
      DBRect(name + IntegerToString(i), x + i * (segW + gap), y, segW, h,
             (i < lit ? fillClr : trackClr), (i < lit ? fillClr : trackClr));
}

//--- วาดหุ่นยนต์โยนเงิน (แอนิเมชันด้วยตัวอักษร ไม่ต้องใช้ไฟล์รูป)
void DrawRobot(const int x, const int y, const bool happy, const color accent)
{
   int  f    = (g_frame / 4) % 4;                       // เฟรมช้าลง 4 เท่า
   int  bob  = (f == 1 || f == 3) ? 1 : 0;              // ตัวหุ่นขยับขึ้นลงเบาๆ
   color body = accent;
   color eyes = happy ? C'0,255,140' : C'255,64,96';

   //--- ลำตัวหุ่นยนต์ 4 บรรทัด
   DBText("rb1", x, y + bob,      "  ┌───────┐",  body, 10);
   DBText("rb2", x, y + bob + 13, "  │ ", body, 10);
   //--- ใช้ตัวอักษรพื้นฐาน เพราะฟอนต์บางเครื่องไม่มีสัญลักษณ์วงกลม (ขึ้นเป็นสี่เหลี่ยม)
   DBText("rbE", x + 30, y + bob + 13, (f % 2 == 0 ? "O O" : "- -"), eyes, 10);
   DBText("rb3", x + 62, y + bob + 13, " │", body, 10);
   DBText("rb4", x, y + bob + 26, "  └──┬─┬──┘",  body, 10);
   DBText("rb5", x, y + bob + 39, " ▄▄▄▄█▄█▄▄▄▄", body, 10);

   //--- แขนเหวี่ยง เปลี่ยนท่าตามเฟรม
   string arms[4] = {"╱", "─", "╲", "─"};
   DBText("rbArm", x + 78, y + bob + 13, arms[f], C'255,196,0', 11);

   //--- เหรียญ 3 เหรียญ ลอยเป็นเส้นโค้งออกจากมือหุ่น
   int   handX = x + 92, handY = y + 16;
   string coin = happy ? "💰" : "💸";
   for(int i = 0; i < 3; i++)
   {
      int   ph = (g_frame + i * 9) % 27;                // เฟส 0-26
      double t = ph / 27.0;
      int cx = handX + (int)(t * 96);
      int cy = happy ? handY - (int)(MathSin(t * M_PI) * 26)
                     : handY + (int)(t * 30);           // ขาดทุน = เหรียญร่วง
      DBText("coin" + IntegerToString(i), cx, cy, coin, clrWhite, 10, "Segoe UI Emoji");
   }

   //--- ข้อความใต้หุ่น
   string say = happy ? "เก็บกำไรเข้ากระเป๋า!" : "ระวัง! วันนี้ยังติดลบ";
   DBText("rbSay", x, y + 56, say, (happy ? C'0,255,140' : C'255,140,60'), 8, "Tahoma");
}

//--- วาดกราฟย่อผลไม้ล่าสุด
void DrawMiniChart(const int x, const int y, const int w, const int h)
{
   double maxAbs = 0.01;
   for(int i = 0; i < g_lastCount; i++) maxAbs = MathMax(maxAbs, MathAbs(g_lastPL[i]));

   int baseY = y + h / 2;
   DBRect("mcBase", x, baseY, w, 1, C'40,60,90', C'40,60,90');

   int pitch = (g_lastCount > 0) ? (w / MathMax(g_lastCount, 6)) : w / 6;
   int barW  = MathMax(pitch - 3, 3);

   for(int i = 0; i < 12; i++)
   {
      string nm = "mc" + IntegerToString(i);
      if(i >= g_lastCount) { DBRect(nm, x + i * pitch, baseY, barW, 1, C'20,28,45', C'20,28,45'); continue; }
      double p  = g_lastPL[i];
      int    bh = MathMax(2, (int)MathRound(MathAbs(p) / maxAbs * (h / 2 - 2)));
      if(p >= 0) DBRect(nm, x + i * pitch, baseY - bh, barW, bh, C'0,255,140', C'0,255,140');
      else       DBRect(nm, x + i * pitch, baseY,      barW, bh, C'255,64,96',  C'255,64,96');
   }
}

//====================================================================
//                       วาดแดชบอร์ดทั้งหมด
//====================================================================
void UpdateDashboard()
{
   if(!InpShowDashboard) return;

   //--- ชุดสีธีมไซเบอร์
   color BG      = C'8,11,20';
   color BORDER  = C'0,229,255';
   color DIM     = C'110,130,160';
   color VAL     = clrWhite;
   color GOOD    = C'0,255,140';
   color BAD     = C'255,64,96';
   color WARN    = C'255,196,0';
   color TRACK   = C'22,30,50';
   color DIVIDER = C'30,55,80';

   int X = InpPanelX, Y = InpPanelY, W = 360;
   int x1 = X + 12, x2 = X + 160, y = Y + 6;

   //--- พื้นหลัง + ขอบเรืองแสง (สร้างก่อนเสมอ เพื่อให้อยู่ชั้นล่างสุด)
   DBRect("bgGlow", X - 2, Y - 2, W + 4, g_panelH + 4, C'0,40,50', C'0,120,140');
   DBRect("bg",     X,     Y,     W,     g_panelH,     BG,          BORDER);
   DBRect("hdr",    X,     Y,     W,     24,           C'0,40,55',  BORDER);

   //--- เส้นสแกนวิ่งลง (ลูกเล่นไฮเทค)
   int scanY = Y + 26 + ((g_frame * 3) % MathMax(g_panelH - 30, 10));
   DBRect("scan", X + 1, scanY, W - 2, 1, C'0,110,140', C'0,110,140');

   //=== หัวแผง ======================================================
   bool   live   = (g_frame / 5) % 2 == 0;
   DBText("t_hdr",  x1, y, "◆ XAU STRADDLE  v3.0", BORDER, 10);
   DBText("t_live", X + W - 78, y, (live ? "● กำลังทำงาน" : "○ กำลังทำงาน"),
          (live ? GOOD : C'0,120,90'), 8, "Tahoma");
   y += 26;

   //=== สถานะปัจจุบัน ================================================
   color stClr = DIM;
   switch(g_state)
   {
      case STATE_PENDING_PLACED:  stClr = WARN; break;
      case STATE_POSITION_OPEN:   stClr = VAL;  break;
      case STATE_BREAKEVEN_SET:
      case STATE_TRAILING_ACTIVE: stClr = GOOD; break;
   }
   string stTxt = StateToThai(g_state);
   if(IsHaltedToday()) { stTxt = "🛑 หยุดเทรดวันนี้"; stClr = BAD; }

   DBText("l_st", x1, y, "สถานะ", DIM, 8, "Tahoma");
   DBText("v_st", x2, y, stTxt, stClr, 9, "Tahoma"); y += DB_ROW;

   //=== ช่วงเวลา + นับถอยหลัง ========================================
   int tm = ThaiMinutesNow();
   string thNow = StringFormat("%02d:%02d น.", tm / 60, tm % 60);
   DBText("l_tm", x1, y, "เวลาไทย", DIM, 8, "Tahoma");
   DBText("v_tm", x2, y, thNow, VAL, 9); y += DB_ROW;

   if(InpUseTimeFilter)
   {
      bool inSes = InSession();
      int  left  = inSes ? MinutesToSessionEnd() : MinutesToNextSession();
      string cd  = inSes ? StringFormat("● เปิดรอบ · ปิดใน %d:%02d ชม.", left / 60, left % 60)
                         : StringFormat("○ นอกรอบ · เปิดใน %d:%02d ชม.", left / 60, left % 60);
      DBText("l_se", x1, y, "รอบเทรด", DIM, 8, "Tahoma");
      DBText("v_se", x2, y, cd, (inSes ? GOOD : DIM), 8, "Tahoma");
   }
   else
   {
      DBText("l_se", x1, y, "รอบเทรด", DIM, 8, "Tahoma");
      DBText("v_se", x2, y, "เทรด 24 ชม. (ปิดตัวกรอง)", DIM, 8, "Tahoma");
   }
   y += DB_ROW;

   //=== ราคาและสเปรด ================================================
   long   spread = SpreadPts();
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   DBText("l_pr", x1, y, "ราคา / สเปรด", DIM, 8, "Tahoma");
   DBText("v_pr", x2, y, DoubleToString(bid, _Digits) + "  |  " +
          IntegerToString(spread) + " จุด",
          (spread > InpMaxSpread) ? BAD : VAL, 9); y += DB_ROW + 4;

   DBText("div1", x1, y - 8, "· · · · · · · · · · · · · · · · · · · · · · ·", DIVIDER, 8);

   //=== บัญชี =======================================================
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   DBText("l_ba", x1, y, "ยอดเงิน (Balance)", DIM, 8, "Tahoma");
   DBText("v_ba", x2, y, DoubleToString(bal, 2) + " $", VAL, 9); y += DB_ROW;
   DBText("l_eq", x1, y, "อิควิตี้ (Equity)", DIM, 8, "Tahoma");
   DBText("v_eq", x2, y, DoubleToString(eq, 2) + " $", (eq >= bal ? GOOD : BAD), 9); y += DB_ROW;
   DBText("l_lt", x1, y, "ล็อตไม้ถัดไป", DIM, 8, "Tahoma");
   DBText("v_lt", x2, y, DoubleToString(CalcLot(), 2) +
          (InpUseAutoLot ? "  [อัตโนมัติ " + DoubleToString(InpRiskPercent, 1) + "%]" : "  [คงที่]"),
          WARN, 9); y += DB_ROW + 4;

   DBText("div2", x1, y - 8, "· · · · · · · · · · · · · · · · · · · · · · ·", DIVIDER, 8);

   //=== ผลงานวันนี้ (หัวใจของเวอร์ชันนี้) =============================
   DBText("t_day", x1, y, "▌ ผลงานวันนี้ (เริ่มนับเที่ยงคืนไทย)", BORDER, 9, "Tahoma");
   y += DB_ROW;

   double floatPL = FloatingPL();
   double netAll  = g_dayNet + floatPL;

   DBText("l_dp", x1, y, "💚 กำไรวันนี้", DIM, 8, "Tahoma");
   DBText("v_dp", x2, y, "+" + DoubleToString(g_dayProfit, 2) + " $   (" +
          IntegerToString(g_dayWins) + " ไม้)", GOOD, 10, "Tahoma"); y += DB_ROW;

   DBText("l_dl", x1, y, "❤️ ขาดทุนวันนี้", DIM, 8, "Tahoma");
   DBText("v_dl", x2, y, DoubleToString(g_dayLoss, 2) + " $   (" +
          IntegerToString(g_dayLosses) + " ไม้)", BAD, 10, "Tahoma"); y += DB_ROW;

   DBText("l_dn", x1, y, "◆ สุทธิวันนี้", DIM, 8, "Tahoma");
   DBText("v_dn", x2, y, (netAll >= 0 ? "+" : "") + DoubleToString(netAll, 2) + " $",
          (netAll >= 0 ? GOOD : BAD), 11, "Tahoma"); y += DB_ROW;

   int    totalT = g_dayWins + g_dayLosses;
   double winRt  = (totalT > 0) ? (double)g_dayWins / totalT * 100.0 : 0;
   DBText("l_wr", x1, y, "อัตราชนะ / ไม้สูงสุด", DIM, 8, "Tahoma");
   DBText("v_wr", x2, y, StringFormat("%.0f%%  |  สูงสุด %+.2f$", winRt, g_dayBest),
          (winRt >= 50 ? GOOD : WARN), 9, "Tahoma"); y += DB_ROW + 2;

   //--- แถบเทียบกำไร vs ขาดทุนของวัน
   double scale = MathMax(MathMax(g_dayProfit, MathAbs(g_dayLoss)), 0.01);
   DBText("l_b1", x1, y, "กำไรสะสม", DIM, 7, "Tahoma");
   DBSegBar("barP", x1 + 62, y + 1, W - 90, 7, g_dayProfit / scale, 20, GOOD, TRACK);
   y += 12;
   DBText("l_b2", x1, y, "ขาดทุนสะสม", DIM, 7, "Tahoma");
   DBSegBar("barL", x1 + 62, y + 1, W - 90, 7, MathAbs(g_dayLoss) / scale, 20, BAD, TRACK);
   y += 16;

   //--- แถบวัดระยะห่างจากเพดานขาดทุนรายวัน
   if(InpUseDailyLossStop)
   {
      double maxLoss  = bal * InpDailyLossPct / 100.0;
      double riskFrac = (maxLoss > 0 && netAll < 0) ? MathAbs(netAll) / maxLoss : 0;
      DBText("l_b3", x1, y, StringFormat("ระดับความเสี่ยงวันนี้  %.0f%% ของเพดาน %.0f$",
             riskFrac * 100.0, maxLoss), DIM, 7, "Tahoma"); y += 11;
      DBSegBar("barR", x1, y, W - 28, 7, riskFrac, 24,
               (riskFrac > 0.8 ? BAD : (riskFrac > 0.5 ? WARN : GOOD)), TRACK);
      y += 16;
   }

   DBText("div3", x1, y - 6, "· · · · · · · · · · · · · · · · · · · · · · ·", DIVIDER, 8);

   //=== ออเดอร์ที่เปิดอยู่ตอนนี้ =======================================
   string posTxt = "-", entTxt = "-", slTxt = "-", pfTxt = "-";
   color  posClr = DIM, pfClr = DIM;
   double profPts = 0;

   if(HasMyPosition() && PositionSelectByMagic())
   {
      long   ptype = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double psl   = PositionGetDouble(POSITION_SL);
      double prof  = PositionGetDouble(POSITION_PROFIT);
      double vol   = PositionGetDouble(POSITION_VOLUME);
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      posTxt  = (ptype == POSITION_TYPE_BUY ? "▲ ซื้อ (BUY) " : "▼ ขาย (SELL) ") + DoubleToString(vol, 2);
      posClr  = (ptype == POSITION_TYPE_BUY) ? C'0,170,255' : BAD;
      entTxt  = DoubleToString(entry, _Digits);
      slTxt   = (psl > 0 ? DoubleToString(psl, _Digits) : "ยังไม่ตั้ง");
      pfTxt   = DoubleToString(prof, 2) + " $";
      pfClr   = (prof >= 0) ? GOOD : BAD;
      profPts = (ptype == POSITION_TYPE_BUY) ? (bid - entry) / g_pt : (entry - ask) / g_pt;
   }

   DBText("l_po", x1, y, "ไม้ปัจจุบัน", DIM, 8, "Tahoma");
   DBText("v_po", x2, y, posTxt, posClr, 9, "Tahoma"); y += DB_ROW;
   DBText("l_en", x1, y, "ราคาเข้า", DIM, 8, "Tahoma");
   DBText("v_en", x2, y, entTxt, VAL, 9); y += DB_ROW;
   DBText("l_sl", x1, y, "จุดตัดขาดทุน (SL)", DIM, 8, "Tahoma");
   DBText("v_sl", x2, y, slTxt, VAL, 9); y += DB_ROW;
   DBText("l_pf", x1, y, "กำไรลอยตอนนี้", DIM, 8, "Tahoma");
   DBText("v_pf", x2, y, pfTxt, pfClr, 10, "Tahoma"); y += DB_ROW;

   double tpFrac = (InpTakeProfit != 0) ? profPts / InpTakeProfit : 0;
   DBText("l_b4", x1, y, StringFormat("ความคืบหน้าไปเป้า TP  (%.0f / %d จุด)",
          profPts, InpTakeProfit), DIM, 7, "Tahoma"); y += 11;
   DBSegBar("barT", x1, y, W - 28, 7, tpFrac, 24, C'0,229,255', TRACK); y += 16;

   //=== ส่วนเสริม (ซ่อนได้ในโหมดย่อ) ==================================
   if(!InpCompactMode)
   {
      DBText("div4", x1, y - 6, "· · · · · · · · · · · · · · · · · · · · · · ·", DIVIDER, 8);
      DBText("l_mc", x1, y, StringFormat("▌ ผลไม้ล่าสุด %d ไม้", g_lastCount), BORDER, 8, "Tahoma");
      y += 13;
      DrawMiniChart(x1, y, W - 28, 26);
      y += 32;

      if(InpShowRobot)
      {
         DrawRobot(x1, y, (netAll >= 0), BORDER);
         y += 72;
      }
   }

   //=== ท้ายแผง ====================================================
   DBText("div5", x1, y - 6, "· · · · · · · · · · · · · · · · · · · · · · ·", DIVIDER, 8);
   DBText("f_r1", x1, y, StringFormat("SL %d | TP %d | กันทุน@%d | ไล่เทียน %d จุด",
          InpStopLoss, InpTakeProfit, InpBreakEvenTrigger, InpTrailBufferPts),
          C'70,100,140', 8); y += 13;
   string modeTxt = !InpUseTimeFilter
                  ? "โหมด 24 ชม. ไม่หยุดพัก | 1 ไม้เท่านั้น"
                  : StringFormat("โหมดจำกัดเวลา | หมดเวลา: %s",
                    (InpCloseOnSessionEnd ? "ปิดทุกไม้" : "ถือต่อ"));
   DBText("f_r2", x1, y, modeTxt, C'70,100,140', 8); y += 13;
   DBText("f_r3", x1, y, StringFormat("ทั้งบัญชีวันนี้ %+.2f$ | เพดานรายวัน: %s",
          g_accountNet, (InpUseDailyLossStop ? "เปิด" : "ปิด (รันต่อเนื่อง)")),
          C'70,100,140', 8); y += 15;

   //--- ปรับความสูงแผงให้พอดีเนื้อหาโดยอัตโนมัติ
   g_panelH = y - Y;

   ChartRedraw(0);
}

//--- ลบวัตถุแดชบอร์ดทั้งหมด
void DeleteDashboard()
{
   ObjectsDeleteAll(0, DB_PREFIX);
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
