# ==============================================================================
# 02-Restore-AD.ps1 - Phuc hoi Active Directory iai.io.vn tu ban sao luu
# ------------------------------------------------------------------------------
# Script chay theo MODE, moi mode xu ly mot tinh huong su co rieng:
#
#   List          Liet ke cac ban sao luu dang co (mac dinh, khong thay doi gi)
#   RecycleBin    Phuc hoi object bi xoa tu AD Recycle Bin (nhanh & an toan nhat)
#   Objects       Import lai user/group/OU tu file LDIF
#   Membership    Gan lai thanh vien nhom tu group-membership.csv
#   GPO           Phuc hoi Group Policy + link lai vao OU
#   DNS           Phuc hoi DNS zone tu file .dns da export
#   SYSVOL        Phuc hoi noi dung SYSVOL (logon script, policy files)
#   SystemState   Phuc hoi ca Domain Controller - CHI chay duoc trong DSRM
#   Authoritative Ep mot nhanh OU thang replication - CHI chay trong DSRM
#
# MOI MODE DEU HO TRO -WhatIf DE XEM TRUOC MA KHONG THAY DOI GI.
# ==============================================================================
#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet("List", "RecycleBin", "Objects", "Membership", "GPO", "DNS", "SYSVOL", "SystemState", "Authoritative")]
    [string]   $Mode = "List",

    # Thu muc ban sao luu cu the (vi du E:\AD-Backup\20260920-153000). Trong = ban moi nhat.
    [string]   $BackupPath = "",

    # Thu muc goc chua cac ban sao luu. Trong = tu do tim.
    [string]   $BackupRoot = "",

    # Loc doi tuong theo ten / sAMAccountName (mode RecycleBin, Objects).
    [string]   $Identity = "",

    # File LDIF cu the (mode Objects). Mac dinh: users.ldf
    [string]   $LdifFile = "users.ldf",

    # Ten GPO can phuc hoi (mode GPO). Trong = tat ca GPO trong ban sao luu.
    [string[]] $GpoName = @(),

    # Link lai GPO vao OU theo gpo-links.csv sau khi phuc hoi.
    [switch]   $RelinkGpo,

    # Phien ban System State (mode SystemState), dinh dang MM/DD/YYYY-HH:MM.
    [string]   $Version = "",

    # Phuc hoi SYSVOL o che do authoritative (mode SystemState).
    [switch]   $AuthSysvol,

    # Nhanh OU can ep authoritative (mode Authoritative).
    [string]   $Subtree = "",

    # Bo qua cac buoc go xac nhan bang tay. Dung cho automation - can trong!
    [switch]   $Force
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ------------------------------------------------------------------------------
# Nap cau hinh (dung chung voi bo script cai dat)
# ------------------------------------------------------------------------------
$configCandidates = @(
    (Join-Path $scriptDir "00-Config.ps1"),
    (Join-Path (Split-Path -Parent $scriptDir) "install-ad\00-Config.ps1"),
    (Join-Path (Split-Path -Parent $scriptDir) "00-Config.ps1")
)
$configFile = $configCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($configFile) {
    . $configFile
} else {
    $global:ADConfig = @{ DomainName = $env:USERDNSDOMAIN }
    function Write-ADLog {
        param([string]$Message, [string]$Level = "INFO")
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $color = switch ($Level) { "SUCCESS" { "Green" } "WARN" { "Yellow" } "ERROR" { "Red" } default { "Cyan" } }
        Write-Host "[$ts] [$Level] $Message" -ForegroundColor $color
    }
}

