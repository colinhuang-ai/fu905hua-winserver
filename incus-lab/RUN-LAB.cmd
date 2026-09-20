@echo off
setlocal
title Incus + QEMU Lab - 2 Incus Containers + 1 QEMU VM tren Ubuntu WSL
echo ============================================================
echo   Cai dat lab: 2 node Incus + 1 VM QEMU (1 CPU) tren Ubuntu WSL
echo   Se hoi mat khau sudo cua Ubuntu - go binh thuong roi Enter
echo ============================================================
echo.

set LABDIR=/mnt/c/Training/Windows19S/incus-lab

wsl.exe -- bash -lc "cd %LABDIR% && sed -i 's/\r$//' *.sh && chmod +x *.sh && ./run-all.sh"
if errorlevel 79 goto done
if errorlevel 78 goto restart
goto done

:restart
echo.
echo [*] Dang khoi dong lai WSL de bat systemd (mat vai giay)...
wsl.exe --shutdown
timeout /t 8 /nobreak >nul
echo [*] Chay lai cai dat...
wsl.exe -- bash -lc "cd %LABDIR% && ./run-all.sh"

:done
echo.
if errorlevel 1 (echo === CO LOI - xem file lab-setup.log trong thu muc nay ===) else (echo === HOAN TAT - go: wsl  roi  sudo incus list ===)
echo.
pause
