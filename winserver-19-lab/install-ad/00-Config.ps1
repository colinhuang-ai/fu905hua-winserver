# ==============================================================================
# 00-Config.ps1 - Cấu hình tập trung cho Active Directory Domain iai.io.vn
# ==============================================================================

$global:ADConfig = @{
    # --- Thông tin Domain ---
    DomainName              = "iai.io.vn"
    NetbiosName             = "IAI"
    ForestMode              = "WinThreshold"   # Tương thích Windows Server 2016 / 2019
    DomainMode              = "WinThreshold"

    # --- Mật khẩu khôi phục DSRM (Directory Services Restore Mode) ---
    # Lưu ý: Mật khẩu cần thỏa mãn độ phức tạp (chữ hoa, chữ thường, số, ký tự đặc biệt)
    DSRMPassword            = "IAI@Admin2026!"

    # --- Cấu trúc Organizational Unit (OU) ---
    TopOUName               = "IAI_Corp"
    AdminsOUName            = "Admins"
    UsersOUName             = "Users"
    GroupsOUName            = "Groups"

    # --- Mật khẩu khởi tạo mặc định cho người dùng quản trị ---
    DefaultUserPassword     = "IAI@Admin2026!"
    PasswordNeverExpires    = $true            # Phù hợp môi trường Lab / Test

    # --- Danh sách các nhóm quản trị hệ thống gán cho các Admin ---
    AdminGroups             = @(
        "Domain Admins",
        "Enterprise Admins",
        "Schema Admins",
        "Administrators",
        "Group Policy Creator Owners"
    )

    # --- Danh sách 2 tài khoản quản trị viên cần khởi tạo ---
    AdminUsers              = @(
        @{
            SamAccountName  = "hoangpt"
            GivenName       = "PT"
            Surname         = "Hoang"
            DisplayName     = "Hoang PT"
            Description     = "Domain Administrator - Primary IT Admin"
            Title           = "System Administrator"
            Department      = "IT Infrastructure"
            Email           = "hoangpt@iai.io.vn"
        },
        @{
            SamAccountName  = "hoangxuan"
            GivenName       = "Xuan"
            Surname         = "Hoang"
            DisplayName     = "Hoang Xuan"
            Description     = "Domain Administrator - Secondary IT Admin"
            Title           = "System Administrator"
            Department      = "IT Infrastructure"
            Email           = "hoangxuan@iai.io.vn"
        }
    )
}

function Write-ADLog {
    param (
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    switch ($Level) {
        "INFO"    { Write-Host "[$timestamp] [INFO] $Message" -ForegroundColor Cyan }
        "SUCCESS" { Write-Host "[$timestamp] [SUCCESS] $Message" -ForegroundColor Green }
        "WARN"    { Write-Host "[$timestamp] [WARN] $Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "[$timestamp] [ERROR] $Message" -ForegroundColor Red }
    }
}
