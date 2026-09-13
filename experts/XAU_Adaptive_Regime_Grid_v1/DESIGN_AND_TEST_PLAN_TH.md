# XAU Adaptive Regime Grid v1 — ข้อกำหนดและแผนพิสูจน์ระบบ

สถานะ: เขียนซอร์สและตรวจเชิงสถิติโดยผู้เขียนแล้ว **ยังไม่ได้ Compile ด้วย MetaEditor และยังไม่มีผล Backtest** ห้ามอ้างว่า Compile ผ่านหรือมี Edge จนกว่าจะมีหลักฐานจาก MT5 งานถัดไปเป็นของ Claude Code บน VPS ตาม CLAUDE_CODE_HANDOFF_TH.md

## 1. Architecture Summary

โมดูล: Indicators → Regime → Entry/Grid → Execution โดย Risk Engine มีลำดับสูงสุดและไม่รอข้อมูล Indicator ส่วน Basket Engine, Persistence, Session/Spread/News และ Panel แยกหน้าที่กัน ใช้ CTrade synchronous และบัญชี Hedging เท่านั้น

ข้อกำหนดที่เติมให้ชัดเจนก่อนสร้าง:

| ประเด็น | ข้อกำหนดใน v1 และเหตุผล |
|---|---|
| Grid ไม่ใช่ Edge ในตัวเอง | การถัวเฉลี่ยจำกัดระดับยังเป็นการเพิ่ม Exposure เมื่อราคาวิ่งสวน ต้องพิสูจน์ว่า Regime/Pullback มีความคาดหวังบวกหลังต้นทุน |
| Stop ที่ใช้คำนวณ Risk | ล็อก Stop ร่วมจากราคาแรก ± HardStopATR × ATR(M5, shift 1); ทุก Position มี SL บน Server และไม่ขยาย Stop |
| บัญชี Netting | ปฏิเสธ OnInit เพราะ Position ของ Symbol เดียวรวมกันและ Magic ไม่ใช่หลักฐานแยกความเป็นเจ้าของที่เพียงพอ |
| ตลาดไม่เข้าเงื่อนไข | เพิ่ม REGIME_NEUTRAL สำหรับพักการเข้า ไม่ถือว่าตลาดที่ไม่ Trend เป็น Range โดยอัตโนมัติ |
| จำนวน Basket | หนึ่ง Basket ทิศทางเดียวต่อ Symbol+Magic; ไม่เปิด Buy/Sell พร้อมกัน |
| ข้อมูลสัญญาณ | ใช้แท่งปิด shift 1 ของแต่ละ TF; slope เทียบ shift 1+N; ATR baseline ใช้ shift 2..51 |
| Timeframe | ใช้ M5/M15/H1 ภายในแบบคงที่; ให้ทดสอบบน M5 แม้ติด EA บน TF อื่นก็ยังใช้ M5 |
| งบ Risk | จำกัดจาก min(Equity ตอนเริ่ม Basket, Equity ปัจจุบัน) ไม่เพิ่มงบตามกำไรระหว่าง Basket |
| จอง Lot | ทั้ง Fixed และ Risk mode ต้องรองรับความเสี่ยงของระดับสูงสุดตั้งแต่แรก; ระดับถัดไปไม่เพิ่ม Lot |
| H1 Strong opposite | นิยามเช่นเดียวกับ M15: EMA50/200 + slope/ATR + ADX ถึง threshold |
| Range | default ปิด; สูงสุด min(2, MaxGridLevels); เฉพาะ ADX M15<20, slope ต่ำ, H1 ไม่ strong และมีการแกว่งสองด้าน VWAP |
| Session | 3 input string เพื่อจำกัดจำนวน Input; ค่าว่าง=ปิด, HH:MM-HH:MM=เปิด; เวลาเท่ากัน=24 ชั่วโมง; รวมช่วงแบบ OR |
| VWAP | Reset เวลา 00:00 Broker ทุกวัน; ใช้ Typical Price ของแท่ง M5 ที่ปิดแล้วถ่วง volume; ไม่ใช่ tick-price exact VWAP |
| จำนวน Input | 31 รายการ แบ่ง 8 กลุ่ม; เพิ่มไฟล์ข่าวเพื่อให้ Tester ใช้ข่าวชุดเดียวกันได้ |
| Equity DD lock | Peak สะสมข้ามวันปกติ; เมื่อชน lock จึง re-arm peak ในวันใหม่ตามโจทย์; Tester DD ตลอดเส้นทางยังต้องวัดแยก |
| ความผิดปกติ Execution | ปิด Exposure ที่เป็นของ EA และล็อก FAULT เพื่อสอบสวน ไม่พยายามเปิดชดเชย |
| TP | Basket ATR TP เป็น virtual exit ต่อ Tick; SL เป็น server-side; ถ้า terminal ปิด TP ไม่ทำงานแต่ SL ยังอยู่ |

