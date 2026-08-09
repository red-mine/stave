@echo off
chcp 65001 >nul
set "PATH=C:\Ruby34-x64\bin;%PATH%"
set "TDX_DATA_PATH=C:\new_tdx\vipdoc"
cd /d "C:\Users\huntl\work\stave"
echo [%date% %time%] Starting daily refresh...
bundle exec rails daily_refresh
echo [%date% %time%] Done.
pause
