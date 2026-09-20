# ==============================================================================
# 01-Backup-AD.ps1 - Sao luu toan bo dich vu Active Directory iai.io.vn
# ------------------------------------------------------------------------------
# Script chay tren chinh Domain Controller, tao mot ban sao luu day du gom:
#   1. System State (wbadmin)      -> ban sao luu CHINH THUC, dung de phuc hoi DC
#   2. IFM snapshot (ntdsutil)     -> ban sao NTDS.dit + registry doc lap
#   3. LDIF export (ldifde)        -> khoi phuc tung doi tuong (user/group/OU)
#   4. CSV export (AD cmdlets)     -> doc bang Excel, doi chieu nhanh
#   5. Group Policy (Backup-GPO)   -> toan bo GPO + bao cao HTML + bang link
#   6. DNS zones                   -> export tung zone cua DNS Server
#   7. SYSVOL (robocopy)           -> script logon, policy files
#   8. Metadata + dcdiag/repadmin  -> FSMO, DC list, suc khoe he thong
# ==============================================================================
#requires -Version 5.1

[CmdletBinding()]
param(
    # Thu muc goc chua ban sao luu. De trong = tu chon o dia phu hop nhat.
    [string] $BackupRoot = "",

    # Xoa cac ban sao luu cu hon so ngay nay. 0 = khong xoa.
    [int]    $RetentionDays = 14,

    # So ban System State giu lai trong kho wbadmin.
    [int]    $KeepSystemStateVersions = 3,

    # Bo qua buoc System State (nhanh hon nhieu, nhung KHONG du de phuc hoi DC).
    [switch] $SkipSystemState,

    # Nen thu muc sao luu thanh file .zip sau khi xong.
    [switch] $Compress
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ------------------------------------------------------------------------------
# 1. Nap file cau hinh (ho tro ca 2 kieu bo tri thu muc)
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
    Write-Warning "Khong tim thay 00-Config.ps1. Se doc thong tin truc tiep tu Active Directory."
    $global:ADConfig = @{ DomainName = $env:USERDNSDOMAIN }
    function Write-ADLog {
        param([string]$Message, [string]$Level = "INFO")
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $color = switch ($Level) { "SUCCESS" { "Green" } "WARN" { "Yellow" } "ERROR" { "Red" } default { "Cyan" } }
        Write-Host "[$ts] [$Level] $Message" -ForegroundColor $color
    }
}

# ------------------------------------------------------------------------------
# 2. Ham tien ich
# ------------------------------------------------------------------------------
$script:StepResults = New-Object System.Collections.ArrayList

function Invoke-BackupStep {
    param(
        [Parameter(Mandatory)] [string]      $Name,
        [Parameter(Mandatory)] [scriptblock] $Action,
        [switch] $Critical
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host ""
    Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-ADLog "BAT DAU: $Name" "INFO"
    $status = "OK"
    $detail = ""
    try {
        $detail = & $Action
        Write-ADLog "HOAN TAT: $Name" "SUCCESS"
    } catch {
        $status = if ($Critical) { "FAILED" } else { "SKIPPED" }
        $detail = $_.Exception.Message
        $level = if ($Critical) { "ERROR" } else { "WARN" }
        Write-ADLog "$($status): $Name -> $detail" $level
    }
    $sw.Stop()
    [void]$script:StepResults.Add([pscustomobject]@{
        Step    = $Name
        Status  = $status
        Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        Detail  = ($detail | Out-String).Trim()
    })
}

function Get-FolderSizeMB {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    $bytes = (Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
              Measure-Object -Property Length -Sum).Sum
    if (-not $bytes) { return 0 }
    return [math]::Round(($bytes / 1MB), 1)
}

# ------------------------------------------------------------------------------
# 3. Kiem tra dieu kien tien quyet
# ------------------------------------------------------------------------------
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "        SAO LUU TOAN BO ACTIVE DIRECTORY - $($global:ADConfig.DomainName)" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor DarkCyan

$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-ADLog "Script phai chay bang quyen Administrator. Mo PowerShell bang 'Run as administrator'." "ERROR"
    exit 1
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-ADLog "Khong nap duoc module ActiveDirectory. May nay co phai Domain Controller khong?" "ERROR"
    exit 1
}

