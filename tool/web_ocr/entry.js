// In-browser OCR for the web build: PaddleOCR (PP-OCRv4 mobile) on ONNX
// Runtime Web. Bundled by ../bundle_web_ocr.sh into build/web/ocr/.
//
// Exposes window.jcOcr = { warmUp(), recognize(imageUrl) → text }.
// Text is detected first (so background texture such as wood grain is
// ignored), then each line is read. Sideways or upside-down tags are
// handled here: a few sample lines are read both ways up and the whole
// image is rotated once, instead of running OCR for every rotation.
import '@gutenye/ocr-browser'; // registers the browser backend
import * as ort from 'onnxruntime-web'; // aliased to onnxruntime-web/wasm
import { Detection, Recognition } from './node_modules/@gutenye/ocr-common/build/models/index.js';

const base = new URL('.', import.meta.url).href; // …/ocr/
ort.env.wasm.wasmPaths = base;
ort.env.wasm.numThreads = 1; // GitHub Pages is not cross-origin isolated

const MAX_SIDE = 1024; // longest side used for detection: speed vs small text
let engine;

function load() {
  engine ??= (async () => {
    const models = {
      detectionPath: base + 'ch_PP-OCRv4_det_infer.onnx',
      recognitionPath: base + 'ch_PP-OCRv4_rec_infer.onnx',
      dictionaryPath: base + 'ppocr_keys_v1.txt',
    };
    const [detection, recognition] = await Promise.all([
      Detection.create({ models }),
      Recognition.create({ models }),
    ]);
    return { detection, recognition };
  })().catch((e) => {
    engine = undefined; // allow a retry (e.g. after going online)
    throw e;
  });
  return engine;
}

async function loadImage(url) {
  const img = new Image();
  img.src = url;
  await img.decode();
  return img;
}

/** Draws [img] scaled to MAX_SIDE. */
function draw(img, deg = 0) {
  const W = img.naturalWidth || img.width;
  const H = img.naturalHeight || img.height;
  const s = Math.min(1, MAX_SIDE / Math.max(W, H));
  const w = Math.round(W * s), h = Math.round(H * s);
  const cv = document.createElement('canvas');
  cv.width = deg % 180 ? h : w;
  cv.height = deg % 180 ? w : h;
  const ctx = cv.getContext('2d');
  ctx.translate(cv.width / 2, cv.height / 2);
  ctx.rotate((deg * Math.PI) / 180);
  ctx.drawImage(img, -w / 2, -h / 2, w, h);
  const d = ctx.getImageData(0, 0, cv.width, cv.height);
  return { data: d.data, width: d.width, height: d.height };
}

const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
const boxSize = (box) => ({ w: dist(box[0], box[1]), h: dist(box[1], box[2]) });

async function meanConfidence(recognition, lineImages) {
  if (!lineImages.length) return 0;
  const lines = await recognition.run(lineImages);
  const chars = lines.reduce((n, l) => n + l.text.length, 0);
  return lines.reduce((s, l) => s + l.mean * l.text.length, 0) / Math.max(chars, 1);
}

/** Line images turned upside down. */
async function flipped(lineImages) {
  return Promise.all(lineImages.map(async (li) => {
    const { data, width, height } = li.image;
    const out = new Uint8ClampedArray(data.length);
    for (let i = 0, j = data.length - 4; i < data.length; i += 4, j -= 4) {
      out[j] = data[i]; out[j + 1] = data[i + 1]; out[j + 2] = data[i + 2]; out[j + 3] = data[i + 3];
    }
    const Img = li.image.constructor;
    return { box: li.box, image: new Img({ data: out, width, height }) };
  }));
}

async function recognize(url) {
  const { detection, recognition } = await load();
  const img = await loadImage(url);
  const det = await detection.run(draw(img, 0));
  const { lineImages } = det;
  if (!lineImages.length) return '';

  // Orientation: are the text boxes mostly tall (tag photographed
  // sideways)? Then read the biggest lines as cropped and upside down.
  const tall = lineImages.filter((l) => { const s = boxSize(l.box); return s.h > s.w * 1.5; });
  const vertical = tall.length * 2 > lineImages.length;
  const pool = vertical ? tall : lineImages;
  const sample = [...pool]
    .sort((a, b) => { const x = boxSize(a.box), y = boxSize(b.box); return y.w * y.h - x.w * x.h; })
    .slice(0, 3);
  const asIs = await meanConfidence(recognition, sample);
  // Confident reads are the right way up; only doubtful ones are compared
  // with the upside-down version.
  const upsideDown = asIs >= 0.85 ? 0 : await meanConfidence(recognition, await flipped(sample));
  // Tall crops are turned 90° anticlockwise by the line splitter, so text
  // that reads correctly that way needs the image rotated 270°.
  const deg = vertical ? (asIs >= upsideDown ? 270 : 90) : (asIs >= upsideDown ? 0 : 180);
  // Rather than detecting again on a rotated image, move each line's box
  // into the rotated frame (so lines are ordered top to bottom) and turn
  // the line images that read upside down.
  const W = det.resizedImageWidth, H = det.resizedImageHeight;
  const turn = {
    0: (p) => p,
    90: ([x, y]) => [H - y, x],
    180: ([x, y]) => [W - x, H - y],
    270: ([x, y]) => [y, W - x],
  }[deg];
  const flip = deg === 90 || deg === 180;
  const ready = (flip ? await flipped(lineImages) : lineImages).map((l) => ({
    image: l.image,
    box: l.box.map(turn),
  }));

  const lines = await recognition.run(ready);
  return lines.map((l) => l.text).join('\n');
}

window.jcOcr = { warmUp: () => load().then(() => true), recognize };
