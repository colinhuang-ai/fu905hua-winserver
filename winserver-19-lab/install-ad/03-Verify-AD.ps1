# ==============================================================================
# 03-Verify-AD.ps1 - Kiem tra trang thai hoat dong cua AD Domain Server iai.io.vn
# ==============================================================================
#requires -Version 5.1

# 1. Nap file cau hinh
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configFile = Join-Path $scriptDir "00-Config.ps1"
if (-not (Test-Path $configFile)) {
    Write-Error "Khong tim thay file cau hinh: $configFile"
    exit 1
}
. $configFile

Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "     KIEM TRA TRANG THAI ACTIVE DIRECTORY DOMAIN: $($global:ADConfig.DomainName)" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor DarkCyan

# 2. Kiem tra cac Windows Services quan trong
Write-Host "`n[1/5] KIEM TRA CAC DICH VU CORE CUA ACTIVE DIRECTORY & DNS:" -ForegroundColor Yellow
$services = @("NTDS", "DNS", "ADWS", "KDC", "Netlogon", "W32Time")
$allServicesOk = $true
foreach ($svc in $services) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        if ($s.Status -eq "Running") {
            Write-Host "  [OK] Dich vu $($svc.PadRight(12)) : DANG CHAY ($($s.Status))" -ForegroundColor Green
        } else {
            Write-Host "  [CANH BAO] Dich vu $($svc.PadRight(12)) : $($s.Status)" -ForegroundColor Red
            $allServicesOk = $false
        }
    } else {
        Write-Host "  [ERROR] Khong tim thay dich vu: $svc" -ForegroundColor Red
        $allServicesOk = $false
    }
}

# 3. Kiem tra Domain va Forest qua ActiveDirectory Module
Write-Host "`n[2/5] KIEM TRA THONG TIN DOMAIN VA FOREST:" -ForegroundColor Yellow
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $domain = Get-ADDomain -Identity $global:ADConfig.DomainName
    $forest = Get-ADForest -Identity $global:ADConfig.DomainName
    
    Write-Host "  Domain Name:            $($domain.DNSRoot)" -ForegroundColor White
    Write-Host "  NetBIOS Name:           $($domain.NetBIOSName)" -ForegroundColor White
    Write-Host "  Domain Mode:            $($domain.DomainMode)" -ForegroundColor White
    Write-Host "  Forest Mode:            $($forest.ForestMode)" -ForegroundColor White
    Write-Host "  PDC Emulator:           $($domain.PDCEmulator)" -ForegroundColor White
    Write-Host "  RID Master:             $($domain.RIDMaster)" -ForegroundColor White
    Write-Host "  Infrastructure Master:  $($domain.InfrastructureMaster)" -ForegroundColor White
    Write-Host "  Schema Master:          $($forest.SchemaMaster)" -ForegroundColor White
    Write-Host "  Domain Naming Master:   $($forest.DomainNamingMaster)" -ForegroundColor White
} catch {
    Write-Host "  [ERROR] Khong the doc thong tin AD Domain: $_" -ForegroundColor Red
}

# 4. Kiem tra chia se mang SYSVOL va NETLOGON
Write-Host "`n[3/5] KIEM TRA SHARE SYSVOL VA NETLOGON:" -ForegroundColor Yellow
$shares = Get-SmbShare -Name SYSVOL, NETLOGON -ErrorAction SilentlyContinue
if ($shares) {
    foreach ($sh in $shares) {
        Write-Host "  [OK] Share $($sh.Name.PadRight(10)) : Ton tai tai $($sh.Path)" -ForegroundColor Green
    }
} else {
    Write-Host "  [CANH BAO] Chua thay SYSVOL/NETLOGON duoc share. Neu may vua reboot, vui long doi 1-2 phut." -ForegroundColor Yellow
}

# 5. Kiem tra phan giai DNS
Write-Host "`n[4/5] KIEM TRA BAN GHI DNS CHO DOMAIN $($global:ADConfig.DomainName):" -ForegroundColor Yellow
try {
    $aRecords = Resolve-DnsName -Name $global:ADConfig.DomainName -Type A -ErrorAction Stop
    foreach ($rec in $aRecords) {
        Write-Host "  [OK] A Record $($rec.Name) -> $($rec.IPAddress)" -ForegroundColor Green
    }
} catch {
    Write-Host "  [CANH BAO] Khong the phan giai A Record cho $($global:ADConfig.DomainName): $_" -ForegroundColor Yellow
}

$srvQuery = "_ldap._tcp.dc._msdcs.$($global:ADConfig.DomainName)"
try {
    $srvRecords = Resolve-DnsName -Name $srvQuery -Type SRV -ErrorAction Stop
    foreach ($srv in $srvRecords) {
        Write-Host "  [OK] SRV Record ($srvQuery) -> Target: $($srv.NameTarget):$($srv.Port)" -ForegroundColor Green
    }
} catch {
    Write-Host "  [CANH BAO] Khong the phan giai SRV Record ($srvQuery): $_" -ForegroundColor Yellow
}

# 6. Kiem tra chi tiet 2 user admin hoangpt va hoangxuan
Write-Host "`n[5/5] KIEM TRA TRANG THAI 2 USER ADMIN (hoangpt, hoangxuan):" -ForegroundColor Yellow
foreach ($userCfg in $global:ADConfig.AdminUsers) {
    $sam = $userCfg.SamAccountName
    Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
    try {
        $u = Get-ADUser -Identity $sam -Properties MemberOf, Enabled, PasswordNeverExpires, Title, Department, UserPrincipalName -ErrorAction Stop
        Write-Host "  User:             $($u.SamAccountName)" -ForegroundColor Cyan
        Write-Host "  Display Name:     $($u.Name)" -ForegroundColor White
        Write-Host "  UPN:              $($u.UserPrincipalName)" -ForegroundColor White
        Write-Host "  Enabled:          $($u.Enabled)" -ForegroundColor $(if ($u.Enabled) { "Green" } else { "Red" })
        Write-Host "  Password Never Exp: $($u.PasswordNeverExpires)" -ForegroundColor White
        Write-Host "  Chuc vu / Phong:  $($u.Title) / $($u.Department)" -ForegroundColor White
        
        Write-Host "  Nhom thanh vien (MemberOf):" -ForegroundColor Yellow
        $memberOf = $u.MemberOf | ForEach-Object { (Get-ADGroup -Identity $_).Name }
        foreach ($grp in $memberOf) {
            $isKeyAdmin = $global:ADConfig.AdminGroups -contains $grp
            $color = if ($isKeyAdmin) { "Green" } else { "Gray" }
            Write-Host "    * $grp" -ForegroundColor $color
        }

        # Kiem tra xem da thuoc Domain Admins chua
        if ($memberOf -contains "Domain Admins") {
            Write-Host "  => KET QUA: [$sam] CO DAY DU QUYEN DOMAIN ADMINS!" -ForegroundColor Green
        } else {
            Write-Host "  => CANH BAO: [$sam] CHUA THUOC NHOM DOMAIN ADMINS!" -ForegroundColor Red
        }
    } catch {
        Write-Host "  [ERROR] Khong tim thay user '$sam' trong AD! Vui long chay .\02-Init-AdminUsers.ps1" -ForegroundColor Red
    }
}

Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "                 HOAN TAT KIEM TRA TOAN DIEN HE THONG" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor DarkCyan
