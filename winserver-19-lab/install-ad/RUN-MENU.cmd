@echo off
chcp 65001 >nul
:: ==============================================================================
:: RUN-MENU.cmd - Menu dieu khien trien khai Active Directory iai.io.vn
:: ==============================================================================

:: Kiem tra quyen Administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Vui long chay file nay bang quyen Administrator!
    echo Chuot phai vao RUN-MENU.cmd va chon "Run as administrator".
    echo.
    pause
    exit /b 1
)

:MENU
cls
echo ==============================================================================
echo       TRIEN KHAI ACTIVE DIRECTORY DOMAIN SERVER: iai.io.vn
echo ==============================================================================
echo.
echo  [1] Buoc 1: Cai dat AD DS va thiet lap Domain Controller (Tu dong reboot)
echo  [2] Buoc 2: Khoi tao cay OU va 2 User Admin (hoangpt, hoangxuan)
echo  [3] Buoc 3: Kiem tra toan dien he thong (Dich vu, DNS, Domain, Users)
echo  [4] Xem / Sua file cau hinh 00-Config.ps1
echo  [5] Xem huong dan su dung chi tiet (README.md)
echo  [0] Thoat
echo.
set /p choice="Nhap lua chon cua ban [0-5]: "

if "%choice%"=="1" goto STEP1
if "%choice%"=="2" goto STEP2
if "%choice%"=="3" goto STEP3
if "%choice%"=="4" goto CONFIG
if "%choice%"=="5" goto README
if "%choice%"=="0" exit /b 0
goto MENU

:STEP1
cls
echo ==============================================================================
echo Dang khoi chay Buoc 1: Cai dat AD DS va nang cap Domain Controller iai.io.vn...
echo ==============================================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp001-Install-ADDS.ps1"
pause
goto MENU

:STEP2
cls
echo ==============================================================================
echo Dang khoi chay Buoc 2: Khoi tao OU va 2 Admin: hoangpt, hoangxuan...
echo ==============================================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp002-Init-AdminUsers.ps1"
pause
goto MENU

:STEP3
cls
echo ==============================================================================
echo Dang khoi chay Buoc 3: Kiem tra toan dien he thong AD DS...
echo ==============================================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp003-Verify-AD.ps1"
pause
goto MENU

:CONFIG
notepad "%~dp000-Config.ps1"
goto MENU

:README
notepad "%~dp0README.md"
goto MENU
