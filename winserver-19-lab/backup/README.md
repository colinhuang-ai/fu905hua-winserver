# Sao Lưu & Phục Hồi Active Directory `iai.io.vn`

Bộ script sao lưu toàn bộ dịch vụ Active Directory trên Domain Controller Windows Server 2019.

> **Chạy ở đâu:** trực tiếp **trên máy Domain Controller**, bằng PowerShell **Run as Administrator**. Script sẽ tự kiểm tra quyền, module `ActiveDirectory` và dịch vụ `NTDS` trước khi bắt đầu.

---

## 1. Script sao lưu những gì

| # | Thành phần | Công cụ | Dùng để làm gì |
| :-- | :--- | :--- | :--- |
| 1 | **System State** | `wbadmin` | **Quan trọng nhất.** Bản sao lưu chính thức của Microsoft: NTDS.dit, SYSVOL, registry, COM+, boot files. Đây là thứ duy nhất phục hồi lại được cả Domain Controller. |
| 2 | **IFM snapshot** | `ntdsutil ifm` | Bản sao NTDS.dit + registry độc lập, không cần Windows Server Backup. Dùng để dựng DC mới nhanh hoặc soi database offline. |
| 3 | **LDIF export** | `ldifde` | File text chứa từng đối tượng — phục hồi lẻ 1 user/group/OU bị xoá nhầm. |
| 4 | **CSV export** | AD cmdlets | users, groups, group-membership, OUs, computers — mở bằng Excel để đối chiếu. |
| 5 | **Group Policy** | `Backup-GPO` | Toàn bộ GPO + báo cáo HTML + **bảng link GPO vào OU** (`Backup-GPO` không tự lưu phần link này). |
| 6 | **DNS zones** | `Export-DnsServerZone` | Từng zone + danh sách forwarder. |
| 7 | **SYSVOL** | `robocopy /MIR` | Logon script, policy files (bản copy đọc được ngay, không cần giải nén System State). |
| 8 | **Metadata** | `dcdiag`, `repadmin`, `netdom` | FSMO roles, schema version, tombstone lifetime, sức khoẻ replication. |

---

## 2. Cách chạy

**Cách 1 — menu:** chuột phải `RUN-BACKUP.cmd` → **Run as administrator**.

**Cách 2 — PowerShell (Administrator):**

```powershell
cd C:\Training\Windows19S\winserver-19-lab\backup
Set-ExecutionPolicy RemoteSigned -Scope Process -Force

.\01-Backup-AD.ps1                              # đầy đủ, tự chọn ổ đĩa
.\01-Backup-AD.ps1 -BackupRoot "E:\AD-Backup"   # chỉ định nơi lưu
.\01-Backup-AD.ps1 -SkipSystemState             # nhanh, chỉ vài phút
.\01-Backup-AD.ps1 -Compress                    # nén kết quả thành .zip
.\01-Backup-AD.ps1 -RetentionDays 30            # giữ bản cũ 30 ngày
```

### Tham số

| Tham số | Mặc định | Ý nghĩa |
| :--- | :--- | :--- |
| `-BackupRoot` | tự chọn | Thư mục gốc. Để trống: script chọn ổ NTFS cố định **khác ổ hệ thống**, còn nhiều dung lượng nhất; không có thì dùng `C:\AD-Backup`. |
| `-RetentionDays` | `14` | Xoá thư mục sao lưu cũ hơn N ngày. `0` = không xoá. |
| `-KeepSystemStateVersions` | `3` | Số bản System State giữ lại trong kho `wbadmin`. |
| `-SkipSystemState` | tắt | Bỏ qua bước lâu nhất. **Lưu ý:** không có bản này thì không dựng lại được DC. |
| `-Compress` | tắt | Nén thành `.zip` (bỏ qua nếu thư mục > 1.5 GB — giới hạn của PowerShell 5.1). |

**Mã thoát:** `0` = thành công, `2` = bước quan trọng thất bại, `1` = không đủ điều kiện chạy. Tiện cho Scheduled Task.

---

## 3. Kết quả tạo ra