$ntds = Get-Service -Name NTDS -ErrorAction SilentlyContinue
if (-not $ntds -or $ntds.Status -ne "Running") {
    Write-ADLog "Dich vu NTDS khong chay. Chi sao luu duoc tren Domain Controller dang hoat dong." "ERROR"
    exit 1
}

$domain    = Get-ADDomain
$forest    = Get-ADForest
$baseDN    = $domain.DistinguishedName
$domainDNS = $domain.DNSRoot
Write-ADLog "Domain: $domainDNS  |  Base DN: $baseDN  |  DC: $env:COMPUTERNAME" "INFO"

# ------------------------------------------------------------------------------
# 4. Xac dinh noi luu tru
# ------------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
    # Uu tien o dia co dinh KHAC o he thong, con nhieu dung luong nhat
    $sysDriveLetter = $env:SystemDrive.TrimEnd(":")
    $candidate = Get-Volume -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DriveLetter -and
            $_.DriveType -eq "Fixed" -and
            $_.FileSystem -eq "NTFS" -and
            $_.DriveLetter -ne $sysDriveLetter
        } | Sort-Object SizeRemaining -Descending | Select-Object -First 1

    if ($candidate) {
        $BackupRoot = "$($candidate.DriveLetter):\AD-Backup"
    } else {
        $BackupRoot = "$env:SystemDrive\AD-Backup"
        Write-ADLog "Khong tim thay o dia rieng. Dung $BackupRoot (cung o he thong - kem an toan hon)." "WARN"
    }
}

$stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
$jobDir  = Join-Path $BackupRoot $stamp
$logFile = Join-Path $jobDir "backup.log"
New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
Start-Transcript -Path $logFile -Append | Out-Null

$targetDriveLetter = Split-Path -Qualifier $jobDir          # vi du "D:"
$freeGB = [math]::Round(((Get-PSDrive -Name $targetDriveLetter.TrimEnd(":")).Free / 1GB), 1)
Write-ADLog "Thu muc sao luu: $jobDir  (con trong $freeGB GB)" "INFO"
if ($freeGB -lt 10 -and -not $SkipSystemState) {
    Write-ADLog "Dung luong trong duoi 10 GB. Buoc System State co the that bai." "WARN"
}

# ==============================================================================
# BUOC 1 - SYSTEM STATE BACKUP (wbadmin) - quan trong nhat
# ==============================================================================
if ($SkipSystemState) {
    Write-ADLog "Bo qua System State theo tham so -SkipSystemState." "WARN"
    [void]$script:StepResults.Add([pscustomobject]@{
        Step = "System State (wbadmin)"; Status = "SKIPPED"; Seconds = 0; Detail = "-SkipSystemState"
    })
} else {
    Invoke-BackupStep -Name "System State (wbadmin)" -Critical -Action {
        $feature = Get-WindowsFeature -Name Windows-Server-Backup
        if (-not $feature.Installed) {
            Write-ADLog "Cai dat tinh nang Windows-Server-Backup..." "INFO"
            Install-WindowsFeature -Name Windows-Server-Backup -IncludeManagementTools | Out-Null
        }

        # Neu o dich cung la o he thong, phai bat AllowSSBToAnyVolume
        if ($targetDriveLetter -ieq $env:SystemDrive) {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\wbengine\SystemStateBackup"
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            Set-ItemProperty -Path $regPath -Name "AllowSSBToAnyVolume" -Value 1 -Type DWord
            Write-ADLog "Da bat AllowSSBToAnyVolume de ghi System State len o he thong." "WARN"
        }

        Write-ADLog "Dang chay wbadmin (buoc nay lau nhat, khoang 5-20 phut)..." "INFO"
        $out = & wbadmin start systemstatebackup -backupTarget:$targetDriveLetter -quiet 2>&1
        $out | Out-File (Join-Path $jobDir "wbadmin-systemstate.txt") -Encoding UTF8
        if ($LASTEXITCODE -ne 0) {
            throw "wbadmin tra ve ma loi $LASTEXITCODE. Xem wbadmin-systemstate.txt."
        }
        "Kho luu: $targetDriveLetter\WindowsImageBackup"
    }
}

