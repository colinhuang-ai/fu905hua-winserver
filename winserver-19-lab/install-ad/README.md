# Hướng Dẫn Cài Đặt Active Directory Domain Server: `iai.io.vn`

Tài liệu và bộ kịch bản (PowerShell scripts) tự động hoá việc cài đặt, nâng cấp Domain Controller cho domain **`iai.io.vn`** trên **Windows Server 2019**, đồng thời khởi tạo cấu trúc phòng ban (OU) và 2 tài khoản quản trị viên: **`hoangpt`** và **`hoangxuan`** với đầy đủ quyền quản trị Domain Admins.

---

## 1. Thông Tin Cấu Hình Hệ Thống

| Tham số | Giá trị |
| :--- | :--- |
| **Domain FQDN** | `iai.io.vn` |
| **Domain NetBIOS** | `IAI` |
| **Forest / Domain Mode** | Windows Server 2016 / 2019 (`WinThreshold`) |
| **Cấu trúc OU** | `OU=IAI_Corp,DC=iai,DC=io,DC=vn`<br>├── `OU=Admins`<br>├── `OU=Users`<br>└── `OU=Groups` |
| **Tài khoản Admin 1** | Username: `hoangpt`<br>UPN: `hoangpt@iai.io.vn`<br>Logon: `IAI\hoangpt` |
| **Tài khoản Admin 2** | Username: `hoangxuan`<br>UPN: `hoangxuan@iai.io.vn`<br>Logon: `IAI\hoangxuan` |
| **Nhóm quyền gán** | `Domain Admins`, `Enterprise Admins`, `Schema Admins`, `Administrators` |
| **Mật khẩu khởi tạo** | `IAI@Admin2026!` *(có thể thay đổi trong `00-Config.ps1`)* |

---

## 2. Danh Sách Các Kịch Bản (Scripts)