```
E:\AD-Backup\
├── 20260920-153000\                 <- mỗi lần chạy 1 thư mục theo dấu thời gian
│   ├── backup.log                   transcript đầy đủ
│   ├── manifest.json                tóm tắt từng bước + thời gian + trạng thái
│   ├── wbadmin-systemstate.txt
│   ├── ntds-ifm\Active Directory\ntds.dit
│   ├── ldif\        full-domain.ldf, users.ldf, groups.ldf, ous.ldf, ...
│   ├── csv\         users.csv, groups.csv, group-membership.csv, ous.csv
│   ├── gpo\         {GUID}\, all-gpo-report.html, gpo-links.csv
│   ├── dns\         backup_iai.io.vn.dns, zones.csv, forwarders.txt
│   ├── sysvol\      bản mirror của C:\Windows\SYSVOL\domain
│   └── metadata\    domain-info.json, dcdiag.txt, repadmin-showrepl.txt, fsmo.txt
└── WindowsImageBackup\              <- System State do wbadmin quản lý (ngoài thư mục trên)
```

`WindowsImageBackup` nằm ở **gốc ổ đĩa**, không nằm trong thư mục dấu thời gian — đó là cách `wbadmin` hoạt động, không đổi được. Khi chép bản sao lưu sang nơi khác, nhớ chép **cả hai**.

---

## 4. Phục hồi

Dùng [02-Restore-AD.ps1](02-Restore-AD.ps1) — hoặc chuột phải `RUN-RESTORE.cmd` → **Run as administrator**. Script chạy theo `-Mode`, mặc định là `List` (chỉ xem, không thay đổi gì).

| Tình huống | Lệnh |
| :--- | :--- |
| Xem có những bản sao lưu nào | `.\02-Restore-AD.ps1 -Mode List` |
| Xoá nhầm user/group (đã bật Recycle Bin) | `.\02-Restore-AD.ps1 -Mode RecycleBin -Identity hoangpt` |
| Xoá nhầm, chưa bật Recycle Bin | `.\02-Restore-AD.ps1 -Mode Objects -Identity hoangpt` |
| Mất thành viên nhóm | `.\02-Restore-AD.ps1 -Mode Membership` |
| Hỏng / xoá GPO | `.\02-Restore-AD.ps1 -Mode GPO -RelinkGpo` |
| Mất DNS zone | `.\02-Restore-AD.ps1 -Mode DNS` |
| Mất logon script trong SYSVOL | `.\02-Restore-AD.ps1 -Mode SYSVOL` |
| Hỏng cả Domain Controller | `.\02-Restore-AD.ps1 -Mode SystemState` *(cần DSRM)* |
| Ép 1 nhánh OU thắng replication | `.\02-Restore-AD.ps1 -Mode Authoritative -Subtree "OU=IAI_Corp,DC=iai,DC=io,DC=vn"` *(cần DSRM)* |

**Mọi mode đều hỗ trợ `-WhatIf`** để xem trước script sẽ làm gì mà không thay đổi gì:

```powershell
.\02-Restore-AD.ps1 -Mode Membership -WhatIf
```

Các bước phá huỷ (ghi đè System State, `/MIR` lên SYSVOL, authoritative restore, reboot vào DSRM) đều bắt **gõ đúng một chuỗi xác nhận** (`RESTORE`, `MIRROR`, `AUTHORITATIVE`, `REBOOT`) — gõ sai là huỷ. `-Force` bỏ qua các xác nhận này, chỉ dùng khi tự động hoá.

Tham số khác: `-BackupPath` chọn bản sao lưu cụ thể (mặc định lấy bản mới nhất), `-LdifFile` chọn file LDIF, `-GpoName` giới hạn GPO cần phục hồi.

Phần dưới đây là **các lệnh thủ công tương ứng**, để hiểu script đang làm gì và để xử lý khi script không chạy được.

### 4.1. Xoá nhầm 1 user / group — dùng AD Recycle Bin (nhanh nhất)

Nếu Recycle Bin đã bật (xem `metadata\domain-info.json`, khoá `RecycleBinEnabled`):

```powershell
Get-ADObject -Filter 'Name -like "*hoangpt*"' -IncludeDeletedObjects |
    Restore-ADObject
```

Bật Recycle Bin (nên làm ngay, **không thể tắt lại**):

```powershell
Enable-ADOptionalFeature 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target iai.io.vn
```

### 4.2. Xoá nhầm nhưng Recycle Bin chưa bật — import lại từ LDIF

```powershell
ldifde -i -f E:\AD-Backup\20260920-153000\ldif\users.ldf -j C:\Temp
```