ความขัดแย้งเชิง Quant ที่ต้องรับทราบ: ความเสี่ยงคาดการณ์ 1.5% ไม่รับประกันการขาดทุนจริง 1.5% เพราะ Gap, Slippage และสภาพคล่อง; ทุน 500 USD อาจเปิด 0.01 lot ไม่ได้ในงบ 4 ระดับ ให้รายงานว่าไม่สามารถจัดขนาดได้ ห้ามปัด Lot ขึ้นหรือเพิ่ม Risk เพื่อให้มี Trade

## 2. Trading Logic Summary

### Trend Buy (Sell กลับเครื่องหมายทุกข้อ)

1. M15 EMA50>EMA200, (EMA200[1]-EMA200[1+N])/ATR[1] ≥ MinimumSlopeATR และ ADX≥TrendADXThreshold
2. H1 ไม่ Strong Bearish; Expansion มาก่อนทุก Regime
3. M5 EMA50>EMA200; Close[1] สูงกว่า VWAP และห่างไม่เกิน 1.5 ATR
4. Low[1] แตะเขต EMA50+0.5 ATR และ |Close[1]-EMA50|≤0.5 ATR; ไม่ใช้ Candle Pattern เพิ่ม
5. ราคาที่ส่งจริงต้องยังอยู่ฝั่ง VWAP เดิม ห่าง VWAP ไม่เกิน 1.5 ATR และห่าง EMA50 ไม่เกิน 0.5 ATR เพื่อไม่ไล่ราคาเมื่อเปิดแท่งกระโดด
6. ตรวจ session, spread, news, symbol permission, market schedule, volume, margin, stop/freeze และ budget แล้วส่ง Entry #1 พร้อม SL
7. Add ได้เมื่อ Regime ยังทิศเดิม, ราคา executable วิ่งสวนจาก Last actual entry ≥ ATR[1]×GridATRMultiplier, จำนวนยังไม่เต็ม และ risk หลังเพิ่มยังอยู่ในงบ
8. Add ไม่บังคับ Pullback/VWAP ของ Entry #1 ซ้ำ เพราะนั่นอาจขัดกับราคาที่ถอยเข้า Grid แต่ยังต้องผ่าน Regime ทุกครั้ง
9. สูงสุดหนึ่งคำขอเปิดต่อแท่ง M5 ไม่มี catch-up หลายระดับใน Tick เดียว ระยะห่างจริงจึงอาจกว้างกว่า ATR spacing เมื่อราคา Gap

### Expansion / Range / Neutral

- Expansion เมื่อ ATR[1] > mean(ATR[2..51])×ExpansionATRMultiplier หรือ High[1]-Low[1] > ATR[1]×ExpansionCandleMultiplier หรือ Spread ณ เวลาตรวจเกินเพดาน
- ระหว่าง Expansion ไม่เปิด/เติม แต่ยังตรวจ SL, loss limit และ TP ทุก Tick ไม่ปิดเพราะ Expansion เพียงอย่างเดียว
- Range ใช้ Close และราคาจริงต่ำ/สูงกว่า VWAP 0.8–1.8 ATR; การ oscillate คือใน 12 แท่งท้ายของวัน มีอย่างน้อย 2 close เหนือ และ 2 close ใต้ VWAP สะสม ณ แท่งนั้น
- Neutral ไม่เปิด/เติม; Range basket ไม่กลายเป็น Trend basket และ Trend basket ไม่กลายเป็น Range basket
- เมื่อ Regime ยืนยันตรงข้ามกับทิศ Basket และ CloseOnRegimeFlip=true ให้ปิด Basket ทั้งหมด รวม Range ที่สวน Trend ใหม่

### Risk / Exit

Weighted average = Σ(volume×entry)/Σvolume. Floating net estimate = Σ(position profit+swap) − CostReservePerLot×open volume. ใช้เงินสำรองค่าธรรมเนียมเต็มรอบเพื่อไม่ให้ TP ที่แสดงกำไรเล็กน้อยกลายเป็นขาดทุนหลังต้นทุน แต่ไม่ใช่การอ่าน Commission จริงแบบราย Deal

Risk ประเมินแต่ละ Position ด้วย OrderCalcProfit(entry→SL) เป็นสกุลบัญชี รวม downside เท่านั้น + reserve ค่าธรรมเนียม + เงินกันชนราคา 2×20 points ต่อ lot + swap ที่ติดลบ ไม่มีการใช้กำไรของ Position หนึ่งหักกลบ Risk ของอีก Position

Risk-based lot = floor_to_step[Equity×risk% / (MaxLevels×first-entry loss per lot)]. วิธีจองนี้ conservative กว่าการสมมุติว่าทุกระดับได้ราคาตามแผน ห้ามปัดขึ้นถึง minimum lot ถ้างบไม่พอ

