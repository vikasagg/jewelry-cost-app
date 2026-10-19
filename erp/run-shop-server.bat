@echo off
REM Starts the ERP on the shop server (local mode: works with no internet).
REM Counters, phones and tablets on the shop Wi-Fi open http://<server-ip>:8080
cd /d "%~dp0"
if not exist target\jewellery-erp.jar call mvn -B -q -DskipTests package
if "%ERP_DATA_DIR%"=="" set ERP_DATA_DIR=%CD%\data
java -jar target\jewellery-erp.jar
