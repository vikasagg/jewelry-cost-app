# Smart Jewellery Cost Calculator

A cross-platform Flutter app (Android, iOS, web) for jewellery retailers in India.
Staff scan a printed jewellery tag, check what was read, and get a cost
breakdown in ₹ with every step shown. It needs no backend and no login, and the
calculations work offline.

## Features

| Area | What it does |
| --- | --- |
| **Gold rate setup** | Asks only for the **24K** rate (per 10 g by default) on first launch. The other purities are derived from it: 22K = 92%, 20K = 84%, 18K = 76%, 14K = 60%, 9K = 40% of 24K, and are shown before saving. The value must be a positive number. The rates and the time they were last changed are saved on the device. Open the settings from any screen with the ₹ icon in the app bar. |
| **Dashboard** | A large *Scan Jewellery Tag* button, plus Manual Entry, Gold Rate Settings, Scan History, the current rates and when they were last updated. |
| **Tag scanner** | Take a photo with the camera or pick one from the gallery (upload on web). A **built-in crop screen** (with rotate, starting on the full photo) opens straight away; it works offline on every platform. The image is then optionally enhanced (greyscale, contrast, sharpen) and OCR runs. If the tag was photographed **sideways or upside down**, other orientations are tried automatically. You can preview the result, then **Retake**, **Crop**, start a **New** scan, or **Continue**. Unclear readings are checked right there: each highlighted value says why, with **Edit** and **Confirm** (or **Confirm all**); a missing gold weight is entered there too. **Continue** unlocks once nothing is left to check, so the details form opens clean. |
| **Stone lines** | A tag can list several diamond or stone groups, e.g. `DIA\0.38\700`, `DIA\0.11\750`, `FANCY CUT\2.13\850`. Each becomes its own line with its weight (ct), a Diamond / Other stone switch, and its own ₹/ct rate. The number after the weight is the **rate code**: **₹ per carat = code × 100** (700 → ₹70,000/ct, 750 → ₹75,000/ct, 850 → ₹85,000/ct). The rate is filled in automatically and stays editable. The ×100 multiplier can be changed in Gold Rate Settings. |
| **Weight balance** | When a tag shows gross weight (G.Wt) and net weight (N.Wt), the app checks gross − net against the total stone carats × 0.2 g. A match confirms the readings (and resolves OCR merging like `2.13850` → 2.13 ct, code 850). A mismatch flags the weights for confirmation. If stone weight is implied but no stone lines were read, the scanner says so. |
| **Tag parser** | Reads GW / G.W. / Gold Wt / Gross Gold Weight / NW, DW / DIA / Dia Wt, FANCY CUT, SW / Stone Wt / CS / CZ / Pearl…, `LABEL\\weight\\code` lines (including OCR misreads of `\\` as `N`, `)`, `1` or nothing), purity in the form 9K / 18K / 18KT / 20K / 22K916 / *Purity: 14*, and the hallmark numbers 375 / 585 / 750 / 833 / 916 / 999. It also reads MC / Making (₹ amount or %), Wastage / VA (% or grams), tag number or item code, and item name. **It never fills in a guess without telling you:** if the OCR swapped characters, read a comma as a decimal point, gave a value that is too large or in the wrong unit, found conflicting values or GW and NW together, or the purity came only from a hallmark number, that field is highlighted and must be confirmed before you can calculate. |
| **Editable details** | Every field can be edited. If the tag prints no purity, **18K** is preselected (with a note). Diamond, stone and polki sections start empty and only show lines the tag lists; **Add** creates a line with ₹70,000/ct for diamond and polki (stone rate left blank). The saved rate for the selected purity is applied automatically. Gross weight is kept apart from gold weight, and stone weight is **never** subtracted from gold weight. |
| **Pricing engine** | A separate, pure-Dart module (`lib/pricing/pricing_engine.dart`) that works in whole paise, so line items always add up exactly. |
| **Results** | Each detail and price line has its own icon (gold, diamond, stone, polki, labour, GST…). A **gold purity drop-down** (defaults to the purity read from the tag) re-prices the estimate for any other purity and updates the saved record. Jewellery details, then the full breakdown: rate, gold, diamond, stone, wastage, making, subtotal, taxable subtotal (listing which parts are taxed), each GST line, and the total. Actions: Edit Details, Recalculate (with current rates), Scan Another, Save to History, Share / Export (share sheet or clipboard). |
| **History** | Saved on the device and searchable by tag number or description. Scanned estimates keep a small photo of the tag (JPEG, ~360 px, stored apart from the record so the list stays fast), shown in the list and at the top of the cost summary (not in the WhatsApp image, so rate codes stay private). Open, edit and recalculate, or delete a record. Each record keeps a **copy of all four gold rates** used at the time, so later rate changes never alter past results. |
| **Storage protection** | Data sits in a Hive box encrypted with AES-256. The key is held in the Android Keystore or the iOS Keychain (flutter_secure_storage; WebCrypto on web). |