SL อยู่ที่ราคาเดียวกันตลอด Basket. ATR ระยะกริดและ TP ใช้ ATR ล่าสุดของแท่งปิดและเปลี่ยนได้ แต่ SL ไม่เปลี่ยน. ตรวจ Risk ซ้ำหลัง fill ถ้าเกินให้ liquidation แทนเลื่อน Stop ออก

ATR TP = average ± ATR[1]×BasketTP_ATR, Buy ตรวจ Bid / Sell ตรวจ Ask และ net estimate>0. Percent TP ใช้ net estimate ≥ Equity ปัจจุบัน×BasketProfitPercent/100. MaxBasketLoss ใช้ Basket-start Equity เป็นฐานคงที่

Daily DD=(StartOfDayEquity-CurrentEquity)/StartOfDayEquity; Equity DD=(PeakEquity-CurrentEquity)/PeakEquity. ทั้งสองอ่านบัญชีทั้งบัญชีแต่ปิดเฉพาะ Symbol+Magic ของ EA นี้ จึงควรทดสอบในบัญชีแยก; เงินฝาก/ถอนหรือ EA อื่นกระทบ lock ได้

## 3. State Machine

| สถานะ | เหตุการณ์ | การเปลี่ยน/การกระทำ |
|---|---|---|
| FLAT | แท่งใหม่+สัญญาณ+ผ่าน gates | จองงบ/SL → บันทึก closing intent → ส่งคำขอ sync → ACTIVE เมื่อยืนยัน Deal |
| FLAT | ไม่ผ่าน filter/ไม่มี lot ที่รับได้ | รอต่อ ไม่เพิ่มความเสี่ยงเพื่อเปิดให้ได้ |
| ACTIVE | แท่งใหม่+ระยะและงบเพียงพอ | Add หนึ่งระดับด้วย lot เท่าเดิมหรือต่ำกว่า |
| ACTIVE | Expansion/Neutral/นอกเวลา/ข่าว | บริหาร Basket เดิม ห้าม Add |
| ACTIVE | TP/SL/loss limit/opposite regime | CLOSING |
| ทุกสถานะ | daily/equity limit | latch DAY_LOCK และ CLOSING จน Exposure เป็นศูนย์ |
| CLOSING | ปิดได้บางส่วน/ตลาดปิด | retry ไม่เกินครั้งต่อวินาทีของ server tick; ไม่ยกเลิก closing intent |
| CLOSING | ไม่มี owned position/order | FLAT หรือ DAY_LOCK/FAULT ตาม latch; ห้าม re-entry แท่งที่เริ่มปิด |
| DAY_LOCK | วัน Broker ใหม่ | ปลด daily lock และตั้ง baseline ใหม่; ถ้ายังปิดค้างต้องปิดให้เสร็จก่อน |
| ทุกสถานะ | metadata/SL/count/volume ผิด, send ไม่แน่นอน | FAULT+liquidation ของตนเอง; ต้องตรวจและ reset เอง |
| รีสตาร์ต | มี persistent closing intent | ปิดต่อก่อน ไม่ resume เปิด |
| รีสตาร์ต | มี owned position แต่ไม่มี metadata | FAULT+liquidation ไม่เดา basket budget |

Snapshot อยู่ใน Terminal Global Variables โดย namespace hash ของ login+server+symbol+magic; มี version=-1 marker ก่อนเขียน snapshot ถ้าขาดกลางทาง fail closed. Lock แบบ CAS ป้องกัน Symbol+Magic ซ้ำภายใน terminal เดียว **ไม่ครอบคลุมหลาย terminal บนบัญชีเดียวกัน** ห้ามใช้ namespace เดียวกันข้าม terminal

FAULT ไม่หายจากการ detach/attach ธรรมดา. วิธี reset: ปิด owned positions/orders ให้หมด, ถอด EA, ตรวจ Journal และ prefix ที่ OnInit พิมพ์, ลบเฉพาะตัวแปร prefix นั้นใน F3 แล้วแนบใหม่. ห้ามเปลี่ยน Magic เพื่อทิ้ง Position เก่า. EA ไม่ลบ snapshot อัตโนมัติเมื่อถอดออก

## 4. Pseudocode