Thư mục `c:\Training\Windows19S\winserver-19-lab\` gồm các tệp sau:

* [00-Config.ps1](file:///c:/Training/Windows19S/winserver-19-lab/00-Config.ps1): File cấu hình tập trung lưu tên miền, mật khẩu mặc định, danh sách OUs và người dùng.
* [01-Install-ADDS.ps1](file:///c:/Training/Windows19S/winserver-19-lab/01-Install-ADDS.ps1): Cài đặt vai trò AD DS, RSAT, DNS và thăng cấp máy chủ thành Domain Controller (tự động reboot khi xong).
* [02-Init-AdminUsers.ps1](file:///c:/Training/Windows19S/winserver-19-lab/02-Init-AdminUsers.ps1): Tạo cấu trúc OU và khởi tạo 2 tài khoản admin `hoangpt`, `hoangxuan`, gán vào các nhóm quản trị cao nhất.
* [03-Verify-AD.ps1](file:///c:/Training/Windows19S/winserver-19-lab/03-Verify-AD.ps1): Kiểm tra toàn diện dịch vụ AD, DNS, FSMO roles và quyền hạn của 2 user.

---

## 3. Các Bước Thực Hiện Chi Tiết

### Chuẩn bị trước khi chạy:
1. Đảm bảo máy Windows Server 2019 đã được đặt **IP Tĩnh (Static IP)** (Ví dụ: `10.20.20.10/24` hoặc dải mạng tương ứng trong mạng của bạn).
2. Đặt Computer Name rõ ràng (ví dụ: `DC01` hoặc `IAI-DC01`).
3. Mở **PowerShell với quyền Administrator** (`Run as Administrator`).

---

### Bước 1: Điều chỉnh cấu hình (Nếu cần)
Nếu bạn muốn đổi mật khẩu DSRM hoặc mật khẩu mặc định của 2 admin, mở tệp `00-Config.ps1`:
```powershell
notepad C:\Training\Windows19S\winserver-19-lab\00-Config.ps1
```
*Lưu ý: Mật khẩu phải có độ dài tối thiểu 8 ký tự, gồm chữ hoa, chữ thường, số và ký tự đặc biệt.*

---

### Bước 2: Cài đặt AD DS và nâng cấp Domain Controller
Trong cửa sổ PowerShell (Administrator), di chuyển vào thư mục và chạy:
```powershell
cd C:\Training\Windows19S\winserver-19-lab
Set-ExecutionPolicy RemoteSigned -Scope Process -Force
.\01-Install-ADDS.ps1
```

* Script sẽ tự động:
  - Cài đặt tính năng `AD-Domain-Services`, `DNS`, `RSAT-ADDS`.
  - Khởi tạo Forest mới `iai.io.vn` với NetBIOS `IAI`.
  - Cấu hình DNS Server tích hợp.
  - Sau khi hoàn tất (mất khoảng 2-5 phút), máy chủ sẽ **tự động khởi động lại (Reboot)**.

---

### Bước 3: Đăng nhập và Khởi tạo 2 User Admin
Sau khi máy chủ khởi động lại:
1. Đăng nhập vào màn hình Windows Server bằng tài khoản Domain Administrator:
   - Tên đăng nhập: `IAI\Administrator` (hoặc `Administrator@iai.io.vn`)
   - Mật khẩu: Mật khẩu quản trị viên cũ của máy local trước khi nâng cấp.
2. Mở **PowerShell (Run as Administrator)** và chạy:
```powershell
cd C:\Training\Windows19S\winserver-19-lab
Set-ExecutionPolicy RemoteSigned -Scope Process -Force
.\02-Init-AdminUsers.ps1
```

* Script sẽ:
  - Tạo cấu trúc OU: `OU=IAI_Corp` -> `OU=Admins`, `OU=Users`, `OU=Groups`.
  - Tạo user `hoangpt` với UPN `hoangpt@iai.io.vn`.
  - Tạo user `hoangxuan` với UPN `hoangxuan@iai.io.vn`.
  - Gán cả 2 user vào: `Domain Admins`, `Enterprise Admins`, `Schema Admins`, `Administrators`.
  - Kích hoạt tài khoản và thiết lập mật khẩu ban đầu (`IAI@Admin2026!`).

---

### Bước 4: Kiểm tra và xác minh hệ thống
Chạy script xác minh:
```powershell
.\03-Verify-AD.ps1
```

Kết quả sẽ hiển thị:
- Trạng thái 6 dịch vụ cốt lõi: `NTDS`, `DNS`, `ADWS`, `KDC`, `Netlogon`, `W32Time`.
- Thông tin Domain, Forest, 5 FSMO Roles.
- Phân giải bản ghi DNS A (`iai.io.vn`) và SRV (`_ldap`, `_kerberos`).
- Thông tin chi tiết và danh sách nhóm quyền hạn của `hoangpt` và `hoangxuan`.

---

## 4. Kiểm Tra Đăng Nhập & Tham Gia Domain (Join Domain)

### Đăng nhập trực tiếp hoặc qua RDP:
- Định dạng 1: `hoangpt@iai.io.vn` | Pass: `IAI@Admin2026!`
- Định dạng 2: `IAI\hoangpt`        | Pass: `IAI@Admin2026!`
- Tương tự với tài khoản `hoangxuan`.

### Gia nhập máy trạm (Windows 10/11 Client) vào Domain `iai.io.vn`:
1. Trên máy trạm Client, cấu hình địa chỉ **Preferred DNS Server** trỏ về địa chỉ IP của máy chủ Domain Controller `iai.io.vn`.
2. Mở `sysdm.cpl` (System Properties) -> Tab **Computer Name** -> Nhấn **Change...**
3. Chọn mục **Domain**, nhập: `iai.io.vn`.
4. Nhập tài khoản và mật khẩu của `hoangpt` hoặc `hoangxuan` để ủy quyền gia nhập domain.
5. Khởi động lại máy trạm và đăng nhập với tài khoản domain.