> **Mật khẩu không nằm trong file LDIF.** Sau khi import phải đặt lại mật khẩu và bật tài khoản:
> ```powershell
> Set-ADAccountPassword -Identity hoangpt -Reset -NewPassword (ConvertTo-SecureString "IAI@Admin2026!" -AsPlainText -Force)
> Enable-ADAccount -Identity hoangpt
> ```
> Và gán lại nhóm theo `csv\group-membership.csv` (thuộc tính `memberOf` bị loại khỏi LDIF vì không import trực tiếp được).

### 4.3. Phục hồi 1 GPO

```powershell
Import-Module GroupPolicy
Restore-GPO -Name "Ten GPO" -Path E:\AD-Backup\20260920-153000\gpo
```

Link lại GPO vào OU theo `gpo\gpo-links.csv`:

```powershell
New-GPLink -Name "Ten GPO" -Target "OU=IAI_Corp,DC=iai,DC=io,DC=vn"
```

### 4.4. Phục hồi toàn bộ Domain Controller (non-authoritative)

1. Khởi động lại máy → bấm `F8` (hoặc `bcdedit /set safeboot dsrepair` rồi reboot) → chọn **Directory Services Restore Mode (DSRM)**.
2. Đăng nhập bằng tài khoản **`.\Administrator`** với **mật khẩu DSRM** — trong lab này là giá trị `DSRMPassword` trong [00-Config.ps1](../install-ad/00-Config.ps1) (`IAI@Admin2026!`).
3. Xem danh sách bản sao lưu và phục hồi:
   ```cmd
   wbadmin get versions
   wbadmin start systemstaterecovery -version:09/20/2026-15:30 -quiet
   ```
4. Reboot bình thường (`bcdedit /deletevalue safeboot` nếu đã dùng lệnh ở bước 1).

### 4.5. Phục hồi *authoritative* (ép bản sao lưu ghi đè lên DC khác)

Chỉ dùng khi có nhiều DC và cần ép object/SYSVOL cũ thắng replication. Sau bước 4.4, **vẫn đang trong DSRM**:

```cmd
ntdsutil
  activate instance ntds
  authoritative restore
  restore subtree "OU=IAI_Corp,DC=iai,DC=io,DC=vn"
  quit
  quit
```

Rồi mới reboot ra chế độ thường.

---

## 5. Chạy tự động hằng ngày

Tạo Scheduled Task chạy 2 giờ sáng mỗi ngày, dưới quyền `SYSTEM`:

```powershell
$action  = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\Training\Windows19S\winserver-19-lab\backup\01-Backup-AD.ps1" -RetentionDays 14'
$trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM
$set     = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 4)
Register-ScheduledTask -TaskName "AD-Backup-iai.io.vn" -Action $action -Trigger $trigger `
    -Settings $set -User "SYSTEM" -RunLevel Highest -Description "Sao luu toan bo AD iai.io.vn"
```

Kiểm tra lần chạy gần nhất:

```powershell
Get-ScheduledTaskInfo -TaskName "AD-Backup-iai.io.vn"
```

---

## 6. Những điểm cần lưu ý

- **Tombstone lifetime (180 ngày).** Bản sao lưu AD cũ hơn giá trị này (xem `metadata\domain-info.json`) là **vô dụng** — không được phép phục hồi. Luôn giữ ít nhất một bản mới hơn 180 ngày.
- **Mật khẩu DSRM là bắt buộc** để phục hồi System State. Nếu quên, đặt lại trước khi có sự cố: `ntdsutil "set dsrm password" "reset password on server null"`.
- **Lab chỉ có 1 DC** là điểm chết duy nhất. Với môi trường thật, thêm DC thứ hai quan trọng hơn mọi lịch backup.
- **Bản sao lưu nằm trên cùng máy chủ thì không cứu được khi máy hỏng ổ cứng.** Nên chép thư mục `AD-Backup` và `WindowsImageBackup` sang NAS/ổ ngoài định kỳ.
- **File `csv\users.csv` và `ldif\*.ldf` chứa thông tin tài khoản** — đặt quyền NTFS hạn chế trên thư mục sao lưu, chỉ cho `Domain Admins` đọc.
- Nếu bản sao lưu ghi vào **cùng ổ hệ thống (C:)**, script tự bật khoá registry `AllowSSBToAnyVolume`. Đây là cấu hình Microsoft không khuyến nghị cho production — hãy gắn thêm một ổ đĩa riêng cho DC.