```text
OnInit:
    validate 31 inputs / session strings / grid-stop geometry
    reject netting, unsupported symbol, native news inside tester
    load optional news timestamp file
    acquire unique terminal owner lock
    create M5/M15/H1 EMA50 EMA200 ATR14 ADX14 handles
    restore daily / peak / basket / lastbar / close / fault state
    unknown exposure => fault + closing; do not enter attach bar

OnTick:
    read bid/ask; scan only own symbol+magic positions
    risk: new day / equity peak / account locks / state integrity / basket SL / basket loss / risk estimate
    if closing: cancel own orders + close own position tickets; retry until zero; return
    clear completed basket state
    manage basket TP using latest closed ATR (works even if VWAP not ready)
    if closing: close; return
    if new M5 bar:
        persist consumed bar before any send
        copy closed indicator buffers and current broker-day closed rates
        detect Expansion -> Trend -> Range -> Neutral
        if opposite regime and option: latch closing
        else if armed and data ready: first entry or one add
    update small chart panel

Send:
    refresh executable price; recheck gates / stop / risk / margin / spacing
    persist closing=true BEFORE request (crash safety)
    CTrade.PositionOpen with immutable server-side SL
    check method boolean + retcode + deal id
    uncertain/rejected => permanent fault; never retry entry automatically
    confirmed fill => increment levels, record actual filled volume, never grow lot
    persist active; rescan; recheck actual risk

OnTester:
    negative/invalid expectancy => -1
    cap PF and equity recovery; penalize too few MT5 trades and equity DD
    severe penalty for fault or unclosed execution state
```

## 5. Parameter Table

ค่าตั้งต้นเป็นสมมติฐานวิจัย ไม่ใช่ค่าที่ผ่านการทดสอบแล้ว ช่วงตัวเลขแบบรายรายการไม่ใช่ทุกชุดผสมโดยอัตโนมัติ

| กลุ่ม / Input | Default | Optimization หรือวิธีตั้ง |
|---|---|---|
| GENERAL / MagicNumber | 26091301 | ไม่ Optimize; unique ต่อ instance |
| LotMode | LOT_RISK_BASED | ตรึง Risk-based; Fixed เป็นการทดสอบแยก |
| FixedLot | 0.01 | ตามสเปก broker และงบ; ไม่ไล่กำไร |
| TREND / TrendADXThreshold | 25 | 20 ไม่อนุญาตเพราะชน RANGE_ADX; ทดลอง 22,25,30 |
| SlopeLookback | 5 | ตรึงก่อน; sensitivity 3,5,8 |
| MinimumSlopeATR | 0.10 | 0.05,0.10,0.20 |
| GRID / ATRPeriod | 14 | ตรึง 14; sensitivity ภายหลัง 10,14,20 |
| GridATRMultiplier | 0.7 | 0.4,0.6,0.8,1.0,1.2,1.5 แบบ coarse |
| MaxGridLevels | 4 | ตรึง 4; ablation 1,2,4; ไม่เพิ่มเกิน 4 เพื่อกู้ผล |
| EnableRangeMode | false | ตรึง false ในการพิสูจน์ Core |
| RISK / MaxBasketRiskPercent | 1.5 | ไม่ Optimize เพื่อ PF; stress ลด 0.5,1.0 แยก |
| MaxBasketLossPercent | 1.5 | ต้อง ≥ MaxBasketRiskPercent; ไม่เพิ่มเพื่อซ่อนแพ้ |
| DailyLossLimitPercent | 3.0 | ไม่ Optimize |
| MaxEquityDrawdownPercent | 8.0 | ไม่ Optimize |
| HardStopATR | 3.5 | baseline 3.5; ชุด coarse grid เต็มช่วงใช้ 5.0 คงที่เป็น experiment แยก |
| CostReservePerLot | 10.0 | สกุลบัญชี/lot เต็มรอบ; ตั้งจากต้นทุนจริง ไม่ Optimize |
| EXIT / BasketExitMode | EXIT_ATR | ตรึง ATR; percent เป็น experiment แยก |
| BasketTP_ATR | 0.4 | 0.2,0.3,0.4,0.5,0.6,0.8 |
| BasketProfitPercent | 0.5 | ไม่ใช้เมื่อ EXIT_ATR; ถ้าศึกษา percent แยก 0.25,0.5,0.75 |
| CloseOnRegimeFlip | true | ตรึง true; false เป็น ablation ที่ลงทะเบียนก่อน |
| SESSION / AsianSession | ค่าว่าง | ปิด; กรอกเวลา Broker เมื่อต้องการเปิด |
| LondonSession | 08:00-17:00 | ตัวอย่างเวลา ไม่ใช่การแปลง DST ให้ broker |
| NewYorkSession | 13:00-22:00 | ตัวอย่างเวลา; ถ้าปิดใช้ค่าว่าง |
| FILTER / ExpansionATRMultiplier | 1.8 | ตรึงก่อน; sensitivity 1.5,1.8,2.2 |
| ExpansionCandleMultiplier | 2.5 | ตรึงก่อน; sensitivity 2.0,2.5,3.0 |
| MaxSpreadPoints | 40 | ตาม Digits และ spread จริง; 40 points=0.40 เมื่อ Point=0.01 แต่=0.040 เมื่อ Point=0.001 |
| NewsMode | NEWS_OFF | OFF baseline ระบุชัด; CSV สำหรับย้อนหลัง; NATIVE live/demo เท่านั้น |
| NewsBeforeMinutes | 30 | ตรึงจากนโยบายความเสี่ยง |
| NewsAfterMinutes | 15 | ตรึงจากนโยบายความเสี่ยง |
| NewsCSVFile | XAU_USD_high_impact.csv | ใน Terminal Common/Files; ไม่ใช่ชื่อไฟล์ผลทดสอบ |
| DEBUG / DebugMode | false | true เฉพาะตรวจ behavior/visual; false ใน optimization |

