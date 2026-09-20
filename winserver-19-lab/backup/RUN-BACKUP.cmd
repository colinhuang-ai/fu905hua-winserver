@echo off
chcp 65001 >nul
:: ==============================================================================
:: RUN-BACKUP.cmd - Menu sao luu Active Directory iai.io.vn
:: ==============================================================================

:: Kiem tra quyen Administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Vui long chay file nay bang quyen Administrator!
    echo Chuot phai vao RUN-BACKUP.cmd va chon "Run as administrator".
    echo.
    pause
    exit /b 1
)

:MENU
cls
echo ==============================================================================
echo             SAO LUU ACTIVE DIRECTORY DOMAIN: iai.io.vn
echo ==============================================================================
echo.
echo  [1] Sao luu DAY DU       (System State + NTDS + GPO + DNS + SYSVOL)
echo  [2] Sao luu NHANH        (bo qua System State - chi vai phut)
echo  [3] Sao luu DAY DU + nen thanh file .zip
echo  [4] Xem danh sach cac ban System State dang co (wbadmin)
echo  [5] Xem huong dan sao luu / phuc hoi (README.md)
echo  [0] Thoat
echo.
set /p choice="Nhap lua chon cua ban [0-5]: "

if "%choice%"=="1" goto FULL
if "%choice%"=="2" goto FAST
if "%choice%"=="3" goto ZIP
if "%choice%"=="4" goto LIST
if "%choice%"=="5" goto README
if "%choice%"=="0" exit /b 0
goto MENU

:FULL
cls
echo ==============================================================================
echo Dang sao luu DAY DU. Buoc System State co the mat 5-20 phut, vui long doi...
echo ==============================================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp001-Backup-AD.ps1"
pause
goto MENU

:FAST
cls
echo ==============================================================================
echo Dang sao luu NHANH (KHONG co System State - khong du de dung lai ca DC).
echo ==============================================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp001-Backup-AD.ps1" -SkipSystemState
pause
goto MENU

:ZIP
cls
echo ==============================================================================
echo Dang sao luu DAY DU va nen ket qua thanh file .zip...
echo ==============================================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp001-Backup-AD.ps1" -Compress
pause
goto MENU

:LIST
cls
echo ==============================================================================
echo Danh sach cac ban System State hien co tren may:
echo ==============================================================================
wbadmin get versions
echo.
pause
goto MENU

:README
notepad "%~dp0README.md"
goto MENU