# ==============================================================================
# HAM TIEN ICH
# ==============================================================================

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# DSRM = may dang boot o Safe Mode voi tuy chon Directory Services Repair.
function Test-IsDSRM {
    return (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\Option")
}

# Bat buoc go dung chuoi xac nhan truoc khi lam viec pha huy.
function Confirm-Danger {
    param(
        [Parameter(Mandatory)] [string] $Message,
        [string] $Expect = "YES"
    )
    if ($Force) {
        Write-ADLog "Bo qua xac nhan vi co -Force." "WARN"
        return $true
    }
    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Red
    Write-Host " CANH BAO: $Message" -ForegroundColor Red
    Write-Host "======================================================================" -ForegroundColor Red
    $answer = Read-Host "Go chinh xac '$Expect' de tiep tuc (bat ky gi khac = huy)"
    if ($answer -ceq $Expect) { return $true }
    Write-ADLog "Da huy theo yeu cau nguoi dung." "WARN"
    return $false
}

# Tim thu muc goc chua ban sao luu tren cac o dia co dinh.
function Find-BackupRoot {
    if (-not [string]::IsNullOrWhiteSpace($BackupRoot)) { return $BackupRoot }

    $candidates = Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" } |
        ForEach-Object { "$($_.DriveLetter):\AD-Backup" } |
        Where-Object { Test-Path $_ }

    if (-not $candidates) {
        throw "Khong tim thay thu muc AD-Backup tren o dia nao. Dung -BackupRoot de chi dinh."
    }
    return ($candidates | Select-Object -First 1)
}

# Lay danh sach cac ban sao luu, moi nhat truoc.
function Get-BackupSet {
    $root = Find-BackupRoot
    Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{8}-\d{6}$' } |
        Sort-Object Name -Descending |
        ForEach-Object {
            $manifestFile = Join-Path $_.FullName "manifest.json"
            $manifest = $null
            if (Test-Path $manifestFile) {
                try { $manifest = Get-Content $manifestFile -Raw | ConvertFrom-Json } catch { }
            }
            [pscustomobject]@{
                Name     = $_.Name
                Path     = $_.FullName
                Created  = $_.CreationTime
                SizeMB   = if ($manifest) { $manifest.SizeMB } else { $null }
                Domain   = if ($manifest) { $manifest.Domain } else { "?" }
                Manifest = $manifest
            }
        }
}

# Chon ban sao luu se dung: -BackupPath, hoac ban moi nhat.
function Resolve-BackupPath {
    if (-not [string]::IsNullOrWhiteSpace($BackupPath)) {
        if (-not (Test-Path $BackupPath)) { throw "Khong tim thay thu muc: $BackupPath" }
        return (Resolve-Path $BackupPath).Path
    }
    $latest = Get-BackupSet | Select-Object -First 1
    if (-not $latest) { throw "Khong co ban sao luu nao. Chay 01-Backup-AD.ps1 truoc." }
    Write-ADLog "Dung ban sao luu moi nhat: $($latest.Path)" "INFO"
    return $latest.Path
}

# Do sau cua mot DN - dung de phuc hoi OU cha truoc, object con sau.
function Get-DnDepth {
    param([string]$Dn)
    if ([string]::IsNullOrWhiteSpace($Dn)) { return 0 }
    return ($Dn.ToCharArray() | Where-Object { $_ -eq ',' }).Count
}

# ==============================================================================
# KIEM TRA DIEU KIEN CHUNG
# ==============================================================================
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "       PHUC HOI ACTIVE DIRECTORY - MODE: $($Mode.ToUpper())" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor DarkCyan

if (-not (Test-IsAdministrator)) {
    Write-ADLog "Script phai chay bang quyen Administrator." "ERROR"
    exit 1
}

# Cac mode lam viec truc tiep voi AD dang chay -> can module va dich vu NTDS.
$modesNeedingLiveAD = @("RecycleBin", "Objects", "Membership", "GPO", "DNS")
if ($modesNeedingLiveAD -contains $Mode) {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    } catch {
        Write-ADLog "Khong nap duoc module ActiveDirectory." "ERROR"
        exit 1
    }
    $ntds = Get-Service -Name NTDS -ErrorAction SilentlyContinue
    if (-not $ntds -or $ntds.Status -ne "Running") {
        Write-ADLog "Dich vu NTDS khong chay. Mode '$Mode' can AD dang hoat dong binh thuong." "ERROR"
        Write-ADLog "Neu may dang o DSRM, hay dung mode SystemState hoac Authoritative." "INFO"
        exit 1
    }
}

# Cac mode chi chay duoc trong DSRM.
$modesNeedingDSRM = @("SystemState", "Authoritative")
if ($modesNeedingDSRM -contains $Mode -and -not (Test-IsDSRM)) {
    Write-ADLog "May KHONG dang o Directory Services Restore Mode (DSRM)." "ERROR"
    Write-Host ""
    Write-Host "Cach vao DSRM:" -ForegroundColor Yellow
    Write-Host "  1. bcdedit /set {default} safeboot dsrepair" -ForegroundColor White
    Write-Host "  2. shutdown /r /t 0" -ForegroundColor White
    Write-Host "  3. Dang nhap bang .\Administrator voi MAT KHAU DSRM" -ForegroundColor White
    Write-Host "  4. Chay lai script nay voi -Mode $Mode" -ForegroundColor White
    Write-Host "  5. Xong roi thoat DSRM: bcdedit /deletevalue {default} safeboot" -ForegroundColor White
    Write-Host ""

    if (Confirm-Danger -Message "Dat che do boot vao DSRM va KHOI DONG LAI MAY CHU NGAY BAY GIO?" -Expect "REBOOT") {
        if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Dat safeboot dsrepair va reboot")) {
            & bcdedit /set "{default}" safeboot dsrepair
            if ($LASTEXITCODE -ne 0) { Write-ADLog "bcdedit that bai (ma $LASTEXITCODE)." "ERROR"; exit 2 }
            Write-ADLog "Dang khoi dong lai vao DSRM..." "WARN"
            & shutdown /r /t 5 /c "Khoi dong vao DSRM de phuc hoi Active Directory"
        }
    }
    exit 1
}