ข้อจำกัด Geometry: HardStopATR > (MaxGridLevels−1)×GridATRMultiplier+0.25. ATR ภายหลังอาจเพิ่มจนวางไม่ครบทุกระดับได้ เป็นพฤติกรรมที่ยอมรับ ต้องไม่ขยับ SL ออกเพื่อให้ครบกริด

CSV ข่าว: plain text หนึ่งคอลัมน์ `YYYY.MM.DD HH:MM` ต่อบรรทัด ตาม Broker Server Time; มีเฉพาะ USD High impact ที่คัดกรองแล้ว; บรรทัดขึ้น # เป็น comment ได้ ไม่แนบข่าวสมมุติ. วางใน Terminal Common/Files ของเครื่องที่รัน local agents; ห้าม Cloud/remote agents ถ้ายังไม่ส่งไฟล์ที่ checksum เดียวกันไปให้ครบ. CSV ไม่มีการตรวจ coverage อัตโนมัติ ผู้ทดสอบต้องยืนยันช่วงครอบคลุมและ timezone/DST. Native calendar ล้มเหลวให้ block ไม่เงียบข้ามข่าว

## 6. Full MQL5 Source Code

ซอร์สเต็มอยู่ใน [XAU_Adaptive_Regime_Grid_v1.mq5](XAU_Adaptive_Regime_Grid_v1.mq5) ไฟล์เดียว ไม่มี third-party include นอกจาก Standard Library `Trade/Trade.mqh`. ตัวซอร์สเป็น deliverable หลัก ไม่ใช่ pseudocode และไม่มีฟังก์ชัน placeholder

## 7. Compile Risk Review

### ตรวจจากโค้ดแล้ว (ไม่เท่ากับ Compile ผ่าน)

- ไม่มี MQL4 OrderSelect/MarketInfo compatibility hacks; ใช้ ticket overload ของ PositionClose
- ใช้ buffer shift 1 ทีละค่าเพื่อไม่สับสน series indexing; CopyRates loop เดิน physical oldest→newest
- ไม่ใช้แท่งกำลังก่อตัวเป็นสัญญาณ; ไม่มีใช้ future event outcome/ข่าว actual value
- ใช้ Bid สำหรับ Buy exit และ Ask สำหรับ Sell exit; entry ใช้ Ask/ Bid ตามด้าน
- SL normalize ด้วย tick size ไปทางที่ไม่เพิ่ม Risk; lot ปัดลง; ไม่ยกขั้นต่ำถ้างบไม่พอ
- ทุกการปิด/ลบตรวจ Symbol+Magic และ retcode; partial close คง CLOSING และ retry
- บันทึก last consumed bar ก่อนส่งคำขอ; ปิดในแท่งใดจะไม่กลับเข้าแท่งนั้น
- ตรวจ cumulative filled volume และ position count; position บางส่วนหายหรือถูกแก้ SL จะ liquidation ที่เหลือ
- data ไม่พร้อม block entry แต่ไม่ block risk/TP
- restart ไม่ยก Daily baseline ใหม่เมื่อมี snapshot; attach ครั้งแรกกลางวันใช้ Equity ตอน attach เพราะไม่สามารถสร้าง Equity เที่ยงคืนย้อนหลังอย่างแม่นยำได้
- รีเซ็ต VWAP จากวัน Broker และไม่ย้อนใช้ VWAP เมื่อวานหลังเที่ยงคืน; รออย่างน้อย 3 closed M5 bars ของวัน
- Snapshot partial write marker fail closed; CAS กัน duplicate instance ภายใน terminal เดียว
- ไม่มี Modify SL เพราะ SL ล็อกตั้งแต่เปิด; freeze level ตรวจตอน entry แบบ conservative; broker เป็นตัวตัดสิน execution จริง

### ความเสี่ยงที่ยังต้องตรวจด้วย Native Compiler/Terminal