# ==============================================================================
# BUOC 2 - IFM SNAPSHOT (ntdsutil): ban sao NTDS.dit + registry
# ==============================================================================
Invoke-BackupStep -Name "IFM snapshot NTDS.dit (ntdsutil)" -Action {
    $ifmDir = Join-Path $jobDir "ntds-ifm"
    if (Test-Path $ifmDir) { Remove-Item $ifmDir -Recurse -Force }
    $cmd = "activate instance ntds`r`nifm`r`ncreate full `"$ifmDir`"`r`nquit`r`nquit`r`n"
    $out = $cmd | & ntdsutil 2>&1
    $out | Out-File (Join-Path $jobDir "ntdsutil-ifm.txt") -Encoding UTF8
    $dit = Join-Path $ifmDir "Active Directory\ntds.dit"
    if (-not (Test-Path $dit)) { throw "Khong tao duoc ntds.dit. Xem ntdsutil-ifm.txt." }
    "ntds.dit: $([math]::Round((Get-Item $dit).Length / 1MB, 1)) MB"
}

# ==============================================================================
# BUOC 3 - LDIF EXPORT (ldifde): phuc hoi tung doi tuong
# ==============================================================================
Invoke-BackupStep -Name "LDIF export (ldifde)" -Action {
    $ldifDir = Join-Path $jobDir "ldif"
    New-Item -ItemType Directory -Path $ldifDir -Force | Out-Null

    # Cac thuoc tinh do he thong sinh ra - phai bo di thi file .ldf moi import lai duoc
    $omit = "objectGUID,objectSid,uSNCreated,uSNChanged,whenCreated,whenChanged," +
            "pwdLastSet,badPasswordTime,lastLogon,lastLogoff,lastLogonTimestamp," +
            "badPwdCount,logonCount,dSCorePropagationData,memberOf,primaryGroupID"

    $exports = @(
        @{ File = "full-domain.ldf";   Base = $baseDN;                    Filter = "(objectClass=*)" },
        @{ File = "users.ldf";         Base = $baseDN;                    Filter = "(&(objectClass=user)(objectCategory=person))" },
        @{ File = "groups.ldf";        Base = $baseDN;                    Filter = "(objectClass=group)" },
        @{ File = "ous.ldf";           Base = $baseDN;                    Filter = "(objectClass=organizationalUnit)" },
        @{ File = "computers.ldf";     Base = $baseDN;                    Filter = "(objectClass=computer)" },
        @{ File = "configuration.ldf"; Base = "CN=Configuration,$baseDN"; Filter = "(objectClass=*)" }
    )

    foreach ($e in $exports) {
        $path = Join-Path $ldifDir $e.File
        & ldifde -f "$path" -d "$($e.Base)" -p subtree -r "$($e.Filter)" -o "$omit" -j "$ldifDir" 2>&1 |
            Out-File (Join-Path $ldifDir "ldifde-console.txt") -Append -Encoding UTF8
    }
    $count = @(Get-ChildItem $ldifDir -Filter *.ldf).Count
    "Da xuat $count file .ldf (LUU Y: LDIF khong chua mat khau user)"
}

# ==============================================================================
# BUOC 4 - CSV EXPORT: doi chieu nhanh bang Excel
# ==============================================================================
Invoke-BackupStep -Name "CSV export (users/groups/OU/computers)" -Action {
    $csvDir = Join-Path $jobDir "csv"
    New-Item -ItemType Directory -Path $csvDir -Force | Out-Null

    Get-ADUser -Filter * -Properties DisplayName, UserPrincipalName, Enabled, Description,
            Title, Department, EmailAddress, PasswordNeverExpires, PasswordLastSet, LastLogonDate, MemberOf |
        Select-Object SamAccountName, DisplayName, UserPrincipalName, Enabled, Title, Department,
            EmailAddress, PasswordNeverExpires, PasswordLastSet, LastLogonDate, DistinguishedName,
            @{ N = "MemberOf"; E = { ($_.MemberOf | ForEach-Object { ($_ -split ",")[0] -replace "^CN=", "" }) -join "; " } } |
        Export-Csv (Join-Path $csvDir "users.csv") -NoTypeInformation -Encoding UTF8

    Get-ADGroup -Filter * -Properties Description, GroupScope, GroupCategory, Members |
        Select-Object Name, SamAccountName, GroupScope, GroupCategory, Description,
            @{ N = "MemberCount"; E = { @($_.Members).Count } }, DistinguishedName |
        Export-Csv (Join-Path $csvDir "groups.csv") -NoTypeInformation -Encoding UTF8

    # Bang thanh vien nhom day du (group -> member), dung de dung lai phan quyen
    $membership = foreach ($g in (Get-ADGroup -Filter *)) {
        foreach ($m in (Get-ADGroupMember -Identity $g -ErrorAction SilentlyContinue)) {
            [pscustomobject]@{
                Group      = $g.Name
                Member     = $m.SamAccountName
                MemberType = $m.objectClass
                MemberDN   = $m.distinguishedName
            }
        }
    }
    $membership | Export-Csv (Join-Path $csvDir "group-membership.csv") -NoTypeInformation -Encoding UTF8

    Get-ADOrganizationalUnit -Filter * -Properties Description, ProtectedFromAccidentalDeletion |
        Select-Object Name, DistinguishedName, Description, ProtectedFromAccidentalDeletion |
        Export-Csv (Join-Path $csvDir "ous.csv") -NoTypeInformation -Encoding UTF8

    Get-ADComputer -Filter * -Properties OperatingSystem, LastLogonDate, Enabled |
        Select-Object Name, DNSHostName, OperatingSystem, Enabled, LastLogonDate, DistinguishedName |
        Export-Csv (Join-Path $csvDir "computers.csv") -NoTypeInformation -Encoding UTF8

    "users=$(@(Get-ADUser -Filter *).Count), groups=$(@(Get-ADGroup -Filter *).Count), ou=$(@(Get-ADOrganizationalUnit -Filter *).Count)"
}

# ==============================================================================
# BUOC 5 - GROUP POLICY: backup GPO + bao cao HTML + bang link
# ==============================================================================
Invoke-BackupStep -Name "Group Policy (GPO)" -Action {
    Import-Module GroupPolicy -ErrorAction Stop
    $gpoDir = Join-Path $jobDir "gpo"
    New-Item -ItemType Directory -Path $gpoDir -Force | Out-Null

    $gpos = Backup-GPO -All -Path $gpoDir -Domain $domainDNS
    Get-GPOReport -All -ReportType Html -Path (Join-Path $gpoDir "all-gpo-report.html") -Domain $domainDNS

    # Backup-GPO KHONG luu thong tin GPO dang link vao OU nao -> phai ghi rieng
    $links = foreach ($gpo in (Get-GPO -All -Domain $domainDNS)) {
        [xml]$rpt = Get-GPOReport -Guid $gpo.Id -ReportType Xml -Domain $domainDNS
        foreach ($l in $rpt.GPO.LinksTo) {
            [pscustomobject]@{
                GpoName    = $gpo.DisplayName
                GpoId      = $gpo.Id
                LinkedTo   = $l.SOMPath
                Enabled    = $l.Enabled
                NoOverride = $l.NoOverride
            }
        }
    }
    $links | Export-Csv (Join-Path $gpoDir "gpo-links.csv") -NoTypeInformation -Encoding UTF8
    "Da sao luu $(@($gpos).Count) GPO + bao cao HTML + bang link"
}

# ==============================================================================
# BUOC 6 - DNS: export tung zone
# ==============================================================================
Invoke-BackupStep -Name "DNS Server zones" -Action {
    Import-Module DnsServer -ErrorAction Stop
    $dnsDir = Join-Path $jobDir "dns"
    New-Item -ItemType Directory -Path $dnsDir -Force | Out-Null

    $zones = Get-DnsServerZone | Where-Object { -not $_.IsAutoCreated }
    foreach ($z in $zones) {
        $fileName = "backup_$($z.ZoneName).dns"
        # Export-DnsServerZone luon ghi vao %SystemRoot%\System32\dns
        Export-DnsServerZone -Name $z.ZoneName -FileName $fileName -ErrorAction SilentlyContinue | Out-Null
        $src = Join-Path "$env:SystemRoot\System32\dns" $fileName
        if (Test-Path $src) {
            Move-Item $src (Join-Path $dnsDir $fileName) -Force
        }
    }
    $zones | Select-Object ZoneName, ZoneType, IsDsIntegrated, IsReverseLookupZone, DynamicUpdate |
        Export-Csv (Join-Path $dnsDir "zones.csv") -NoTypeInformation -Encoding UTF8
    Get-DnsServerForwarder | Out-File (Join-Path $dnsDir "forwarders.txt") -Encoding UTF8
    "Da export $(@($zones).Count) zone"
}

# ==============================================================================
# BUOC 7 - SYSVOL: script logon, template policy
# ==============================================================================
Invoke-BackupStep -Name "SYSVOL (robocopy)" -Action {
    $sysvolSrc = "$env:SystemRoot\SYSVOL\domain"
    if (-not (Test-Path $sysvolSrc)) { throw "Khong tim thay $sysvolSrc" }
    $sysvolDst = Join-Path $jobDir "sysvol"
    $rcLog = Join-Path $jobDir "robocopy-sysvol.txt"
    & robocopy $sysvolSrc $sysvolDst /MIR /R:2 /W:2 /NFL /NDL /NP /LOG:"$rcLog" | Out-Null
    # Robocopy: ma thoat tu 8 tro len moi la loi that su
    if ($LASTEXITCODE -ge 8) { throw "robocopy loi, ma thoat $LASTEXITCODE. Xem robocopy-sysvol.txt." }
    "$(Get-FolderSizeMB $sysvolDst) MB"
}

# ==============================================================================
# BUOC 8 - METADATA + SUC KHOE HE THONG
# ==============================================================================
Invoke-BackupStep -Name "Metadata + dcdiag/repadmin" -Action {
    $metaDir = Join-Path $jobDir "metadata"
    New-Item -ItemType Directory -Path $metaDir -Force | Out-Null

    $info = [ordered]@{
        BackupTime            = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        BackupHost            = $env:COMPUTERNAME
        OperatingSystem       = (Get-CimInstance Win32_OperatingSystem).Caption
        DomainDNS             = $domain.DNSRoot
        DomainNetBIOS         = $domain.NetBIOSName
        DomainDN              = $baseDN
        DomainMode            = "$($domain.DomainMode)"
        ForestMode            = "$($forest.ForestMode)"
        SchemaVersion         = (Get-ADObject "CN=Schema,CN=Configuration,$baseDN" -Properties objectVersion).objectVersion
        PDCEmulator           = $domain.PDCEmulator
        RIDMaster             = $domain.RIDMaster
        InfrastructureMaster  = $domain.InfrastructureMaster
        SchemaMaster          = $forest.SchemaMaster
        DomainNamingMaster    = $forest.DomainNamingMaster
        DomainControllers     = @((Get-ADDomainController -Filter *).HostName)
        Sites                 = @((Get-ADReplicationSite -Filter *).Name)
        RecycleBinEnabled     = [bool](Get-ADOptionalFeature -Filter 'Name -like "Recycle Bin Feature"').EnabledScopes
        TombstoneLifetimeDays = (Get-ADObject "CN=Directory Service,CN=Windows NT,CN=Services,CN=Configuration,$baseDN" -Properties tombstoneLifetime).tombstoneLifetime
    }
    $info | ConvertTo-Json -Depth 4 | Out-File (Join-Path $metaDir "domain-info.json") -Encoding UTF8

    Get-ADDefaultDomainPasswordPolicy | Out-File (Join-Path $metaDir "password-policy.txt") -Encoding UTF8
    Get-ADDomainController -Filter * |
        Select-Object HostName, Site, IPv4Address, IsGlobalCatalog, OperationMasterRoles |
        Format-List | Out-File (Join-Path $metaDir "domain-controllers.txt") -Encoding UTF8

    & dcdiag /v          2>&1 | Out-File (Join-Path $metaDir "dcdiag.txt") -Encoding UTF8
    & repadmin /showrepl 2>&1 | Out-File (Join-Path $metaDir "repadmin-showrepl.txt") -Encoding UTF8
    & netdom query fsmo  2>&1 | Out-File (Join-Path $metaDir "fsmo.txt") -Encoding UTF8

    "Schema v$($info.SchemaVersion), tombstone $($info.TombstoneLifetimeDays) ngay"
}

# ==============================================================================
# BUOC 9 - NEN (tuy chon)
# ==============================================================================
if ($Compress) {
    Invoke-BackupStep -Name "Nen thanh file .zip" -Action {
        $sizeMB = Get-FolderSizeMB $jobDir
        if ($sizeMB -gt 1500) {
            throw "Thu muc $sizeMB MB - vuot gioi han 2 GB cua Compress-Archive tren PowerShell 5.1."
        }
        $zip = "$jobDir.zip"
        Compress-Archive -Path "$jobDir\*" -DestinationPath $zip -CompressionLevel Optimal -Force
        "$([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB -> $zip"
    }
}

# ==============================================================================
# BUOC 10 - DON DEP BAN CU
# ==============================================================================
if ($RetentionDays -gt 0) {
    Invoke-BackupStep -Name "Don dep ban cu (> $RetentionDays ngay)" -Action {
        $cutoff = (Get-Date).AddDays(-$RetentionDays)
        $removed = 0
        Get-ChildItem -Path $BackupRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{8}-\d{6}$' -and $_.Name -ne $stamp -and $_.CreationTime -lt $cutoff } |
            ForEach-Object { Remove-Item $_.FullName -Recurse -Force; $removed++ }
        Get-ChildItem -Path $BackupRoot -Filter "*.zip" -ErrorAction SilentlyContinue |
            Where-Object { $_.CreationTime -lt $cutoff } |
            ForEach-Object { Remove-Item $_.FullName -Force; $removed++ }

        if (-not $SkipSystemState -and $KeepSystemStateVersions -gt 0) {
            & wbadmin delete systemstatebackup -keepVersions:$KeepSystemStateVersions -quiet 2>&1 | Out-Null
        }
        "Da xoa $removed muc cu; giu $KeepSystemStateVersions ban System State"
    }
}

# ==============================================================================
# TONG KET
# ==============================================================================
$totalMB = Get-FolderSizeMB $jobDir
$failed  = @($script:StepResults | Where-Object { $_.Status -eq "FAILED" })
$skipped = @($script:StepResults | Where-Object { $_.Status -eq "SKIPPED" })

$manifest = [ordered]@{
    Domain      = $domainDNS
    BackupHost  = $env:COMPUTERNAME
    Timestamp   = $stamp
    Folder      = $jobDir
    SizeMB      = $totalMB
    SystemState = if ($SkipSystemState) { "skipped" } else { "$targetDriveLetter\WindowsImageBackup" }
    Steps       = $script:StepResults
}
$manifest | ConvertTo-Json -Depth 5 | Out-File (Join-Path $jobDir "manifest.json") -Encoding UTF8

Write-Host ""
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "                        KET QUA SAO LUU" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor DarkCyan
$script:StepResults |
    Format-Table @{ N = "Buoc";       E = { $_.Step } },
                 @{ N = "Trang thai"; E = { $_.Status } },
                 @{ N = "Giay";       E = { $_.Seconds } },
                 @{ N = "Chi tiet";   E = { if ($_.Detail.Length -gt 60) { $_.Detail.Substring(0, 57) + "..." } else { $_.Detail } } } -AutoSize

Write-Host ""
Write-ADLog "Thu muc: $jobDir  ($totalMB MB)" "INFO"
if (-not $SkipSystemState) {
    Write-ADLog "System State: $targetDriveLetter\WindowsImageBackup" "INFO"
}

if ($failed.Count -gt 0) {
    Write-ADLog "CO $($failed.Count) BUOC QUAN TRONG THAT BAI: $(($failed.Step) -join ', ')" "ERROR"
    Stop-Transcript | Out-Null
    exit 2
} elseif ($skipped.Count -gt 0) {
    Write-ADLog "Hoan tat, nhung bo qua $($skipped.Count) buoc: $(($skipped.Step) -join ', ')" "WARN"
    Stop-Transcript | Out-Null
    exit 0
} else {
    Write-ADLog "SAO LUU TOAN BO AD THANH CONG - tat ca cac buoc deu OK." "SUCCESS"
    Stop-Transcript | Out-Null
    exit 0
}
