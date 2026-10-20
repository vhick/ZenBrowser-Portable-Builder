@echo off
setlocal
cd /d "%~dp0"
echo ==============================================================
echo  ZEN PORTABLE - APPLY SHORTCUT PREVENTION (BEST EFFORT)
echo  Close Zen completely before running this tool.
echo ==============================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Apply-Zen-Startup-Fix.ps1" -Root "%~dp0.."
set "result=%ERRORLEVEL%"
echo.
if not "%result%"=="0" echo Shortcut prevention was NOT applied. See the error above.
pause
exit /b %result%
