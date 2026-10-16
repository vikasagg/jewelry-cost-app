# Smart Jewellery Cost Calculator

A cross-platform Flutter app (Android, iOS, web) for jewellery retailers in India.
Staff scan a printed jewellery tag, check what was read, and get a cost
breakdown in ₹ with every step shown. It needs no backend and no login, and the
calculations work offline.

## Features

| Area | What it does |
| --- | --- |
| **Gold rate setup** | Asks for the 14K / 18K / 22K / 24K rates per gram on first launch. Values must be positive numbers. The rates and the time they were last changed are saved on the device. Open the settings from any screen with the ₹ icon in the app bar. |
| **Dashboard** | A large *Scan Jewellery Tag* button, plus Manual Entry, Gold Rate Settings, Scan History, the current rates and when they were last updated. |
| **Tag scanner** | Take a photo with the camera or pick one from the gallery (upload on web). A **built-in crop screen** (with rotate) opens straight away; it works offline on every platform. The image is then optionally enhanced (greyscale, contrast, sharpen) and OCR runs. If the tag was photographed **sideways or upside down**, other orientations are tried automatically. You can preview the result, then **Retake**, **Crop**, **Rotate**, **Rescan** or **Continue**. |
| **Stone lines** | A tag can list several diamond or stone groups, e.g. `DIA\0.38\700`, `DIA\0.11\750`, `FANCY CUT\2.13\850`. Each becomes its own line with weight (ct), its own ₹/ct rate, a Diamond / Other stone switch, and the **tag code** (700, 750…). The code is shown for reference and **never used as a rate**. The ₹/ct you enter is remembered **per code** and pre-filled the next time that code appears; an unknown code is never given another code's rate. |
| **Weight balance** | When a tag shows gross weight (G.Wt) and net weight (N.Wt), the app checks gross − net against the total stone carats × 0.2 g. A match confirms the readings (and resolves OCR merging like `2.13850` → 2.13 ct, code 850). A mismatch flags the weights for confirmation. If stone weight is implied but no stone lines were read, the scanner says so. |
| **Tag parser** | Reads GW / G.W. / Gold Wt / Gross Gold Weight / NW, DW / DIA / Dia Wt, FANCY CUT, SW / Stone Wt / CS / CZ / Pearl…, `LABEL\\weight\\code` lines (including OCR misreads of `\\` as `N`, `)`, `1` or nothing), purity in the form 18K / 18KT / 22K916 / *Purity: 14*, and the hallmark numbers 585 / 750 / 916 / 999. It also reads MC / Making (₹ amount or %), Wastage / VA (% or grams), tag number or item code, and item name. **It never fills in a guess without telling you:** if the OCR swapped characters, read a comma as a decimal point, gave a value that is too large or in the wrong unit, found conflicting values or GW and NW together, or the purity came only from a hallmark number, that field is highlighted and must be confirmed before you can calculate. |
| **Editable details** | Every field can be edited. The saved rate for the selected purity is applied automatically. Gross weight is kept apart from gold weight, and stone weight is **never** subtracted from gold weight. |
| **Pricing engine** | A separate, pure-Dart module (`lib/pricing/pricing_engine.dart`) that works in whole paise, so line items always add up exactly. |
| **Results** | Jewellery details, then the full breakdown: rate, gold, diamond, stone, wastage, making, subtotal, taxable subtotal (listing which parts are taxed), each GST line, and the total. Actions: Edit Details, Recalculate (with current rates), Scan Another, Save to History, Share / Export (share sheet or clipboard). |
| **History** | Saved on the device and searchable by tag number or description. Open, edit and recalculate, or delete a record. Each record keeps a **copy of all four gold rates** used at the time, so later rate changes never alter past results. |
| **Storage protection** | Data sits in a Hive box encrypted with AES-256. The key is held in the Android Keystore or the iOS Keychain (flutter_secure_storage; WebCrypto on web). |

### Formulas

```
Gold value    = gold weight (g) × saved rate/g for the selected purity   (no extra purity factor)
Diamond value = diamond weight (ct) × diamond rate/ct     — rate required, or diamond explicitly excluded
Stone value   = stone weight (ct) × stone rate/ct         — 0 allowed, or stone excluded
Wastage       = gold value × % / 100   OR   wastage weight (g) × gold rate/g   (one method only)
Making        = fixed ₹                OR   gold value × % / 100
Subtotal      = gold + diamond + stone + wastage + making
GST           = taxable base × GST % / 100   (you choose which parts are taxed; making charges can have their own rate)
Total         = subtotal + GST
```

