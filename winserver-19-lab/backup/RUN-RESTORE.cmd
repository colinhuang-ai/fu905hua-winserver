@echo off
chcp 65001 >nul
:: ==============================================================================
:: RUN-RESTORE.cmd - Menu phuc hoi Active Directory iai.io.vn
:: ==============================================================================

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Vui long chay file nay bang quyen Administrator!
    echo Chuot phai vao RUN-RESTORE.cmd va chon "Run as administrator".
    echo.
    pause
    exit /b 1
)

set PS=powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp002-Restore-AD.ps1"

:MENU
cls
echo ==============================================================================
echo            PHUC HOI ACTIVE DIRECTORY DOMAIN: iai.io.vn
echo ==============================================================================
echo.
echo  [1] Xem danh sach cac ban sao luu dang co
echo  [2] Phuc hoi user/group bi xoa tu AD Recycle Bin   (nhanh, an toan nhat)
echo  [3] Import lai object tu file LDIF                 (khi chua bat Recycle Bin)
echo  [4] Gan lai thanh vien nhom tu group-membership.csv
echo  [5] Phuc hoi Group Policy + link lai vao OU
echo  [6] Phuc hoi DNS zone
echo  [7] Phuc hoi SYSVOL (logon script, policy files)
echo  [8] Phuc hoi CA DOMAIN CONTROLLER (System State - can DSRM)
echo  [9] Kiem tra lai he thong sau khi phuc hoi
echo  [0] Thoat
echo.
echo  Meo: moi lua chon deu in ra danh sach va hoi xac nhan truoc khi thay doi.
echo.
set /p choice="Nhap lua chon cua ban [0-9]: "

if "%choice%"=="1" goto LIST
if "%choice%"=="2" goto RECYCLE
if "%choice%"=="3" goto LDIF
if "%choice%"=="4" goto MEMBER
if "%choice%"=="5" goto GPO
if "%choice%"=="6" goto DNS
if "%choice%"=="7" goto SYSVOL
if "%choice%"=="8" goto SYSTEMSTATE
if "%choice%"=="9" goto VERIFY
if "%choice%"=="0" exit /b 0
goto MENU

:LIST
cls
%PS% -Mode List
pause
goto MENU

:RECYCLE
cls
set /p who="Ten user/group can phuc hoi (Enter = xem tat ca): "
if "%who%"=="" (
    %PS% -Mode RecycleBin
) else (
    %PS% -Mode RecycleBin -Identity "%who%"
)
pause
goto MENU

:LDIF
cls
echo Cac file LDIF thuong dung: users.ldf, groups.ldf, ous.ldf, computers.ldf
set /p who="Ten object can import lai (Enter = TOAN BO file): "
set /p ldf="Ten file LDIF [users.ldf]: "
if "%ldf%"=="" set ldf=users.ldf
if "%who%"=="" (
    %PS% -Mode Objects -LdifFile "%ldf%"
) else (
    %PS% -Mode Objects -LdifFile "%ldf%" -Identity "%who%"
)
pause
goto MENU

:MEMBER
cls
set /p who="Chi gan lai cho user nao (Enter = tat ca): "
if "%who%"=="" (
    %PS% -Mode Membership
) else (
    %PS% -Mode Membership -Identity "%who%"
)
pause
goto MENU

:GPO
cls
%PS% -Mode GPO -RelinkGpo
pause
goto MENU

:DNS
cls
%PS% -Mode DNS
pause
goto MENU

:SYSVOL
cls
%PS% -Mode SYSVOL
pause
goto MENU

:SYSTEMSTATE
cls
echo ==============================================================================
echo  CANH BAO: Buoc nay ghi de toan bo System State va khoi dong lai may chu.
echo  Chi chay duoc khi may dang o Directory Services Restore Mode (DSRM).
echo  Neu chua o DSRM, script se huong dan cach vao.
echo ==============================================================================
echo.
set /p ver="Phien ban can phuc hoi (MM/DD/YYYY-HH:MM, Enter = chi xem danh sach): "
if "%ver%"=="" (
    %PS% -Mode SystemState
) else (
    %PS% -Mode SystemState -Version "%ver%"
)
pause
goto MENU

:VERIFY
cls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\install-ad\03-Verify-AD.ps1"
pause
goto MENU