# ==============================================================================
# MODE: LIST - liet ke ban sao luu (mac dinh, khong thay doi gi)
# ==============================================================================
if ($Mode -eq "List") {
    $sets = Get-BackupSet
    if (-not $sets) {
        Write-ADLog "Khong tim thay ban sao luu nao." "WARN"
        exit 1
    }

    Write-Host ""
    Write-Host "CAC BAN SAO LUU THU MUC:" -ForegroundColor Yellow
    $sets | Format-Table @{ N = "Ban sao luu"; E = { $_.Name } },
                         @{ N = "Ngay tao";    E = { $_.Created.ToString("yyyy-MM-dd HH:mm") } },
                         @{ N = "MB";          E = { $_.SizeMB } },
                         @{ N = "Domain";      E = { $_.Domain } },
                         @{ N = "Duong dan";   E = { $_.Path } } -AutoSize

    $newest = $sets | Select-Object -First 1
    if ($newest.Manifest -and $newest.Manifest.Steps) {
        Write-Host "CHI TIET BAN MOI NHAT ($($newest.Name)):" -ForegroundColor Yellow
        $newest.Manifest.Steps | Format-Table Step, Status, Seconds -AutoSize
    }

    # Canh bao tombstone: ban sao luu qua cu thi KHONG duoc phep phuc hoi
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $baseDN = (Get-ADDomain).DistinguishedName
        $tsl = (Get-ADObject "CN=Directory Service,CN=Windows NT,CN=Services,CN=Configuration,$baseDN" `
                    -Properties tombstoneLifetime).tombstoneLifetime
        if (-not $tsl) { $tsl = 180 }
        $ageDays = [int]((Get-Date) - $newest.Created).TotalDays
        if ($ageDays -gt $tsl) {
            Write-ADLog "Ban moi nhat da $ageDays ngay tuoi > tombstone lifetime $tsl ngay - KHONG dung duoc nua!" "ERROR"
        } else {
            Write-ADLog "Ban moi nhat: $ageDays ngay tuoi (tombstone lifetime $tsl ngay). Con dung duoc." "SUCCESS"
        }
    } catch { }

    Write-Host ""
    Write-Host "CAC BAN SYSTEM STATE (wbadmin):" -ForegroundColor Yellow
    & wbadmin get versions 2>&1 | Select-Object -First 40

    Write-Host ""
    Write-Host "Chon viec can lam:" -ForegroundColor Cyan
    Write-Host "  .\02-Restore-AD.ps1 -Mode RecycleBin -Identity hoangpt   # xoa nham 1 user" -ForegroundColor White
    Write-Host "  .\02-Restore-AD.ps1 -Mode Objects -Identity hoangpt      # import lai tu LDIF" -ForegroundColor White
    Write-Host "  .\02-Restore-AD.ps1 -Mode GPO -RelinkGpo                 # phuc hoi Group Policy" -ForegroundColor White
    Write-Host "  .\02-Restore-AD.ps1 -Mode SystemState                    # dung lai ca DC (can DSRM)" -ForegroundColor White
    exit 0
}

# ==============================================================================
# MODE: RECYCLEBIN - phuc hoi object bi xoa (nhanh nhat, khong can ban sao luu)
# ==============================================================================
if ($Mode -eq "RecycleBin") {
    $feature = Get-ADOptionalFeature -Filter 'Name -like "Recycle Bin Feature"'
    if (-not $feature -or -not $feature.EnabledScopes) {
        Write-ADLog "AD Recycle Bin CHUA duoc bat -> khong dung duoc mode nay." "ERROR"
        Write-Host ""
        Write-Host "Bat Recycle Bin (luu y: bat roi KHONG tat lai duoc):" -ForegroundColor Yellow
        Write-Host "  Enable-ADOptionalFeature 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target $($global:ADConfig.DomainName)" -ForegroundColor White
        Write-Host ""
        Write-Host "Voi object da xoa TRUOC khi bat, hay dung: -Mode Objects (import tu LDIF)." -ForegroundColor Yellow
        exit 1
    }

    $deleted = Get-ADObject -Filter { isDeleted -eq $true -and name -ne "Deleted Objects" } `
                            -IncludeDeletedObjects `
                            -Properties lastKnownParent, whenChanged, sAMAccountName, objectClass

    if ($Identity) {
        $deleted = $deleted | Where-Object { $_.Name -like "*$Identity*" -or $_.sAMAccountName -like "*$Identity*" }
    }

    if (-not $deleted) {
        Write-ADLog "Khong co object nao bi xoa (khop bo loc '$Identity')." "WARN"
        exit 0
    }

    Write-Host ""
    Write-Host "CAC OBJECT DANG NAM TRONG RECYCLE BIN:" -ForegroundColor Yellow
    $deleted | Sort-Object whenChanged -Descending |
        Format-Table @{ N = "Ten"; E = { ($_.Name -split '\\0ADEL')[0] } },
                     @{ N = "Loai"; E = { $_.objectClass } },
                     @{ N = "Xoa luc"; E = { $_.whenChanged } },
                     @{ N = "Vi tri cu"; E = { $_.lastKnownParent } } -AutoSize

    if (-not (Confirm-Danger -Message "Phuc hoi $(@($deleted).Count) object tren ve vi tri cu?" -Expect "YES")) {
        exit 1
    }

    # Phuc hoi container cha truoc, object con sau - neu khong se loi "parent does not exist"
    $ordered = $deleted | Sort-Object { Get-DnDepth $_.lastKnownParent }
    $ok = 0; $fail = 0
    foreach ($obj in $ordered) {
        $displayName = ($obj.Name -split '\\0ADEL')[0]
        try {
            if ($PSCmdlet.ShouldProcess($displayName, "Restore-ADObject")) {
                Restore-ADObject -Identity $obj.DistinguishedName -ErrorAction Stop
                Write-ADLog "Da phuc hoi: $displayName -> $($obj.lastKnownParent)" "SUCCESS"
                $ok++
            }
        } catch {
            Write-ADLog "That bai: $displayName -> $($_.Exception.Message)" "ERROR"
            $fail++
        }
    }

    Write-Host ""
    Write-ADLog "Ket qua: $ok thanh cong, $fail that bai." $(if ($fail -gt 0) { "WARN" } else { "SUCCESS" })
    Write-ADLog "User duoc phuc hoi tu Recycle Bin van GIU nguyen mat khau va nhom cu." "INFO"
    exit $(if ($fail -gt 0) { 2 } else { 0 })
}

# ==============================================================================
# MODE: OBJECTS - import lai user/group/OU tu file LDIF
# ==============================================================================
if ($Mode -eq "Objects") {
    $jobDir  = Resolve-BackupPath
    $ldifDir = Join-Path $jobDir "ldif"
    $source  = Join-Path $ldifDir $LdifFile
    if (-not (Test-Path $source)) {
        Write-ADLog "Khong tim thay file LDIF: $source" "ERROR"
        Write-ADLog "Cac file co san: $((Get-ChildItem $ldifDir -Filter *.ldf -ErrorAction SilentlyContinue).Name -join ', ')" "INFO"
        exit 1
    }

    $importFile = $source
    $tempFile   = $null

    # Neu chi can 1 doi tuong -> tach rieng khoi entry do ra file tam,
    # de khong dung cham toan bo phan con lai cua domain.
    if ($Identity) {
        $raw = Get-Content -Path $source -Raw -Encoding Default
        # Cac entry trong LDIF ngan cach nhau bang dong trong.
        # Dung nhom (?:...) khong bat, neu khong -split se tra ve ca phan ngan cach.
        $entries = $raw -split "(?:\r?\n){2,}" | Where-Object { $_ -match '^\s*dn:' }
        $matched = $entries | Where-Object { $_ -match [regex]::Escape($Identity) }

        if (-not $matched) {
            Write-ADLog "Khong tim thay entry nao khop '$Identity' trong $LdifFile." "ERROR"
            exit 1
        }

        Write-Host ""
        Write-Host "CAC ENTRY SE DUOC IMPORT:" -ForegroundColor Yellow
        foreach ($e in $matched) {
            $dn = ($e -split "\r?\n" | Where-Object { $_ -match '^dn:' } | Select-Object -First 1)
            Write-Host "  $dn" -ForegroundColor White
        }

        $tempFile = Join-Path $env:TEMP "restore-$Identity-$(Get-Date -Format 'HHmmss').ldf"
        ($matched -join "`r`n`r`n") + "`r`n" | Set-Content -Path $tempFile -Encoding Default
        $importFile = $tempFile
    } else {
        Write-ADLog "Se import TOAN BO file $LdifFile (khong co -Identity de loc)." "WARN"
    }

    if (-not (Confirm-Danger -Message "Import LDIF vao Active Directory tu $importFile ?" -Expect "YES")) {
        if ($tempFile -and (Test-Path $tempFile)) { Remove-Item $tempFile -Force }
        exit 1
    }

    if ($PSCmdlet.ShouldProcess($importFile, "ldifde -i")) {
        $logDir = Join-Path $env:TEMP "ldifde-restore"
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        # -k: bo qua loi "object already exists" de chi tao lai phan con thieu
        $out = & ldifde -i -f "$importFile" -j "$logDir" -k 2>&1
        $out | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

        if ($LASTEXITCODE -ne 0) {
            Write-ADLog "ldifde tra ve ma loi $LASTEXITCODE. Xem log tai $logDir" "ERROR"
            if ($tempFile -and (Test-Path $tempFile)) { Remove-Item $tempFile -Force }
            exit 2
        }
    }
    if ($tempFile -and (Test-Path $tempFile)) { Remove-Item $tempFile -Force }

    Write-Host ""
    Write-ADLog "Import xong. CAN LAM TIEP 3 VIEC (LDIF khong chua mat khau va nhom):" "WARN"
    Write-Host "  1. Dat lai mat khau:" -ForegroundColor Yellow
    Write-Host "     Set-ADAccountPassword -Identity $(if ($Identity) { $Identity } else { '<user>' }) -Reset ``" -ForegroundColor White
    Write-Host "       -NewPassword (ConvertTo-SecureString '$($global:ADConfig.DefaultUserPassword)' -AsPlainText -Force)" -ForegroundColor White
    Write-Host "  2. Bat tai khoan:" -ForegroundColor Yellow
    Write-Host "     Enable-ADAccount -Identity $(if ($Identity) { $Identity } else { '<user>' })" -ForegroundColor White
    Write-Host "  3. Gan lai nhom:" -ForegroundColor Yellow
    Write-Host "     .\02-Restore-AD.ps1 -Mode Membership -BackupPath `"$jobDir`"" -ForegroundColor White
    exit 0
}

# ==============================================================================
# MODE: MEMBERSHIP - gan lai thanh vien nhom tu group-membership.csv
# ==============================================================================
if ($Mode -eq "Membership") {
    $jobDir = Resolve-BackupPath
    $csv = Join-Path $jobDir "csv\group-membership.csv"
    if (-not (Test-Path $csv)) {
        Write-ADLog "Khong tim thay $csv" "ERROR"
        exit 1
    }

    $rows = Import-Csv $csv
    if ($Identity) {
        $rows = $rows | Where-Object { $_.Member -like "*$Identity*" }
    }
    if (-not $rows) {
        Write-ADLog "Khong co dong nao khop bo loc." "WARN"
        exit 0
    }

    # Doi chieu truoc: chi hanh dong voi cac quan he dang THIEU
    $missing = @()
    $absent  = @()
    foreach ($r in $rows) {
        # Bo loc cua module AD khong deref duoc $r.Member trong script block -> dung chuoi
        $memberName = $r.Member
        $exists = $null
        try { $exists = Get-ADObject -Filter "sAMAccountName -eq '$memberName'" -ErrorAction SilentlyContinue } catch { }
        if (-not $exists) { $absent += $r; continue }

        $already = $false
        try {
            $already = [bool](Get-ADGroupMember -Identity $r.Group -ErrorAction Stop |
                              Where-Object { $_.SamAccountName -eq $r.Member })
        } catch { }
        if (-not $already) { $missing += $r }
    }

    Write-Host ""
    Write-ADLog "Tong: $(@($rows).Count) quan he | Thieu can gan lai: $(@($missing).Count) | Object khong ton tai: $(@($absent).Count)" "INFO"

    if ($absent) {
        Write-Host ""
        Write-Host "CAC MEMBER CHUA TON TAI TRONG AD (phai tao lai truoc):" -ForegroundColor Yellow
        $absent | Select-Object Member, MemberType -Unique | Format-Table -AutoSize
    }

    if (-not $missing) {
        Write-ADLog "Khong co gi phai gan lai - thanh vien nhom da dung." "SUCCESS"
        exit 0
    }

    Write-Host "CAC QUAN HE SE DUOC GAN LAI:" -ForegroundColor Yellow
    $missing | Format-Table Group, Member, MemberType -AutoSize

    if (-not (Confirm-Danger -Message "Gan lai $(@($missing).Count) quan he thanh vien nhom?" -Expect "YES")) {
        exit 1
    }

    $ok = 0; $fail = 0
    foreach ($r in $missing) {
        try {
            if ($PSCmdlet.ShouldProcess("$($r.Member) -> $($r.Group)", "Add-ADGroupMember")) {
                Add-ADGroupMember -Identity $r.Group -Members $r.Member -ErrorAction Stop
                Write-ADLog "Da gan: $($r.Member) vao nhom $($r.Group)" "SUCCESS"
                $ok++
            }
        } catch {
            Write-ADLog "That bai: $($r.Member) -> $($r.Group): $($_.Exception.Message)" "ERROR"
            $fail++
        }
    }
    Write-ADLog "Ket qua: $ok thanh cong, $fail that bai." $(if ($fail -gt 0) { "WARN" } else { "SUCCESS" })
    exit $(if ($fail -gt 0) { 2 } else { 0 })
}

# ==============================================================================
# MODE: GPO - phuc hoi Group Policy va link lai vao OU
# ==============================================================================
if ($Mode -eq "GPO") {
    Import-Module GroupPolicy -ErrorAction Stop
    $jobDir = Resolve-BackupPath
    $gpoDir = Join-Path $jobDir "gpo"
    if (-not (Test-Path (Join-Path $gpoDir "manifest.xml"))) {
        Write-ADLog "Khong tim thay manifest.xml trong $gpoDir - thu muc nay khong phai GPO backup." "ERROR"
        exit 1
    }

    # Doc manifest cua Backup-GPO de biet ban sao luu chua nhung GPO nao.
    # Dung local-name() vi manifest.xml co namespace rieng.
    [xml]$mf = Get-Content (Join-Path $gpoDir "manifest.xml") -Raw
    $backups = foreach ($node in $mf.SelectNodes("//*[local-name()='BackupInst']")) {
        [pscustomobject]@{
            GpoGuid = ($node.SelectSingleNode("*[local-name()='GPOGuid']")).InnerText.Trim("{", "}")
            Name    = ($node.SelectSingleNode("*[local-name()='GPODisplayName']")).InnerText
            BackupId= ($node.SelectSingleNode("*[local-name()='ID']")).InnerText
        }
    }

    if ($GpoName.Count -gt 0) {
        $backups = $backups | Where-Object { $GpoName -contains $_.Name }
    }
    if (-not $backups) {
        Write-ADLog "Khong co GPO nao khop trong ban sao luu." "ERROR"
        exit 1
    }

    Write-Host ""
    Write-Host "CAC GPO SE DUOC PHUC HOI:" -ForegroundColor Yellow
    $backups | Format-Table Name, GpoGuid -AutoSize

    if (-not (Confirm-Danger -Message "Ghi de cau hinh cua $(@($backups).Count) GPO bang noi dung trong ban sao luu?" -Expect "YES")) {
        exit 1
    }

    $ok = 0; $fail = 0; $recreated = @()
    foreach ($b in $backups) {
        try {
            $live = Get-GPO -Guid $b.GpoGuid -ErrorAction SilentlyContinue
            if ($live) {
                # GPO con ton tai -> phuc hoi vao dung GUID cu, giu nguyen moi link
                if ($PSCmdlet.ShouldProcess($b.Name, "Restore-GPO")) {
                    Restore-GPO -Guid $b.GpoGuid -Path $gpoDir -ErrorAction Stop | Out-Null
                    Write-ADLog "Da phuc hoi GPO: $($b.Name)" "SUCCESS"
                    $ok++
                }
            } else {
                # GPO da bi xoa -> tao moi. LUU Y: GUID moi, moi link cu deu mat.
                if ($PSCmdlet.ShouldProcess($b.Name, "Import-GPO -CreateIfNeeded")) {
                    Import-GPO -BackupGpoName $b.Name -TargetName $b.Name -Path $gpoDir -CreateIfNeeded -ErrorAction Stop | Out-Null
                    Write-ADLog "Da tao lai GPO moi: $($b.Name) (GUID moi - can link lai)" "WARN"
                    $recreated += $b.Name
                    $ok++
                }
            }
        } catch {
            Write-ADLog "That bai: $($b.Name) -> $($_.Exception.Message)" "ERROR"
            $fail++
        }
    }

    # Link lai GPO vao OU theo bang da luu luc backup
    if ($RelinkGpo) {
        $linkCsv = Join-Path $gpoDir "gpo-links.csv"
        if (-not (Test-Path $linkCsv)) {
            Write-ADLog "Khong co gpo-links.csv - bo qua buoc link lai." "WARN"
        } else {
            Write-Host ""
            Write-ADLog "Dang link lai GPO vao OU theo gpo-links.csv..." "INFO"
            foreach ($l in (Import-Csv $linkCsv)) {
                if ($GpoName.Count -gt 0 -and $GpoName -notcontains $l.GpoName) { continue }
                # GPO link vao Site co SOMPath khac han - khong doi sang DN cua OU duoc
                if ($l.LinkedTo -match "/Sites?/") {
                    Write-ADLog "Bo qua link vao Site (phai link tay): $($l.GpoName) -> $($l.LinkedTo)" "WARN"
                    continue
                }
                try {
                    # SOMPath dang "iai.io.vn/IAI_Corp/Admins" -> doi sang DN
                    $parts = $l.LinkedTo -split "/"
                    if ($parts.Count -eq 1) {
                        $target = (Get-ADDomain).DistinguishedName
                    } else {
                        $ouParts = $parts[1..($parts.Count - 1)]
                        [array]::Reverse($ouParts)
                        $target = (($ouParts | ForEach-Object { "OU=$_" }) -join ",") + "," + (Get-ADDomain).DistinguishedName
                    }

                    $existing = Get-GPInheritance -Target $target -ErrorAction SilentlyContinue
                    if ($existing -and ($existing.GpoLinks.DisplayName -contains $l.GpoName)) {
                        Write-ADLog "Da co link san: $($l.GpoName) -> $target" "INFO"
                        continue
                    }
                    if ($PSCmdlet.ShouldProcess("$($l.GpoName) -> $target", "New-GPLink")) {
                        New-GPLink -Name $l.GpoName -Target $target -ErrorAction Stop | Out-Null
                        Write-ADLog "Da link: $($l.GpoName) -> $target" "SUCCESS"
                    }
                } catch {
                    Write-ADLog "Khong link duoc $($l.GpoName) -> $($l.LinkedTo): $($_.Exception.Message)" "WARN"
                }
            }
        }
    } elseif ($recreated.Count -gt 0) {
        Write-Host ""
        Write-ADLog "$($recreated.Count) GPO duoc tao lai voi GUID MOI nen KHONG con link cu." "WARN"
        Write-ADLog "Chay lai voi -RelinkGpo de link lai theo gpo-links.csv." "INFO"
    }

    Write-Host ""
    Write-ADLog "Ket qua: $ok thanh cong, $fail that bai." $(if ($fail -gt 0) { "WARN" } else { "SUCCESS" })
    Write-ADLog "Chay 'gpupdate /force' tren may client de ap dung ngay." "INFO"
    exit $(if ($fail -gt 0) { 2 } else { 0 })
}

# ==============================================================================
# MODE: DNS - phuc hoi zone tu file .dns da export
# ==============================================================================
if ($Mode -eq "DNS") {
    Import-Module DnsServer -ErrorAction Stop
    $jobDir = Resolve-BackupPath
    $dnsDir = Join-Path $jobDir "dns"
    if (-not (Test-Path $dnsDir)) {
        Write-ADLog "Khong tim thay thu muc dns trong ban sao luu." "ERROR"
        exit 1
    }

    Write-ADLog "Zone tich hop AD (_msdcs, iai.io.vn) thuong TU PHUC HOI cung AD - it khi can mode nay." "WARN"

    $files = Get-ChildItem $dnsDir -Filter "backup_*.dns"
    if (-not $files) {
        Write-ADLog "Khong co file .dns nao trong ban sao luu." "ERROR"
        exit 1
    }

    $dnsSystemDir = "$env:SystemRoot\System32\dns"
    $created = 0; $skipped = 0; $fail = 0

    foreach ($f in $files) {
        $zoneName = $f.BaseName -replace '^backup_', ''
        $existing = Get-DnsServerZone -Name $zoneName -ErrorAction SilentlyContinue

        if ($existing) {
            # KHONG tu dong xoa zone dang chay - chi bao va huong dan
            Write-ADLog "Zone '$zoneName' dang ton tai -> BO QUA (khong ghi de zone dang chay)." "WARN"
            Write-Host "    Neu that su muon thay the, lam thu cong:" -ForegroundColor Gray
            Write-Host "      Remove-DnsServerZone -Name $zoneName -Force" -ForegroundColor Gray
            Write-Host "      Copy-Item '$($f.FullName)' '$dnsSystemDir\$($f.Name)'" -ForegroundColor Gray
            Write-Host "      Add-DnsServerPrimaryZone -Name $zoneName -ZoneFile '$($f.Name)' -LoadExisting" -ForegroundColor Gray
            $skipped++
            continue
        }

        try {
            if ($PSCmdlet.ShouldProcess($zoneName, "Add-DnsServerPrimaryZone -LoadExisting")) {
                Copy-Item $f.FullName (Join-Path $dnsSystemDir $f.Name) -Force
                Add-DnsServerPrimaryZone -Name $zoneName -ZoneFile $f.Name -LoadExisting -ErrorAction Stop
                Write-ADLog "Da tao lai zone: $zoneName" "SUCCESS"
                $created++
            }
        } catch {
            Write-ADLog "That bai voi zone '$zoneName': $($_.Exception.Message)" "ERROR"
            $fail++
        }
    }

    Write-Host ""
    Write-ADLog "Ket qua: $created tao moi, $skipped bo qua (da ton tai), $fail that bai." "INFO"
    Write-ADLog "Zone tao lai la zone FILE-BACKED. De chuyen ve AD-integrated: ConvertTo-DnsServerPrimaryZone -Name <zone> -ReplicationScope Domain -Force" "INFO"
    exit $(if ($fail -gt 0) { 2 } else { 0 })
}

# ==============================================================================
# MODE: SYSVOL - phuc hoi logon script / policy files
# ==============================================================================
if ($Mode -eq "SYSVOL") {
    $jobDir    = Resolve-BackupPath
    $sysvolSrc = Join-Path $jobDir "sysvol"
    $sysvolDst = "$env:SystemRoot\SYSVOL\domain"

    if (-not (Test-Path $sysvolSrc)) {
        Write-ADLog "Khong tim thay ban sao SYSVOL trong $jobDir" "ERROR"
        exit 1
    }

    $dcCount = @(Get-ADDomainController -Filter * -ErrorAction SilentlyContinue).Count
    if ($dcCount -gt 1) {
        Write-ADLog "Domain co $dcCount DC. Chep de len SYSVOL truc tiep co the bi replication ghi nguoc lai." "WARN"
        Write-ADLog "Voi nhieu DC, dung authoritative SYSVOL restore (DFSR: msDFSR-Options=1) thay vi mode nay." "WARN"
    }

    # Mac dinh /E: chi bo sung file thieu, KHONG xoa gi.
    # -Force moi dung /MIR: xoa file khong co trong ban sao luu.
    $mirror = $false
    if ($Force) {
        $mirror = $true
    } else {
        Write-Host ""
        Write-Host "Chon kieu phuc hoi SYSVOL:" -ForegroundColor Yellow
        Write-Host "  [1] An toan (/E)  - chi bo sung file thieu, giu nguyen file dang co (khuyen nghi)" -ForegroundColor White
        Write-Host "  [2] Mirror (/MIR) - lam SYSVOL giong het ban sao luu, XOA file khong co trong do" -ForegroundColor White
        $pick = Read-Host "Lua chon [1/2]"
        if ($pick -eq "2") {
            if (-not (Confirm-Danger -Message "/MIR se XOA moi file trong SYSVOL khong co trong ban sao luu!" -Expect "MIRROR")) {
                exit 1
            }
            $mirror = $true
        }
    }

    $mode = if ($mirror) { "/MIR" } else { "/E" }
    $rcLog = Join-Path $env:TEMP "robocopy-sysvol-restore.txt"

    if ($PSCmdlet.ShouldProcess($sysvolDst, "robocopy $mode tu $sysvolSrc")) {
        & robocopy $sysvolSrc $sysvolDst $mode /R:2 /W:2 /NFL /NDL /NP /LOG:"$rcLog" | Out-Null
        if ($LASTEXITCODE -ge 8) {
            Write-ADLog "robocopy loi, ma thoat $LASTEXITCODE. Xem $rcLog" "ERROR"
            exit 2
        }
        Write-ADLog "Da phuc hoi SYSVOL ($mode). Log: $rcLog" "SUCCESS"
    }
    exit 0
}

# ==============================================================================
# MODE: SYSTEMSTATE - phuc hoi ca Domain Controller (chi trong DSRM)
# ==============================================================================
if ($Mode -eq "SystemState") {
    Write-ADLog "Dang o DSRM - du dieu kien phuc hoi System State." "SUCCESS"

    Write-Host ""
    Write-Host "CAC PHIEN BAN SYSTEM STATE CO SAN:" -ForegroundColor Yellow
    & wbadmin get versions

    if ([string]::IsNullOrWhiteSpace($Version)) {
        Write-Host ""
        Write-ADLog "Chua chon phien ban. Chay lai voi -Version theo dinh dang MM/DD/YYYY-HH:MM" "ERROR"
        Write-Host "  Vi du: .\02-Restore-AD.ps1 -Mode SystemState -Version 09/20/2026-15:30" -ForegroundColor White
        exit 1
    }

    $msg = "Ghi de toan bo System State cua $env:COMPUTERNAME bang ban $Version. " +
           "May se can khoi dong lai. KHONG the hoan tac."
    if (-not (Confirm-Danger -Message $msg -Expect "RESTORE")) {
        exit 1
    }

    # Khong dat ten bien la $args - do la bien tu dong cua PowerShell
    $wbArgs = @("start", "systemstaterecovery", "-version:$Version", "-quiet")
    if ($AuthSysvol) {
        $wbArgs += "-authsysvol"
        Write-ADLog "Bat -authsysvol: SYSVOL nay se ghi de len cac DC khac." "WARN"
    }

    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "wbadmin $($wbArgs -join ' ')")) {
        Write-ADLog "Dang phuc hoi System State - co the mat 10-30 phut, KHONG duoc tat may..." "WARN"
        & wbadmin @wbArgs
        if ($LASTEXITCODE -ne 0) {
            Write-ADLog "wbadmin tra ve ma loi $LASTEXITCODE." "ERROR"
            exit 2
        }
        Write-ADLog "Phuc hoi System State thanh cong." "SUCCESS"
    }

    Write-Host ""
    Write-Host "BUOC TIEP THEO:" -ForegroundColor Yellow
    Write-Host "  - Neu can ep mot nhanh OU thang replication, lam NGAY BAY GIO (van dang o DSRM):" -ForegroundColor White
    Write-Host "      .\02-Restore-AD.ps1 -Mode Authoritative -Subtree `"OU=IAI_Corp,DC=iai,DC=io,DC=vn`"" -ForegroundColor White
    Write-Host "  - Thoat DSRM va khoi dong lai binh thuong:" -ForegroundColor White
    Write-Host "      bcdedit /deletevalue {default} safeboot" -ForegroundColor White
    Write-Host "      shutdown /r /t 0" -ForegroundColor White
    Write-Host "  - Sau khi len lai, kiem tra bang: ..\install-ad\03-Verify-AD.ps1" -ForegroundColor White
    exit 0
}

# ==============================================================================
# MODE: AUTHORITATIVE - ep mot nhanh OU thang replication (chi trong DSRM)
# ==============================================================================
if ($Mode -eq "Authoritative") {
    if ([string]::IsNullOrWhiteSpace($Subtree)) {
        Write-ADLog "Thieu -Subtree. Vi du: -Subtree `"OU=IAI_Corp,DC=iai,DC=io,DC=vn`"" "ERROR"
        exit 1
    }

    Write-ADLog "Authoritative restore chi co y nghia khi domain co NHIEU DC." "WARN"
    Write-ADLog "Phai chay NGAY SAU buoc SystemState va TRUOC khi reboot ra che do thuong." "WARN"

    $msg = "Ep nhanh '$Subtree' ghi de len TAT CA cac DC khac trong domain?"
    if (-not (Confirm-Danger -Message $msg -Expect "AUTHORITATIVE")) {
        exit 1
    }

    if ($PSCmdlet.ShouldProcess($Subtree, "ntdsutil authoritative restore")) {
        $cmd = "activate instance ntds`r`nauthoritative restore`r`nrestore subtree `"$Subtree`"`r`nquit`r`nquit`r`n"
        $out = $cmd | & ntdsutil 2>&1
        $out | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

        if ($out -match "successfully|Successfully") {
            Write-ADLog "Da danh dau authoritative cho: $Subtree" "SUCCESS"
        } else {
            Write-ADLog "Khong thay thong bao thanh cong - doc ky output ben tren truoc khi reboot." "ERROR"
            exit 2
        }
    }

    Write-Host ""
    Write-Host "Thoat DSRM va khoi dong lai:" -ForegroundColor Yellow
    Write-Host "  bcdedit /deletevalue {default} safeboot" -ForegroundColor White
    Write-Host "  shutdown /r /t 0" -ForegroundColor White
    exit 0
}