### Daily Stock Summary (stock reconciliation)

The app opens on a chooser: **Price Calculator** or **Stock Reconciliation**
(also reachable from the price dashboard as *Daily Stock Summary*). Stock
counting is completely separate: it never reads or changes gold rates,
prices or saved estimates, and it has its own history.

- **Categories:** Ring (LGR, GGR), Earring (GE, DE), Pendant, Pendant Set,
  Necklace Set, Bangle, Tikka, Diamond Set, Chain, Chashma, Watch, Nath.
  Counts are entered on a large numeric keypad; category (Ring, Earring)
  and grand totals update live.
- **Reconciliation:** each line shows the previous day's *verified* closing,
  today's expected opening (that closing + approved adjustments), the
  physical count and the difference. Differences are highlighted and take a
  remark. The very first count has nothing to compare with and becomes the
  opening stock once verified.
- **Approval:** employee submits → a manager verifies with the manager PIN
  (stored hashed). Verified counts are locked and become the next day's
  opening. Stock adjustments and reopening a verified day also need the PIN
  (reopening is refused once a later day was verified on top of it).
  Earlier closing balances are never changed to hide a difference.
- **Audit trail:** every count, remark, submission, adjustment, approval,
  reopening and share is logged with time and person.
- **Sharing:** *Share on WhatsApp* opens WhatsApp / WhatsApp Web with the
  formatted summary pre-filled (pick the chat and send); *Share PDF report*
  shares a one-page PDF; the share icon sends plain text.
- Stored locally (encrypted, works offline) under `stock_*` keys.

### Formulas

```
Gold value    = gold weight (g) × rate per gram for the selected purity   (no extra purity factor)
                purity rate = 24K rate × 92% (22K) / 84% (20K) / 76% (18K) / 60% (14K) / 40% (9K)
                rates can be entered per 10 g (default) or per 1 g; per-10 g rates are divided by 10 internally
Diamond value = diamond weight (ct) × diamond rate/ct     — rate required, or diamond explicitly excluded
Stone value   = stone weight (ct) × stone rate/ct         — 0 allowed, or stone excluded
Making        = ₹ per gram × gold (net) weight   (default, e.g. 1200 × 1.35 g = ₹1,620)
                OR fixed ₹   OR   gold value × % / 100
Subtotal      = gold + diamond + stone + making
GST           = taxable base × GST % / 100   (GST defaults to 3%, editable per item)   (you choose which parts are taxed; making charges can have their own rate)
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
  ocr/ocr_service*.dart        ML Kit (Android/iOS, on-device) | PaddleOCR (web)
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
./tool/bundle_web_ocr.sh      # required for scanning: bundles PaddleOCR (needs Node.js; ~39 MB, ~21 MB gzipped)
# serve build/web with any static server, e.g.:
python3 -m http.server -d build/web 8080
```
- Web scanning uses **PaddleOCR** (PP-OCRv4 mobile models on ONNX Runtime
  Web, wrapped by `tool/web_ocr/entry.js`). It finds the text areas first, so a
  busy background (e.g. a wood-grain table) is ignored, and it corrects
  sideways or upside-down tags itself in one pass. The models start loading as
  soon as the app opens, so the first scan does not wait for them.
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
| `08_real_14k_diamond` | **Real photo** (`.jpg`): sideways tag on a wood-grain table, G.Wt/N.Wt, three `LABEL\\weight\\code` stone lines. Tests include the actual Tesseract and PaddleOCR output for this photo. |

To regenerate the images, run `python3 tool/make_sample_tags.py` (needs Pillow).

## Verification status

- All automated tests pass (`flutter test`), and `flutter analyze` reports no issues.
- A web release build was run in Chromium with real PaddleOCR. The real photo
  `08_real_14k_diamond.jpg` (sideways, uncropped, on a wood-grain table) is
  read fully correctly in every orientation, and sample tags scan in about
  1.5–3 s from tapping *Use crop* to the detected values (the previous
  Tesseract engine took about 34 s on the real photo and needed a tight crop).
- The Android and iOS native builds were **not** compiled in the development
  sandbox, because the Android SDK and Xcode were unavailable. Build them
  locally with the commands above.