1. Compile 0 errors และ 0 warnings บน MetaEditor build ของ VPS; เก็บ log จริงและ SHA256 ของ mq5/ex5
2. Native Economic Calendar API/enum และ Trade standard library ใน build ของ broker
3. POSITION_TIME_MSC, partial-fill ResultVolume และ deal→position visibility ทันทีหลัง sync request
4. Broker hedging/FIFO restrictions, session schedule, holiday/close-only และ fill policy FOK/IOC
5. Terminal Global Variables และ persistent recovery ใน terminal demo จริง; Tester ตั้งใจไม่ใช้ global persistence เพื่อแยก optimization passes
6. Lot step/tick size ที่ต่างจาก XAUUSD มาตรฐาน และค่าคอมมิชชันเป็นสกุลบัญชี
7. Native TESTER ทุก Tick และ forced liquidation ตอนสิ้นสุดช่วง รวม floating equity DD จาก path ไม่ใช่ balance อย่างเดียว

การตรวจเชิงสถิติและ numeric fixtures ใน `checks/verify_contracts.py` เป็น preflight เท่านั้น ไม่จำลองระบบ MT5 และไม่ใช้แทน Compile/Backtest

แหล่งยืนยัน API ทางการ:

- [CTrade PositionOpen](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionopen): ต้องตรวจผลจาก server เพิ่มจาก boolean
- [CTrade PositionClose](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionclose): ใช้ ticket และตรวจ retcode
- [OrderCalcProfit](https://www.mql5.com/en/docs/trading/ordercalcprofit): ประเมิน P/L ในสกุลบัญชี
- [Economic Calendar](https://www.mql5.com/en/docs/calendar): timestamp ของ calendar ใช้ trade server time
- [SymbolInfoSessionTrade](https://www.mql5.com/en/docs/marketinformation/symbolinfosessiontrade): ใช้ตารางช่วงเวลาที่ broker ส่งมา
- [Testing Statistics](https://www.mql5.com/en/docs/constants/environment_state/statistics): OnTester ใช้ Equity DD; คำนวณ equity recovery เอง เพราะ STAT_RECOVERY_FACTOR ทางการอิง balance DD
- [GlobalVariableSetOnCondition](https://www.mql5.com/en/docs/globals/globalvariablesetoncondition): ใช้ atomic compare-and-set สำหรับ owner lock

## 8. Backtest Plan

### Gate A — Engineering (ต้องผ่านก่อนค้นหาค่าที่กำไร)

ดูตาราง TEST_CASES_TH.md ครอบคลุม restart/duplicate/grid stop/partial failures/ข่าว/เวลา. การจำลอง rejection หรือ restart ที่ Strategy Tester ปกติทำไม่ได้ให้ทดสอบ demo หรือ test harness แยกและติดสถานะ NOT TESTED จนมีหลักฐาน ห้ามใช้เงินจริง

### Gate B — Data and baseline

- ใช้ XAUUSD ของ Broker ที่จะใช้จริง, M5, Every tick based on real ticks, historical Bid/Ask ที่เปลี่ยนจริง, commission+swap ครบ
- เป้าหมายอย่างน้อย 5 ปีเต็มถ้ามีข้อมูล; ใช้ช่วงครบปีที่มีจริง เช่น 2021–2025 เมื่อข้อมูลครบ ห้ามอ้างตัวอย่างนี้ว่าโหลดมาแล้ว
- Export symbol specification, GMT/DST policy, leverage, stop-out, account currency, tick data gaps, tester build และคุณภาพ/coverage
- แบ่งตามเวลา 60% IS /20% validation /20% untouched OOS; ประกาศ boundary ก่อน optimize. เตรียม warm-up H1 ≥250 bars ก่อนเริ่มแต่ละช่วงโดยห้ามนำผล warm-up ไปรวม
- เริ่ม baseline ตาม default. ถ้าไม่เทรด ให้แยกเหตุผล min lot, filter, data, session หรือ implementation ไม่ใช่เพิ่ม risk/simplify signal ทันที
- ถ้าจะใช้ทุน 500 USD ให้ใช้จริงตามโจทย์เงินทุนและรายงานความสามารถจัดขนาด; บัญชีใหญ่กว่าเป็น experiment แยก ไม่ปะปนผล
- ใช้ deposit/leverage/cost เดียวกันในชุดเปรียบเทียบ; ไม่ปรับ leverage ระหว่างผลที่นำมาเทียบ
- Baseline ต้องรวมหลายปี; ช่วงสั้นใช้เช็คระบบเท่านั้น ไม่เป็นหลักฐาน Edge

### Gate C — Limited optimization

เริ่ม grid spacing × TP เท่านั้น. ใช้ HardStopATR=5.0 คงที่ใน experiment coarse 6×6=36 ชุด เพื่อให้ geometry รองรับ spacing ทุกค่า. รายงาน baseline 3.5 แยกและระบุว่าการขยาย stop ทำให้ risk-based lot เล็กลง. จากนั้นจึงศึกษาความไว ADX/slope แบบ staged โดยไม่เปิดทุก Input พร้อมกัน

กรณีต้องการ arithmetic MT5 optimizer ใช้ spacing 0.4..1.2 step0.2, TP 0.2..0.6 step0.1; ทดสอบ spacing1.5 และ TP0.8 แยก อย่าเปลี่ยนโจทย์เป็น step0.01. เลือกบริเวณหลายค่าที่ใกล้กันผ่าน ไม่เลือกเฉพาะจุดสูงสุด. นับทุก experiment เพื่อไม่ซ่อน multiple testing

### Gate D — Pass/fail ที่ลงทะเบียนก่อนดู OOS

- Net OOS >0 หลังต้นทุน
- PF >1.30; Equity DD <10% เป็น PASS, 10–12% เป็น REVIEW ไม่ใช่ PASS อัตโนมัติ, ≥12% FAIL
- Equity recovery = net profit/max equity drawdown money >1.5; รายงาน MT5 balance recovery แยก
- กำหนดขั้นต่ำเบื้องต้น IS ≥200 closed baskets, OOS ≥50 closed baskets และอย่างน้อย 12 เดือน OOS; ต่ำกว่านี้ INCONCLUSIVE ไม่ตีความ PF สูงว่า PASS
- ไม่มี grid overflow/lot escalation/SL removed/ownership leakage/stop-out; พบหนึ่งครั้ง Engineering FAIL
- ตรวจ floating exposure, worst basket, MAE/MFE, max lots, ระยะถือ, underwater duration, ผลรายปี/เดือน/long-short/session, กำไรที่กระจุกเพียงไม่กี่ Basket
- ค่าเพื่อนบ้านต้องมี majority ให้ผลบวกและผลไม่ทรุดจาก perturbation เล็ก; pre-register อย่างน้อย 2/3 ของเพื่อนบ้านได้ validation net>0 โดยไม่เลือกเพื่อนบ้านภายหลัง
- รายงานทั้ง trade PF และ basket PF; Grid 4 positions ไม่ใช่ 4 ตัวอย่างอิสระ
- ถ้า Core FAIL ให้หยุดและรายงานเหตุผล; ห้ามเปิด Range/เพิ่ม Indicator เพื่อกู้คะแนนแล้วเรียกว่า Core ผ่าน

## 9. Walk Forward Plan

ใช้ rolling train 24 เดือน → validation 6 เดือน → forward test 6 เดือน เลื่อนทีละ 6 เดือนเมื่อข้อมูลเพียงพอ. เลือกค่าจาก train+validation เท่านั้นก่อน forward แต่ละช่วง. เก็บทุก fold แม้ขาดทุน และ concatenate เฉพาะ forward returns ที่ไม่ซ้อนกัน

ในแต่ละ fold ใช้ configuration pool เดิม, cost model เดิม, risk เดิม, ไม่มีใช้ผล forward เลือก indicator/parameter ใหม่. รายงาน median PF, median equity DD, fraction positive folds, worst fold, parameter drift และความต่าง train/forward. เริ่มขั้นต่ำ 4 forward folds หากข้อมูลพอ; น้อยกว่านี้ระบุข้อจำกัด

Untouched OOS สุดท้ายต้องกันไว้จากการตัดสินออกแบบ/เลือก workflow. ถ้าใช้ช่วงใดปรับกลยุทธ์แล้ว ช่วงนั้นไม่ใช่ untouched OOS อีกต่อไป ต้องสร้าง holdout ใหม่ตามเวลาที่มีจริง

## 10. Monte Carlo Plan

Monte Carlo เป็นการทดสอบความไว ไม่ใช่พิสูจน์ว่าระบบไม่มีโอกาสล้างพอร์ต

- Export closed baskets พร้อมเวลาเริ่ม/จบ, net after actual costs, equity ก่อนเข้า, maximum adverse excursion, intrabasket equity path และ exposure; อย่าสุ่มแยก Grid levels เป็น trades อิสระ
- อย่างน้อย 5,000 paths, fixed seed เช่น 260913; จด distribution และ assumptions ก่อนดูผล
- Block bootstrap ตามสัปดาห์ หรือกลุ่มต่อเนื่อง 5–20 baskets เพื่อรักษา clustering; ทดสอบความไว block length แยก
- Shuffle closed baskets แบบง่ายรายงานเป็น diagnostic เพิ่ม แต่ไม่อ้างเป็น MC ของ Grid equity risk
- คิด sizing ใหม่ตาม equity, min lot/lot step, daily locks และ margin; ถ้าไม่มี tick replay ให้ระบุว่าขนาดบัญชีและ lock จำลองได้เพียง approximation
- Stress spread/commission 1.25×,1.5×,2×; latency/missed entries และ adverse gaps/slippage ใช้ distribution จาก broker หรือระบุ scenario สมมุติให้ชัด. ต้อง replay ticks/custom symbol เพื่อรักษาผลต่อ entry/regime/grid/stop ไม่ใช่หักกำไรปลายทางอย่างเดียว
- รายงาน median/95th/99th percentile max equity DD, P(final loss), P(DD≥12%), P(DD≥20%), stop-out probability และ confidence intervals
- นิยาม ruin สองแบบแยก: broker margin stop-out และ capital drawdown≥50%; ห้ามเรียก DD20% ว่าล้างพอร์ต
- เกณฑ์วิจัยตั้งต้น: baseline MC 95th DD<12%, P(DD≥20%)<1%, ไม่เกิด margin stop-out ใน sampled paths; ถ้าไม่ผ่าน FAIL/REVIEW ตามเหตุผล. ไม่มี stop-out ใน simulation ไม่ได้แปลว่าความน่าจะเป็นจริง=0

## 11. Known Weaknesses

1. EMA/ADX lag: Trend จบแล้ว Detector ยังบอก Trend ได้; Grid จะเพิ่ม Exposure ในช่วงเปลี่ยนทิศ
2. การถัวจำกัด risk ไม่ทำให้ expectancy บวกโดยตัวมันเอง; ต้องเปรียบเทียบกับ MaxGridLevels=1 ที่ risk เท่ากัน
3. Stop อาจโดนใน pullback ปกติ แล้วเกิด whipsaw หลาย Basket; daily loss เป็น guard ไม่ใช่ alpha
4. ATR/TP ปรับตามตลาดทำให้ target เคลื่อน และ expansion detector อาศัยแท่งปิด จึงไม่ทัน shock ภายในแท่ง; server SL รับหน้าที่หลัก
5. Session VWAP บน CFD ใช้ volume ของ broker และ bar approximation ไม่ใช่ volume รวมตลาดทอง; นโยบาย whole-day real volume fallback เปลี่ยนได้เมื่อแท่งใหม่ไม่มี real volume
6. จอง budget ทุกระดับแบบ conservative ทำให้ทุนเล็กมี lot=0 และจำนวน trade ต่ำ ซึ่งต้องรายงานตามจริง
7. Commission reserve ไม่ใช่ค่าธรรมเนียม settlement จริง; ตั้งต่ำเกินไปทำให้ประเมินกำไร/ความเสี่ยงดีเกินจริง
8. Stop gaps, requotes, partial fills, freeze/market closure ทำให้ loss เกินเพดานและ liquidation ใช้เวลานานได้
9. Global snapshot flush ตอน peak ใหม่อาจมี I/O overhead ใน live; ต้องวัด latency บน VPS. Tester แยก persistence จึงไม่วัดปัญหานี้
10. ไม่มี coordinated account-wide risk ระหว่างหลาย magic/terminal; 4 EA×1.5% ไม่ใช่ความเสี่ยงรวม1.5%
11. Account equity DD รวมกิจกรรมอื่นและ cashflows; v1 ไม่แยกเงินฝากถอนออกจาก daily baseline
12. DD re-arm วันใหม่หมายความว่า peak cap8% ไม่ใช่ total lifetime cap8%; ดู Tester entire-path DD เสมอ
13. News CSV ต้องตรวจ completeness เอง และ live calendar ต้องมีข้อมูล; NEWS_OFF ไม่ได้แปลว่าระบบหลบข่าว
14. Fault กรณี order rejected แม้ benign อาจทำให้หยุดทั้ง run โดยตั้งใจ conservative; ให้สอบสวนก่อนปรับ retry policy
15. ไม่มี basket export อัตโนมัติใน v1; Claude ต้องสร้าง postprocessor/harness จาก deals และ equity path เพื่อ WFA/MC ห้ามใช้เฉพาะ close P/L ประเมิน floating DD
16. พารามิเตอร์เป็นสมมติฐาน ไม่มีผลกำไรหรือ quant research validation ของชุดกฎนี้ในเวลาส่งมอบ

## 12. สิ่งที่ไม่ควร Optimize

Risk limits, lot escalation (ไม่มี), Magic, digits/point/tick/volume step, commission/slippage reserve, timezone/DST, data coverage, minimum sample threshold, pass/fail gate, MC seed เพื่อเลือกผลสวย, news schedule, enable/disable risk, warm-up, source timeframe และ broker identity

อย่า Optimize ทั้งหมดพร้อมกัน. EMA50/200, ATR14, ADX14, Pullback band, Range oscillation และ expansion constants ให้ตรึงใน core evaluation; การแก้ถือเป็น strategy revision ต้อง version และเปิด OOS ใหม่ ห้ามไล่ตัวเลข 0.01 เพื่อ Perfect Number
