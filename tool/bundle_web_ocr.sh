#!/usr/bin/env bash
# Bundles the in-browser OCR engine into build/web/ocr: PaddleOCR (PP-OCRv4
# mobile detection + recognition models) on ONNX Runtime Web, wrapped by
# tool/web_ocr/entry.js. Everything is served from the app itself (no CDN),
# so scanning works offline once loaded. Run after `flutter build web`.
#   ./tool/bundle_web_ocr.sh [build/web]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mkdir -p "${1:-build/web}" && cd "${1:-build/web}" && pwd)/ocr"
SRC="$ROOT/tool/web_ocr"
( cd "$SRC" && npm ci --no-audit --no-fund --silent )
rm -rf "$OUT" && mkdir -p "$OUT"
( cd "$SRC" && npx esbuild entry.js --bundle --format=esm --platform=browser \
    --external:path --external:fs --external:crypto \
    --alias:onnxruntime-web=onnxruntime-web/wasm \
    --minify --log-level=warning --outfile="$OUT/jcocr.js" )
cp "$SRC"/node_modules/onnxruntime-web/dist/ort-wasm-simd-threaded.{wasm,mjs} "$OUT/"
cp "$SRC"/node_modules/@gutenye/ocr-models/assets/{ch_PP-OCRv4_det_infer.onnx,ch_PP-OCRv4_rec_infer.onnx,ppocr_keys_v1.txt} "$OUT/"
echo "Bundled OCR assets into $OUT ($(du -sh "$OUT" | cut -f1))"
