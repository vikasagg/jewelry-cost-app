#!/usr/bin/env bash
# Starts the ERP on the shop server (local mode: works with no internet).
# Counters, phones and tablets on the shop Wi-Fi open http://<server-ip>:8080
set -e
cd "$(dirname "$0")"
[ -f target/jewellery-erp.jar ] || mvn -B -q -DskipTests package
export ERP_DATA_DIR="${ERP_DATA_DIR:-$PWD/data}"
exec java -jar target/jewellery-erp.jar
