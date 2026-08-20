@echo off
chcp 65001 >nul
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0bin\daily-refresh.ps1" %*
set "STAVE_EXIT_CODE=%ERRORLEVEL%"
if not "%STAVE_EXIT_CODE%"=="0" echo Daily refresh failed with exit code %STAVE_EXIT_CODE%.
pause
exit /b %STAVE_EXIT_CODE%