No GST rate is built in. You enter it, and the app remembers the last GST
settings (along with the diamond and stone rates) to fill in the next item.
Amounts use Indian grouping, for example `₹1,25,450.00`.

## Project layout

```
lib/
  core/money.dart              paise rounding + Indian currency formatting
  models/                      Purity, GoldRates, JewelleryInput, GstConfig, CalculationRecord
  pricing/pricing_engine.dart  validation + calculation (pure Dart, no Flutter)
  ocr/tag_parser.dart          OCR text → fields with confidence (pure Dart)
  ocr/ocr_service*.dart        ML Kit (Android/iOS, on-device) | Tesseract.js (web)
  ocr/image_enhancer.dart      orientation, resize, greyscale, contrast, sharpen
  data/                        encrypted Hive store + repositories (rates, defaults, history)
  ui/                          theme, widgets, screens
test/                          engine, parser, formatting, history, end-to-end widget tests
samples/tags/                  sample printed tags (.png to scan, .txt used by tests)
tool/                          sample-tag generator, web OCR bundler
```

## Setup

You need Flutter 3.32 or newer (it was developed on 3.47.7 / Dart 3.13).

```bash
flutter pub get
flutter test                 # 90+ tests: engine, parser (incl. real-photo OCR output), formatting, history, widget flow
flutter analyze
```

### Android

```bash
flutter run -d android        # or: flutter build apk --release
```
- `minSdk` is 23 (needed by ML Kit and secure storage). The ML Kit OCR model
  is declared in `AndroidManifest.xml` and downloaded when the app is
  installed, so scanning works offline.
- Before publishing, add your own release signing config in `android/app/build.gradle.kts`.

### iOS

```bash
cd ios && pod install && cd ..
flutter run -d ios            # or: flutter build ipa
```
- The deployment target is iOS 15.5, which ML Kit requires. It is set in
  `ios/Podfile` and in the Xcode project.
- The camera and photo library permission messages are in `Info.plist`.
- ML Kit runs on arm64 only, so use a real device or an arm64 simulator.

### Web

```bash
flutter build web --release
./tool/bundle_web_ocr.sh      # optional: vendors Tesseract.js + English model (~17 MB) for offline scanning
# serve build/web with any static server, e.g.:
python3 -m http.server -d build/web 8080
```
- Without the bundle step, the first scan downloads Tesseract.js and the English
  model from jsDelivr, and the browser caches them after that.
- Camera capture on web opens the device camera on phones. On desktop browsers
  it opens a file picker.
- On web, how well the stored data is protected depends on the browser's
  WebCrypto support and site-data settings.

## Sample tags

`samples/tags/` has seven sample tags, each as a `.png` (to scan) and a `.txt`
(used by the tests):

| File | What it shows |
| --- | --- |
| `01_diamond_ring_18k` | Typical diamond ring: G.W./D.W./S.W., fixed MC with ₹ thousands separator |
| `02_bangle_22k` | `22K916`, % making, % wastage |
| `03_pendant_14k` | Lower-case labels, `.35 ct`, `1500/-` |
| `04_coin_24k` | Value printed on the line after its label |
| `05_ocr_noise_chain` | O/0 confusion, wastage in grams (VA) |
| `06_gross_and_net` | GW and NW together, so both are flagged for confirmation |
| `07_missing_gold` | No gold weight or purity, which must be entered by hand |
| `08_real_14k_diamond` | **Real photo** (`.jpg`): sideways tag on a wood-grain table, G.Wt/N.Wt, three `LABEL\\weight\\code` stone lines. Tests include the actual Tesseract output for this photo. |

To regenerate the images, run `python3 tool/make_sample_tags.py` (needs Pillow).

## Verification status

- All automated tests pass (`flutter test`), and `flutter analyze` reports no issues.
- A web release build was run in Chromium with real Tesseract OCR. The sample
  tags scanned correctly into the form, and the total, saving to history and
  persistence after a page reload all worked. The real photo
  `08_real_14k_diamond.jpg` (sideways tag on a wood-grain table) was read fully
  correctly after cropping, with the rotation detected automatically.
- With Tesseract (web), **cropping tightly to the tag matters**. On the
  uncropped photo, the wood-grain texture hid the stone lines.
- The Android and iOS native builds were **not** compiled in the development
  sandbox, because the Android SDK and Xcode were unavailable. Build them
  locally with the commands above.
