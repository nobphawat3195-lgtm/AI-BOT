# แก้ปัญหาติดตั้ง Claude Desktop บน Windows ไม่ได้

บันทึกวิธีแก้อาการที่ตัวติดตั้ง Claude Desktop ขึ้นหน้าต่าง **Claude Setup** พร้อมข้อความ:

```
Installation failed: AddPackage failed: AddPackage failed with HRESULT 0x80073CF9
Please share this log with us.
The log file will be opened in Explorer.
```

---

## สาเหตุ

`0x80073CF9` คือ `ERROR_INSTALL_FAILED` ของระบบติดตั้งแอปแบบ **MSIX/AppX** ของ Windows
ตัวติดตั้ง Claude Desktop บน Windows ใช้กลไกนี้ ดังนั้น error นี้แปลว่า **Windows ปฏิเสธการลงทะเบียนแพ็กเกจ**
ไม่ใช่ว่าไฟล์ติดตั้งของ Claude เสีย และไม่ใช่บั๊กของตัวแอปเอง

สาเหตุที่พบบ่อย เรียงตามความน่าจะเป็น:

| # | สาเหตุ | อาการ/หมายเหตุ |
|---|--------|----------------|
| 1 | โฟลเดอร์ `%LOCALAPPDATA%\Packages` หรือ `C:\Program Files\WindowsApps\Deleted` หายไป หรือสิทธิ์เพี้ยน | ต้นเหตุอันดับหนึ่งของ `0x80073CF9` |
| 2 | Windows ถูกตั้งให้ลงแอปจาก Microsoft Store เท่านั้น | ตัวติดตั้งภายนอกถูกบล็อกตั้งแต่ต้น |
| 3 | บริการ `AppXSvc` / `AppReadiness` / `StateRepository` ถูกปิด | มักเกิดหลังใช้ tweak/debloat script |
| 4 | พื้นที่ดิสก์ไม่พอ หรือแอนตี้ไวรัสบล็อก | |
| 5 | คอมโพเนนต์ระบบของ Windows เสียหาย | ต้องซ่อมด้วย DISM/SFC |

---

## วิธีแก้ ไล่ตามลำดับ

### 1. เปิดให้ติดตั้งแอปจากที่อื่นได้

`Settings` → `Apps` → `Advanced app settings` → **Choose where to get apps** ตั้งเป็น **Anywhere**

### 2. สร้างโฟลเดอร์ที่หายกลับมา

เปิด **PowerShell แบบ Run as Administrator** แล้วรัน:

```powershell
New-Item -ItemType Directory -Force -Path "$env:LOCALAPPDATA\Packages"
New-Item -ItemType Directory -Force -Path "C:\Program Files\WindowsApps\Deleted"
```

จากนั้นลองติดตั้งใหม่ — หลายเคสจบตรงขั้นนี้

### 3. ตรวจว่าบริการที่จำเป็นทำงานอยู่

```powershell
Get-Service AppXSvc, AppReadiness, StateRepository | Select-Object Name, Status, StartType
Start-Service AppXSvc
```

ทั้งสามตัวควรมีสถานะ `Running` (หรืออย่างน้อย `StartType` ไม่ใช่ `Disabled`)

### 4. ซ่อมคอมโพเนนต์ Windows

ใช้เวลาสักพัก และควร **restart** เครื่องหลังรันเสร็จ:

```powershell
DISM /Online /Cleanup-Image /RestoreHealth
sfc /scannow
wsreset.exe
```

### 5. ตรวจพื้นที่ว่างและแอนตี้ไวรัส

- ไดรฟ์ `C:` ควรเหลืออย่างน้อย ~5 GB
- ปิดแอนตี้ไวรัสตัวที่ติดตั้งเพิ่ม (ไม่ใช่ Defender) ชั่วคราวระหว่างติดตั้ง

### 6. ติดตั้งจากโฟลเดอร์ในเครื่อง

ย้ายไฟล์ติดตั้งไปที่ `C:\Users\<ชื่อผู้ใช้>\Downloads` ที่ **ไม่ได้ sync กับ OneDrive**
แล้วคลิกขวา → **Run as administrator**

---

## ถ้ายังไม่หาย: อ่าน log

หน้าต่าง error บอกว่า *"The log file will be opened in Explorer"* — ในไฟล์นั้นจะมี error code
ตัวจริงที่ละเอียดกว่า ให้มองหาบรรทัดที่มีคำว่า `error` หรือ `failed` แล้วใช้ code นั้นค้นหาต่อ

---

## ทางเลี่ยงระหว่างที่ยังแก้ไม่ได้

- ใช้ Claude ผ่านเบราว์เซอร์ที่ <https://claude.ai> — ฟีเจอร์แชทครบเหมือนกัน
  ต่างแค่ส่วนที่เข้าถึงไฟล์และแอปในเครื่อง
- ใช้ Claude Code ผ่าน terminal หรือ VS Code extension แทน
