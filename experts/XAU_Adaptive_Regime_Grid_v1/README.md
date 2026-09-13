# XAU Adaptive Regime Grid v1

EA MQL5 สำหรับ XAUUSD M5 ใช้ Regime M15/H1, directional pullback grid, equal/reduced lot, immutable basket SL และ risk locks. Range module ปิดโดยค่าเริ่มต้น. **รองรับบัญชี Hedging เท่านั้น**

**สถานะ: ซอร์สเพื่อวิจัย ยังไม่ยืนยัน Native Compile และไม่มี Backtest จริง. ไม่ใช่ระบบที่พิสูจน์กำไรแล้ว**

## ไฟล์และลำดับอ่าน

1. [ข้อกำหนดครบ12หัวข้อและแผนวิจัย](DESIGN_AND_TEST_PLAN_TH.md)
2. [ซอร์ส MQL5 เต็ม](XAU_Adaptive_Regime_Grid_v1.mq5)
3. [ผลตรวจ/ข้อจำกัดที่ยังไม่ยืนยัน](REVIEW_STATUS.md)
4. [กรณีทดสอบ MT5](TEST_CASES_TH.md)
5. [พรอมป์ต์ให้ Claude Code Compile และ Backtest บน VPS](CLAUDE_CODE_HANDOFF_TH.md)

ให้ Claude Code อ่านไฟล์ส่งงานแล้วทำตามขั้นตอนจริงบน VPS. ทุน500 USD อาจไม่รองรับ minimum lot ภายในงบ1.5%; ห้ามเพิ่ม risk เพื่อให้เปิดออเดอร์ได้

มี31 inputs ในกลุ่ม GENERAL/TREND/GRID/RISK/EXIT/SESSION/FILTER/DEBUG. ต้องตั้ง session เป็นเวลา broker, spread เป็น broker points และ cost reserve เป็นสกุลบัญชี/lot ก่อนทดสอบ

Preflight ที่ไม่ใช่ MT5: `python checks/verify_contracts.py`

ห้ามอ้างผล preflight ว่าเป็น Compile/Backtest. ห้าม merge เป็นเวอร์ชันพร้อมใช้จริงก่อนตรวจ Native acceptance cases และ OOS/WFA/MC
