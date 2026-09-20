# ==============================================================================
# 02-Init-AdminUsers.ps1 - Khoi tao cau truc OU va 2 User Admin: hoangpt, hoangxuan
# ==============================================================================
#requires -Version 5.1

[CmdletBinding()]
param (
    [string]$PasswordOverride
)

# 1. Kiem tra quyen Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Script nay yeu cau chay voi quyen Administrator (Run as Administrator)!"
    exit 1
}

# 2. Nap file cau hinh
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configFile = Join-Path $scriptDir "00-Config.ps1"
if (-not (Test-Path $configFile)) {
    Write-Error "Khong tim thay file cau hinh: $configFile"
    exit 1
}
. $configFile

Write-ADLog "=== BAT DAU KHOI TAO NGUOI DUNG QUAN TRI CHO DOMAIN: $($global:ADConfig.DomainName) ===" "INFO"

# 3. Kiem tra module ActiveDirectory
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-ADLog "Khong the nap module ActiveDirectory. May chu da duoc nang cap len Domain Controller chua?" "ERROR"
    Write-ADLog "Chi tiet loi: $_" "ERROR"
    exit 1
}

# 4. Kiem tra ket noi den Domain
try {
    $currentDomain = Get-ADDomain -Identity $global:ADConfig.DomainName -ErrorAction Stop
    $domainDN = $currentDomain.DistinguishedName
    Write-ADLog "Ket noi thanh cong den Domain: $($currentDomain.DNSRoot) ($domainDN)" "SUCCESS"
} catch {
    Write-ADLog "Khong the truy van thong tin Domain '$($global:ADConfig.DomainName)'. Vui long dam bao may da reboot xong sau buoc 01!" "ERROR"
    exit 1
}

# 5. Khoi tao cau truc Organizational Unit (OU)
# CSDL: OU=IAI_Corp,DC=iai,DC=io,DC=vn -> Admins, Users, Groups
$topOUPath = $domainDN
$topOUName = $global:ADConfig.TopOUName
$topOUDN   = "OU=$topOUName,$domainDN"

function Ensure-ADOU {
    param (
        [string]$Name,
        [string]$Path
    )
    $ouDN = "OU=$Name,$Path"
    try {
        $null = Get-ADOrganizationalUnit -Identity $ouDN -ErrorAction Stop
        Write-ADLog "OU '$ouDN' da ton tai." "INFO"
    } catch {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $false -ErrorAction Stop | Out-Null
        Write-ADLog "Da tao moi OU: '$ouDN'" "SUCCESS"
    }
}

Write-ADLog "Kiem tra / Khoi tao cay Organizational Unit..." "INFO"
Ensure-ADOU -Name $topOUName -Path $topOUPath
Ensure-ADOU -Name $global:ADConfig.AdminsOUName -Path $topOUDN
Ensure-ADOU -Name $global:ADConfig.UsersOUName -Path $topOUDN
Ensure-ADOU -Name $global:ADConfig.GroupsOUName -Path $topOUDN

$adminsOUDN = "OU=$($global:ADConfig.AdminsOUName),$topOUDN"

# 6. Thiet lap mat khau cho User
$rawPassword = if ($PasswordOverride) { $PasswordOverride } else { $global:ADConfig.DefaultUserPassword }
$secPassword = ConvertTo-SecureString $rawPassword -AsPlainText -Force

# 7. Khoi tao tung User Admin va gan vao cac nhom dac quyen
foreach ($user in $global:ADConfig.AdminUsers) {
    $sam = $user.SamAccountName
    $upn = "$sam@$($global:ADConfig.DomainName)"
    Write-ADLog "------------------------------------------------------------" "INFO"
    Write-ADLog "Xu ly tai khoan admin: $sam ($($user.DisplayName))" "INFO"

    $existingUser = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue

    if (-not $existingUser) {
        Write-ADLog "Tao moi tai khoan '$sam' trong OU '$adminsOUDN'..." "INFO"
        $newParams = @{
            SamAccountName        = $sam
            UserPrincipalName     = $upn
            Name                  = $user.DisplayName
            DisplayName           = $user.DisplayName
            GivenName             = $user.GivenName
            Surname               = $user.Surname
            Description           = $user.Description
            Title                 = $user.Title
            Department            = $user.Department
            EmailAddress          = $user.Email
            Path                  = $adminsOUDN
            AccountPassword       = $secPassword
            Enabled               = $true
            PasswordNeverExpires  = $global:ADConfig.PasswordNeverExpires
            CannotChangePassword  = $false
        }

        try {
            New-ADUser @newParams -ErrorAction Stop
            Write-ADLog "Tao thanh cong tai khoan: $sam ($upn)" "SUCCESS"
        } catch {
            Write-ADLog "Loi khi tao tai khoan $sam : $_" "ERROR"
            continue
        }
    } else {
        Write-ADLog "Tai khoan '$sam' da ton tai. Cap nhat trang thai kich hoat va mat khau..." "WARN"
        Set-ADUser -Identity $sam -Enabled $true -PasswordNeverExpires $global:ADConfig.PasswordNeverExpires
        Set-ADAccountPassword -Identity $sam -NewPassword $secPassword -Reset
        Write-ADLog "Da reset mat khau va dam bao kich hoat cho $sam." "SUCCESS"
    }

    # 8. Them vao cac nhom Administrator
    Write-ADLog "Phan quyen cac nhom quan tri cho '$sam'..." "INFO"
    foreach ($grpName in $global:ADConfig.AdminGroups) {
        try {
            $groupObj = Get-ADGroup -Identity $grpName -ErrorAction SilentlyContinue
            if ($groupObj) {
                # Kiem tra neu user da trong nhom chua
                $members = Get-ADGroupMember -Identity $grpName | Select-Object -ExpandProperty SamAccountName
                if ($members -notcontains $sam) {
                    Add-ADGroupMember -Identity $grpName -Members $sam -ErrorAction Stop
                    Write-ADLog "  + Da them '$sam' vao nhom: [$grpName]" "SUCCESS"
                } else {
                    Write-ADLog "  = '$sam' da thuoc nhom: [$grpName]" "INFO"
                }
            } else {
                Write-ADLog "  ! Nhom '$grpName' khong ton tai tren he thong." "WARN"
            }
        } catch {
            Write-ADLog "  - Khong the them vao nhom $grpName : $_" "WARN"
        }
    }
}

Write-ADLog "============================================================" "SUCCESS"
Write-ADLog "HOAN TAT KHOI TAO 2 TAI KHOAN QUAN TRI ACTIVE DIRECTORY!" "SUCCESS"
Write-ADLog "============================================================" "SUCCESS"
Write-Host ""
Write-Host "THONG TIN DANG NHAP CUA 2 ADMIN:" -ForegroundColor Yellow
foreach ($user in $global:ADConfig.AdminUsers) {
    Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Account:          $($user.SamAccountName)" -ForegroundColor White
    Write-Host "Full Name:        $($user.DisplayName)" -ForegroundColor White
    Write-Host "UPN (Login 1):    $($user.SamAccountName)@$($global:ADConfig.DomainName)" -ForegroundColor Green
    Write-Host "Domain (Login 2): $($global:ADConfig.NetbiosName)\$($user.SamAccountName)" -ForegroundColor Green
    Write-Host "Default Password: $rawPassword" -ForegroundColor Yellow
}
Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "Ban co the dang nhap ngay qua RDP hoac Console voi cac tai khoan tren!" -ForegroundColor Cyan
