# Native MT5 acceptance tests

สถานะเริ่มต้นทุกแถว: **NOT TESTED ใน MT5**. Preflight Python ไม่เปลี่ยนสถานะตารางนี้. บันทึก build/config/log/หลักฐานต่อแถวเมื่อ Claude Code ทดสอบจริง

| ID | สถานการณ์ | ผลที่ต้องได้ |
|---|---|---|
| C01 | Compile source บน MetaEditor ของ VPS | 0 errors, 0 warnings; EX5 ใหม่; hashes/log ครบ |
| I01 | Netting account | OnInit ปฏิเสธ; ไม่ส่ง trade |
| I02 | Hedging/XAU suffix/valid inputs | init ผ่าน; รอสัญญาณแท่งถัดไป |
| I03 | Stop geometry ไม่พอ, no enabled sessions, invalid clock | INIT_PARAMETERS_INCORRECT |
| I04 | Data M15/H1 ไม่พร้อม | ไม่มี entry; risk บน owned exposure ยังทำงาน |
| S01 | M15 strong up + H1 strong down | ไม่ TREND_UP |
| S02 | M15 weak/ADX20–25/slope ambiguous | NEUTRAL; ไม่เหมาว่า RANGE |
| S03 | ATR ratio, candle range หรือ spread expansion | ไม่มี Entry/Add; TP/SL/loss management ทำต่อ |
| S04 | Pullback buy/sell mirror | เข้าได้เฉพาะเงื่อนไขเอกสาร; buy Ask/sell Bid |
| S05 | ราคาเปิดแท่ง gap ออกจาก VWAP/EMA zone | ไม่ไล่ราคา |
| S06 | Range disabled | ไม่มี Range entry |
| S07 | Range enabled / oscillation ไม่ครบ | ไม่เข้า Range; เมื่อครบใช้ ATR distance และ cap2 |
| G01 | ราคาไม่ถึง ATR spacing | ไม่ Add |
| G02 | ข้ามหลาย grid ใน tick/newbar เดียว | สูงสุดหนึ่ง order attempt ต่อ M5 bar |
| G03 | เต็ม4 Trend หรือ2 Range | ไม่เติม; cap ไม่หายเมื่อ restart |
| G04 | ATR เพิ่มหลังเริ่ม Basket | ระยะเพิ่มได้; SL ห้ามขยาย; อาจวางไม่ครบระดับ |
| G05 | ทุก level fills เต็ม | lot เท่าเดิม; ไม่มี multiplier |
| G06 | partial entry fill | บันทึก volume จริง; future lot ไม่เกินเดิม; ไม่ยิงเติมส่วนขาด |
| R01 | ทุน500/minlot0.01 จัดงบไม่ได้ | reject; ไม่ปัดขึ้น/เพิ่ม risk |
| R02 | Fixed lot ทุกระดับรวมเกิน1.5% | reject ตั้งแต่ Basket แรก |
| R03 | OrderCalcProfit ล้มเหลว | fail closed; ไม่ใช้ค่า0เป็น risk |
| R04 | Slippage ทำ actual risk เกิน budget | liquidation owned basket หลัง fill |
| R05 | Hard SL hit ระหว่าง data/session/news unavailable | server SL/EA exit ทำงาน; gates ไม่ขวาง close |
| R06 | Max basket cash loss | ปิด Basket; ไม่มี entry ซ้ำแท่งที่เริ่มปิด |
| R07 | Daily DDถึง3%, equity DDถึง8% | close owned positions + day lock; ไม่เปิดวันนั้น |
| R08 | อยู่ใน closing แล้วเปลี่ยนวัน | daily reset ได้ แต่ต้องปิดค้างให้หมดก่อน |
| R09 | daily limit restart วันเดิม | ยัง locked; baseline ไม่ถูกยกใหม่ |
| R10 | วันใหม่ปกติยังไม่เคย lock | day equity reset แต่ peak เดิมยังอยู่ |
| R11 | วันใหม่หลัง daily/equity lock | re-arm baseline; report global tester DD แยก |
| R12 | EA อื่น/Manual ในบัญชี | ไม่ปิด/modify; account-equity guard อาจถูก trigger ตามเอกสาร |
| R13 | มีการลด volume/ปิดบาง Position ภายนอก | count/filled-volume mismatch → liquidation remainder + fault |
| R14 | SL ถูกลบ/ขยาย/แก้ภายนอก | mismatch → liquidation; ไม่เติมตาม SL ใหม่ |
| E01 | กำไรถึง ATR TPแต่ยังไม่พ้น fee reserve | ยังไม่ปิดเป็นกำไร |
| E02 | ATR TP Buy/Sell | ตรวจ Bid/Ask ถูกด้าน; weighted avg ตาม lot จริง |
| E03 | Percent TP | net estimate เทียบ equity ปัจจุบันตาม spec |
| E04 | opposite confirmed regime + option true | ปิดทั้ง Basket; false ห้ามเติมสวน แต่รอ risk/TP |
| X01 | Invalid volume/stops/freeze/free margin/direction | precheck reject หรือ broker rejection → fault; ไม่แก้ส่งใหญ่ขึ้น |
| X02 | ตลาดปิด/holiday/close-only | new entry ไม่ผ่าน; closing คง intent และ retry เมื่อทำได้ |
| X03 | PositionClose return false/retcode rejected | มี error log และ retry; ไม่ทำเหมือนปิดแล้ว |
| X04 | PositionClose partial success | CLOSING ต่อ; ไม่ fault เพราะ countลดระหว่าง closing; close residue |
| X05 | send timeout/PLACED/no deal yet | FAULT และ liquidate late exposure; ไม่มี blind resend |
| X06 | unexpected owned order | cancel+close own exposure, fault; ไม่แตะ others |
| P01 | crash ระหว่างบันทึก snapshot | version marker/integrity → fail closed |
| P02 | crash ระหว่างส่ง order | restored closing intent; ปิดก่อนเปิดใหม่ |
| P03 | restart มี Basket และ metadata ครบ | restore SL/lot/cap/levels/equity/bar; skip attach bar |
| P04 | restart มี owned exposure แต่ metadata หาย | fault+liquidation; ไม่สร้าง budget ใหม่ |
| P05 | แนบสอง chart Symbol+Magic เดียว terminal | instance ที่สองปฏิเสธ owner lock |
| P06 | คนละ Magic บน Symbol เดียว | บริหารแยก; รวม risk ต้องประเมินเอง |
| V01 | เที่ยงคืน broker | VWAP reset; รอ3 closed M5 bars; risk/ATR TP ยังทำงาน |
| V02 | real volume มีครบ/ขาดบางแท่ง | ใช้ real ทั้งวันเมื่อครบ มิฉะนั้น tick ทั้งวัน; ไม่ผสมหน่วย |
| V03 | fixture OHLC/volume ที่คำนวณมือ | VWAP ตรง Σtypical×volume/Σvolume; ไม่รวมแท่งเปิด |
| T01 | Session 22:00-02:00 / boundaries | รวม start ไม่รวม end; ข้ามวันถูก |
| T02 | Session overlap / equal start-end | OR; equal=24h; ไม่เปิดซ้ำเพราะทับซ้อน |
| N01 | NEWS_NATIVE ใน Strategy Tester | ปฏิเสธ OnInit บอกให้ใช้ OFF/CSV |
| N02 | native API ล้มเหลว/metadata eventล้มเหลว | block entry/add; risk exitไม่ถูก block |
| N03 | USD high event ก่อน30/หลัง15นาที | block ในขอบเขตรวม endpoints |
| N04 | CSV หาย/ว่าง/บรรทัดผิด/ timezoneไม่ตรง | fileผิด init fail; timezone/coverage ต้องพบจาก data audit |
| F01 | negative net/PF<1/sampleต่ำ | custom fitness ถูกลงโทษ |
| F02 | positive balance แต่ floating DDสูง | equity DD/recovery ใช้ equity; ห้ามรายงาน balanceแทน |
| F03 | optimization passes หลายชุด | persistence ไม่ปน pass; repeat seed/configได้ผลเหมือนเดิม |

Fault injection X03–X05/P01–P05 ต้องใช้ demo/harness ที่รองรับ และต้องไม่ไปรบกวน terminal ที่มีการเทรดเงินจริง. ยังไม่สามารถยืนยันจาก native Tester ปกติเพียงอย่างเดียว
