@echo off
title Damiyaas Jewelers - shop PC server
cd /d "%~dp0"
echo.
echo  Damiyaas Jewelers is starting on this PC.
echo  Keep this window open while the shop is working. Close it to stop.
echo.
echo  On this PC:   http://127.0.0.1:8090
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do (
  for /f "tokens=*" %%b in ("%%a") do echo  On phones:    http://%%b:8090   ^(same Wi-Fi^)
)
echo  Admin panel:  http://127.0.0.1:8090/_/
echo.
rem Open the app in the browser once the server is up.
start "" /min cmd /c "ping -n 4 127.0.0.1 >nul & start http://127.0.0.1:8090"
pocketbase.exe serve --http=0.0.0.0:8090
echo.
echo  The server has stopped.
pause
