# สถานะตรวจรับ XAU Adaptive Regime Grid v1

วันที่จัดชุด: 2026-09-13

| รายการ | สถานะ | หลักฐาน/ข้อจำกัด |
|---|---|---|
| ซอร์ส MQL5 เต็ม | เขียนแล้ว | 730 บรรทัด; 31 inputs; CTrade |
| ตรวจเชิงสถิติโดยผู้เขียน | ทำแล้ว | ownership, risk, indexing, restart, closing, lot sizing |
| Preflight Python | PASS 11/11 | checks/preflight_output.txt; structural + independent arithmetic fixtures |
| MetaEditor compile | NOT RUN | สภาพแวดล้อมผู้เขียนไม่มี MetaEditor/MT5; ให้ Claude Code รันบน VPS |
| EX5 | NOT GENERATED | ไม่แนบ binary ที่ยังไม่มีหลักฐาน Compile |
| Native MT5 acceptance cases | NOT TESTED | TEST_CASES_TH.md |
| Real tick multi-year baseline | NOT RUN | ไม่มีตัวเลขกำไร/PF/DD ที่อ้างได้ |
| IS/Validation/OOS | NOT RUN | ต้องลงทะเบียนช่วงก่อน Optimize |
| Walk Forward / Monte Carlo | NOT RUN | ต้องมีผลจริงและ floating equity path ก่อน |
| ใช้เงินจริง | NOT APPROVED BY EVIDENCE | กลยุทธ์ยังไม่มีผลพิสูจน์ Edge |

Source SHA256: `17226f5613bc418714afb85a1fe8590c48ce70f68455e9dc8ebfc79e17c44ec6`

## ประเด็นที่แก้ระหว่าง self-review

- Closing แบบ partial ไม่ถูก count mismatch ทำให้หยุด retry; ข้าม integrity check ระหว่าง CLOSING แต่ยังใช้ risk locks
- ตรวจ filled volume สะสมเพื่อไม่ให้การปิดบางส่วนภายนอกซ่อน basket loss/ทำให้เปิดเติมแทน
- กำหนด namespace แบบ hash สองชุดเพื่อไม่เกินความยาวชื่อ Global Variable
- บันทึก version marker ก่อน snapshot และ closing intent ก่อนคำขอ order เพื่อให้ crash recovery fail closed
- บันทึก consumed M5 bar เมื่อเริ่มปิด ป้องกัน re-entry แท่งเดียวกับ liquidation
- คำนวณ recovery จาก equity drawdown money ใน OnTester แทน balance-only recovery
- ตรวจ connected state ก่อนเปิดคำขอ และตรวจ retcode/deal id หลังคำขอ
- ข่าว CSV อ่านจาก Common/Files เพื่อใช้ local tester agents บนเครื่องเดียวกัน; ต้องตรวจ coverage เอง

## ขอบเขตที่ผู้รับช่วงต้องไม่เข้าใจผิด

1. PASS ของ Python ไม่ตรวจไวยากรณ์ MQL5/ABI/Trade server จริง และไม่ยืนยัน runtime behavior
2. Commission ใช้เงินสำรอง ไม่ใช่ settle commission จริงราย Deal; ผู้ทดสอบต้องตั้งค่าจาก broker และประเมิน actual results
3. Equity guard อ่านทั้งบัญชีแต่ปิดเฉพาะ Symbol+Magic; ไม่รวมความเสี่ยงหลาย instances แบบส่วนกลาง
4. บัญชี Netting ถูกปฏิเสธ, Range default false, fault ต้องตรวจและ reset เอง
5. มี stop-risk estimate แต่ Gap อาจทำให้ขาดทุนเกิน; default 500 USD อาจไม่ได้ส่งออเดอร์แม้มีสัญญาณ
6. Source ไม่ใช่การถอดรายละเอียดจากคลิป YouTube ที่ยังเข้าถึงเนื้อหาไม่ได้ แต่สร้างจากข้อกำหนดที่ผู้ใช้ส่งในแชตนี้
7. ไม่มีการ delegate ให้ AI อื่นในช่วงเขียนนี้; เป็น self-review และยังต้อง Native review ของ Claude
