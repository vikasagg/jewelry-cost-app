#!/usr/bin/env bash
# Vendors Tesseract.js + English model into build/web/ocr so web scanning
# works fully offline (no CDN). Run after `flutter build web`.
#   ./tool/bundle_web_ocr.sh [build/web]
set -euo pipefail
OUT="${1:-build/web}/ocr"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
( cd "$TMP" && npm pack --silent tesseract.js@5.1.1 tesseract.js-core@5.1.1 @tesseract.js-data/eng@1.0.0 >/dev/null )
for f in "$TMP"/*.tgz; do d="${f%.tgz}"; mkdir -p "$d"; tar xzf "$f" -C "$d"; done
mkdir -p "$OUT/core" "$OUT/lang"
cp "$TMP"/tesseract.js-5.1.1/package/dist/{tesseract.min.js,worker.min.js} "$OUT/"
# LSTM-only builds (plain + SIMD) are all Tesseract.js uses with the default OEM.
cp "$TMP"/tesseract.js-core-5.1.1/package/tesseract-core{,-simd}-lstm.{js,wasm,wasm.js} "$OUT/core/"
cp "$TMP"/tesseract.js-data-eng-1.0.0/package/4.0.0_best_int/eng.traineddata.gz "$OUT/lang/"
echo "Bundled OCR assets into $OUT ($(du -sh "$OUT" | cut -f1))"
