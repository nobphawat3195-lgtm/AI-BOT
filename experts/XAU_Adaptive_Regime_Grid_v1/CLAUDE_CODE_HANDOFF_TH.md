# พรอมป์ต์ส่งงานให้ Claude Code — Compile และ Backtest บน VPS

คุณคือ Senior MQL5 Engineer และ Quant Research Engineer รับช่วงโปรเจกต์ XAU Adaptive Regime Grid v1 จากซอร์สในรีโป:

- Repository: https://github.com/nobphawat3195-lgtm/AI-BOT
- Branch: `research/xau-adaptive-regime-grid-v1-20260913`
- Project: `experts/XAU_Adaptive_Regime_Grid_v1/`
- Source: `XAU_Adaptive_Regime_Grid_v1.mq5`

ผู้ใช้อนุญาตให้ Compile, แก้บั๊กเชิง implementation, Backtest/Optimization แบบมีขอบเขตบน VPS และบันทึกหลักฐานใน GitHub. ไม่ได้ขอให้เปิดเทรดเงินจริง

## เป้าหมายและความจริงเริ่มต้น

ผู้เขียนก่อนหน้าเขียนซอร์สและทำ preflight review แล้ว แต่ **ยังไม่มี MetaEditor compile log, EX5 ที่ยืนยันได้ หรือผล MT5 Backtest**. อย่าอ้างว่า Compile ผ่านจากสถานะก่อนหน้า. เป้าหมายคือ Robustness และ Controlled Risk ไม่ใช่บังคับให้ผลกำไรสูง

เริ่มด้วยอ่าน README.md, DESIGN_AND_TEST_PLAN_TH.md, TEST_CASES_TH.md, REVIEW_STATUS.md และซอร์สครบก่อน. เก็บข้อจำกัด/กฎกลยุทธ์เดิม ห้ามเพิ่ม Indicator, Martingale, เพิ่ม Lot แก้ขาดทุน, ถอด SL/lock, ย้ายช่วง OOS หรือขยับ pass criteria เพื่อให้ผ่าน

## ขั้นตอนทำงานที่ต้องทำจริง

