# ==============================================================================
# 01-Install-ADDS.ps1 - Cai dat AD DS va nang cap Domain Controller iai.io.vn
# ==============================================================================
#requires -Version 5.1

[CmdletBinding()]
param (
    [switch]$NoReboot,
    [switch]$SkipIpCheck
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

Write-ADLog "=== BAT DAU QUA TRINH CAI DAT AD DS CHO DOMAIN: $($global:ADConfig.DomainName) ===" "INFO"

# 3. Kiem tra may chu hien tai da la Domain Controller chua
try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($cs.DomainRole -ge 4) { # 4 = Backup Domain Controller, 5 = Primary Domain Controller
        Write-ADLog "May chu nay hien da la Domain Controller ($($cs.Domain)). Khong can cai dat lai!" "WARN"
        Write-ADLog "Ban co the chuyen sang buoc tiep theo: .\02-Init-AdminUsers.ps1" "INFO"
        exit 0
    }
} catch {
    Write-ADLog "Khong the kiem tra ComputerSystem DomainRole: $_" "WARN"
}

# 4. Kiem tra cau hinh IP (Khuyen nghi IP tinh cho Domain Controller)
if (-not $SkipIpCheck) {
    Write-ADLog "Kiem tra cau hinh mang cua may chu..." "INFO"
    $activeAdapters = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
        $_.InterfaceAlias -notmatch "Loopback" -and $_.IPAddress -ne "127.0.0.1" 
    }

    if ($activeAdapters) {
        foreach ($nic in $activeAdapters) {
            $dhcpStatus = (Get-NetIPInterface -InterfaceIndex $nic.InterfaceIndex -AddressFamily IPv4).Dhcp
            Write-ADLog "Card mang [$($nic.InterfaceAlias)]: IP = $($nic.IPAddress), DHCP = $dhcpStatus" "INFO"
            if ($dhcpStatus -eq "Enabled") {
                Write-ADLog "[CANH BAO] Card mang $($nic.InterfaceAlias) dang su dung DHCP." "WARN"
                Write-ADLog "Active Directory Domain Controller nen su dung IP Tinh (Static IP) de tranh loi DNS/DC." "WARN"
                Write-ADLog "Neu day la moi truong Lab va router da gan IP Co dinh (Static Lease), ban co the tiep tuc." "INFO"
            }
        }
    }
}

# 5. Cai dat Windows Features: AD DS, DNS, RSAT
Write-ADLog "Kiem tra va cai dat tinh nang AD-Domain-Services, RSAT-ADDS, DNS..." "INFO"
$features = @("AD-Domain-Services", "RSAT-ADDS", "DNS")
foreach ($feature in $features) {
    $state = Get-WindowsFeature -Name $feature
    if (-not $state.Installed) {
        Write-ADLog "Dang cai dat feature: $feature ..." "INFO"
        $installResult = Install-WindowsFeature -Name $feature -IncludeManagementTools
        if ($installResult.Success) {
            Write-ADLog "Cai dat thanh cong feature: $feature" "SUCCESS"
        } else {
            Write-ADLog "Loi khi cai dat feature $feature : $($installResult.ExitCode)" "ERROR"
            exit 1
        }
    } else {
        Write-ADLog "Feature $feature da duoc cai dat san." "SUCCESS"
    }
}

# 6. Thuc hien nang cap Domain Controller (Install-ADDSForest)
Write-ADLog "Chuan bi tao Rung (Forest) moi voi ten mien: $($global:ADConfig.DomainName) (NetBIOS: $($global:ADConfig.NetbiosName))" "INFO"

# Chuyen mat khau DSRM thanh SecureString
$secDSRMPassword = ConvertTo-SecureString $global:ADConfig.DSRMPassword -AsPlainText -Force

$installParams = @{
    DomainName                    = $global:ADConfig.DomainName
    DomainNetbiosName             = $global:ADConfig.NetbiosName
    ForestMode                    = $global:ADConfig.ForestMode
    DomainMode                    = $global:ADConfig.DomainMode
    SafeModeAdministratorPassword = $secDSRMPassword
    InstallDns                    = $true
    CreateDnsDelegation           = $false
    DatabasePath                  = "$env:SystemRoot\NTDS"
    LogPath                       = "$env:SystemRoot\NTDS"
    SysvolPath                    = "$env:SystemRoot\SYSVOL"
    NoRebootOnCompletion         = [bool]$NoReboot
    Force                         = $true
}

Write-ADLog "Dang thuc thi lenh Install-ADDSForest... (Qua trinh nay mat khoang 2-5 phut)" "INFO"

try {
    Install-ADDSForest @installParams
    Write-ADLog "Khoi tao Forest va nang cap Domain Controller thanh cong!" "SUCCESS"

    if ($NoReboot) {
        Write-ADLog "Tham so -NoReboot duoc bat. Vui long khoi dong lai may tinh thu cong de hoan tat!" "WARN"
    } else {
        Write-ADLog "May chu se tu dong khoi dong lai de ap dung cau hinh Domain Controller..." "INFO"
    }
} catch {
    Write-ADLog "Loi trong qua trinh Install-ADDSForest: $_" "ERROR"
    exit 1
}
