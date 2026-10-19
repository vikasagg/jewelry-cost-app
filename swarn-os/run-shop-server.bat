@echo off
REM Starts Swarn-OS on the shop server (local mode: works with no internet).
REM Counters, phones and tablets on the shop Wi-Fi open http://<server-ip>:8080
cd /d "%~dp0"
if not exist target\swarn-os.jar call mvn -B -q -DskipTests package
if "%SWARN_DATA_DIR%"=="" set SWARN_DATA_DIR=%CD%\data
java -jar target\swarn-os.jar