1. ตรวจ checkout และ git status ก่อนแตะไฟล์. ถ้ามีงานค้างให้สร้าง worktree แยกจาก branch นี้ ห้าม reset ทับงานผู้ใช้. ใช้ branch ตามด้านบน ไม่ใช้ main โดยอัตโนมัติ
2. หาเครื่องมือ MT5/MCP ที่มีอยู่บน VPS รวม MetaEditor, Terminal, terminal data path, symbol ที่ตรง Broker (เช่น XAUUSD หรือ suffix), account type, build, commission, swap, leverage และ Real Tick coverage. ห้ามพิมพ์ password/token/account login ลง public repo
3. ถ้า environment ที่คุณอยู่เป็น Linux/cloud ซึ่งไม่มีการเข้าถึง Windows VPS/MT5 ให้รายงาน blocker ที่เจาะจงและเตรียมงานต่อได้เท่าที่มี อย่าอ้างว่าคำสั่ง shell หรือ Python จำลองคือ MT5 backtest
4. รัน `python checks/verify_contracts.py` เป็น preflight ถ้ามี Python. ชุดนี้ไม่แทน compiler
5. คัดลอก source ไป Experts ที่ถูกต้องและ Compile ด้วย MetaEditor จริง. ต้องได้ **0 errors, 0 warnings** และ EX5 ใหม่หลัง source. เก็บ full compiler log, terminal build, UTC timestamp, source SHA256 และ binary SHA256. ถ้ามี warning/error แก้แบบเล็กสุดและบันทึก diff+เหตุผล
6. ตรวจ Native behavior ตาม TEST_CASES_TH.md ก่อน Optimize. ประเด็นสำคัญ: partial close retry, timeout/late execution, order visibility, actual fill risk, namespace restart, day rollover, ownership, M5 duplicate และ VWAP. กรณีจำลองไม่ได้ต้อง NOT TESTED ไม่ใส่ PASS
7. แก้เฉพาะ implementation bugs โดยไม่เปลี่ยน Strategy. หากพบว่าต้องเปลี่ยน semantics เช่น retry rejection, sizing model, SL distance rule, regime thresholds หรือ stop-risk budget ให้บันทึก proposal และผลกระทบก่อน ไม่ใช้การแก้กลยุทธ์เงียบ ๆ
8. ทดสอบ baseline หลายปีของข้อมูลที่มีจริงด้วย Every tick based on real ticks บน M5, variable Bid/Ask, commission+swap. ใช้ทุน **500 USD** หากบัญชีสกุล USD และสเปก min lot รองรับ; ถ้าเปิดไม่ได้ใน Risk1.5% ให้รายงาน INFEASIBLE_AT_500 ไม่เพิ่ม lot/risk. หากแยกทดสอบเงินทุนอื่นให้แยกผลชัดเจน
9. ตรึง EnableRangeMode=false, MaxGridLevels=4, risk1.5%, daily3%, equity8% และ news baseline OFF ตามเอกสาร. Set session/spread/cost ให้ตรง broker พร้อมบันทึกเหตุผล; นี่คือ broker calibration ไม่ใช่ optimization หา profit
10. ประกาศช่วง chronological IS60%/validation20%/untouched OOS20% ก่อน optimize. เลือกอย่างน้อย 5 ปีถ้ามี real ticks จริง; ปิด OOS ไว้จนเลือกค่าเสร็จ. ช่วง 7 วันใช้ smoke/debug เท่านั้น
11. ถ้า baseline ไม่มี trades ให้รายงาน rejection breakdown: data/session/spread/minlot/regime/pullback/risk. ไม่ลด filters หรือเพิ่ม risk อัตโนมัติ
12. เมื่อ Engineering ผ่านและ samples เพียงพอ เริ่ม coarse GridATR×BasketTP_ATR ไม่เกิน36 configurations ตาม design; ชุดเต็มใช้ HardStopATR=5.0 เป็น experiment แยกจาก baseline3.5 พร้อมบันทึก impact ต่อ lot. ห้าม 0.01 steps และห้ามเปิด 31 parameters พร้อมกัน
13. เลือก parameter plateau จาก IS+validation. ใช้ OnTester custom score และตรวจ equity DD / equity recovery เพิ่ม. MT5 trade count ไม่ใช่ basket count; ต้องจัดกลุ่ม deals เป็น basket ตามช่วง exposure เริ่ม0→กลับ0 ของ Symbol+Magic
14. ทำ frozen OOS และ Walk Forward 24m train+6m validation+6m forward, เลื่อน6m เมื่อข้อมูลพอ. รวม forward เฉพาะไม่ซ้ำกัน; เก็บทุก fold
15. เตรียม export equity path/floating MAE และ closed baskets สำหรับ Monte Carlo ≥5,000 paths ตามเอกสาร. ห้ามใช้ shuffled individual grid positions แทน independent samples. ถ้าข้อมูล path ไม่ครบให้ระบุ MC_NOT_READY อย่าแต่งตัวเลข ruin
16. ใช้ pass/fail ที่ประกาศไว้: PF>1.30, equity DD<10% (10–12 REVIEW), equity recovery>1.5, OOS>0, จำนวน baskets เพียงพอ, neighbor stability และ MC risk ไม่สูง. ถ้า core ไม่ผ่านรายงาน FAIL แล้วหยุดเพิ่มความซับซ้อน
17. ทดสอบ ablation MaxGridLevels=1 เทียบ4 ที่ budget เท่ากัน เพื่อดูว่า Grid เพิ่มประโยชน์หลังต้นทุนจริงหรือไม่; เก็บเป็น experiment ที่ลงทะเบียนเพิ่ม ไม่ใช้แทนผล core ที่แพ้
18. Commit source fixes พร้อมหลักฐานและ summary บนสาขานี้ หรือสาขาทดสอบต่อเนื่องจากนี้ แล้วเปิด/update draft PR. ห้าม merge/deploy/live trade อัตโนมัติ. ไม่เพิ่มไฟล์ broker data ที่ไม่มีสิทธิ์เผยแพร่, credentials หรือ EX5 ใน public repo โดยไม่จำเป็น

## สิ่งที่ต้องส่งกลับ

สร้าง `results/RESEARCH_SUMMARY_TH.md` และ `results/experiment_manifest.csv` พร้อม raw evidence ที่เผยแพร่ได้. แต่ละ experiment ต้องมี:

- experiment ID, git commit, source SHA256, EX5 SHA256, terminal build
- account currency/deposit/leverage แบบไม่มีเลขบัญชี, broker symbol specs, time zone/DST, date ranges/data coverage
- .set/config ที่ใช้จริง, tick model, commission/swap/spread assumptions, news dataset checksum
- compile status, engineering test cases PASS/FAIL/NOT_TESTED
- net profit, PF, max EQUITY DD ทั้งเงินและ%, equity recovery, balance recovery แยก, trade count, basket count
- worst basket loss/MAE, max grid/volume, longest holding/underwater, yearly/monthly and long/short breakdown
- IS/validation/OOS/WFA/MC statuses พร้อม file references; sample ไม่เพียงพอให้ INCONCLUSIVE
- unresolved limitations และ next action ที่เล็กที่สุด

สรุปตอบผู้ใช้ภาษาไทยสั้น ๆ: Compile ผ่านหรือไม่ → Backtest ช่วงไหน → ตัวเลขจริง → PASS/FAIL/INCONCLUSIVE → ข้อบกพร่องสำคัญ. บันทึกรายละเอียดในไฟล์ ลดการอ่านประวัติซ้ำและใช้ token เท่าที่จำเป็น

ห้ามสร้างผลลัพธ์จำลองแล้วใช้คำว่า Backtest จริง. ห้ามพูดว่า “พร้อมรันจริง” เพราะเพียง Compile ผ่าน. ถ้างานใช้เวลานาน ให้บันทึก checkpoint หลังแต่ละ stage และทำต่อโดยรักษา manifest เดิม
