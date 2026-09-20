@echo off
setlocal
set OUT=%~dp0wsl-diag.log
title Chan doan WSL
echo Dang thu thap thong tin WSL... (khoang 30 giay)
echo.

echo ===== ver ===== > "%OUT%"
ver >> "%OUT%" 2>&1

echo. >> "%OUT%"
echo ===== wsl --version ===== >> "%OUT%"
wsl.exe --version >> "%OUT%" 2>&1

echo. >> "%OUT%"
echo ===== wsl --status ===== >> "%OUT%"
wsl.exe --status >> "%OUT%" 2>&1

echo. >> "%OUT%"
echo ===== wsl -l -v ===== >> "%OUT%"
wsl.exe -l -v >> "%OUT%" 2>&1

echo. >> "%OUT%"
echo ===== sc query LxssManager ===== >> "%OUT%"
sc query LxssManager >> "%OUT%" 2>&1

echo. >> "%OUT%"
echo ===== optional features (VM Platform / WSL / Hyper-V) ===== >> "%OUT%"
powershell -NoProfile -Command "Get-WindowsOptionalFeature -Online | Where-Object FeatureName -match 'Linux|VirtualMachinePlatform|Hyper-V' | Select-Object FeatureName,State | Format-Table -AutoSize | Out-String" >> "%OUT%" 2>&1

echo. >> "%OUT%"
echo ===== test: wsl -- echo ===== >> "%OUT%"
wsl.exe -- echo HELLO-FROM-WSL >> "%OUT%" 2>&1
echo exitcode=%ERRORLEVEL% >> "%OUT%"

echo. >> "%OUT%"
echo ===== test: wsl -d Ubuntu -- uname -a ===== >> "%OUT%"
wsl.exe -d Ubuntu -- uname -a >> "%OUT%" 2>&1
echo exitcode=%ERRORLEVEL% >> "%OUT%"

echo. >> "%OUT%"
echo ===== test: wsl -d Ubuntu -u root -- cat /etc/os-release ===== >> "%OUT%"
wsl.exe -d Ubuntu -u root -- cat /etc/os-release >> "%OUT%" 2>&1
echo exitcode=%ERRORLEVEL% >> "%OUT%"

echo.
echo Xong. Ket qua nam trong: %OUT%
echo Bao cho Claude biet la da chay xong DIAG.cmd
echo.
pause
