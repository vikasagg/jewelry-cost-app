#!/usr/bin/env bash
# Starts Swarn-OS on the shop server (local mode: works with no internet).
# Counters, phones and tablets on the shop Wi-Fi open http://<server-ip>:8080
set -e
cd "$(dirname "$0")"
[ -f target/swarn-os.jar ] || mvn -B -q -DskipTests package
export SWARN_DATA_DIR="${SWARN_DATA_DIR:-$PWD/data}"
exec java -jar target/swarn-os.jar
