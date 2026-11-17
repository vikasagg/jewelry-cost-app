# Shop PC database (PocketBase)

Everything the app records is kept on each phone (it works offline) and
saved on the shop PC in PocketBase, which shares it with the other phones:
stock counts, Price Calculator estimates (with the tag photo), bills, Today's
Sales registers, gold & silver prices and the gold rate. Tested with
PocketBase 0.40.5.

## One-time setup

1. Put the `pb_migrations` and `pb_hooks` folders from this zip next to
   `pocketbase.exe` (e.g. `C:\pocketbase\pb_migrations\…js` and
   `C:\pocketbase\pb_hooks\…js`). When updating, copy them over the old
   ones; already-applied steps are skipped.
2. Stop PocketBase (Ctrl+C) and start it again so phones on the Wi-Fi can
   reach it:

   ```
   pocketbase serve --http=0.0.0.0:8090
   ```

   On start it creates the tables, once:
   * `staff` — Anil (7678405443), Bhavna (9205348300), Tanish (9667725005)
   * `stock_days` — one record per counted day: date, status,
     `counted_by`, `approved_by`, `approved_at`, totals (expected, counted,
     difference) and the full day
   * `stock_count_items` — one row per counted item per day: item,
     expected, counted, difference, remark, keypad working, counted by,
     approved by, status (kept up to date by `pb_hooks`)
   * `estimates` — every saved estimate: tag, item, purity, weights, total,
     and the tag `photo`
   * `bills` — bill number, customer, phone, address, payment, items, total
     (bill numbers come from the PC, so two phones never repeat one)
   * `sales_registers` and `sales_register_lines` — Today's Sales, one row
     per register line
   * `metal_prices` — gold 24K per 10 g and silver per kg, per day
   * `settings` — the gold rate used by the Price Calculator, counters
   * `stock_items` — the stock export, one row per item; **Tag No is
     unique**. Columns follow the export (item, date, pcs, gross/net/
     diamond/stone/gold weight, design, hallmark, labour, MRP, diamond and
     stone details, supplier) plus `status` (in_stock)
   * `suppliers` — every supplier in the export, linked from stock_items;
     new suppliers get the address **Delhi** and mobile **9717000000**

   Each of these has `data` (the full record as the app keeps it) and
   `deleted`: a record deleted on a phone stays on the PC, marked deleted.

3. Find the PC address with `ipconfig` (IPv4 Address, e.g. `192.168.1.10`).
   Reserve this address in the Wi-Fi router so it does not change.

## Connect the phones

* **Android app:** home screen → tap the line at the bottom ("Saved on this
  phone only…") → enter `192.168.1.10:8090` → Test → Save. Everything
  already on the phone is sent to the PC once.
* **iPhone / any browser:** unzip `damiyaas-web-for-shop-pc.zip` (from the
  same release) into a `pb_public` folder next to `pocketbase.exe`, restart
  PocketBase, then open `http://192.168.1.10:8090` on the phone and use
  Share → Add to Home Screen. It connects to the PC by itself.

The home screen shows "Saved on the shop PC", or "Shop PC not reachable ·
saved on this phone, sent later" (changes are sent when the PC is back).

## Stock items

Stock Reconciliation → list icon "Stock items": search the `stock_items`
table by Tag No, item or supplier and see each item's details.

**Import the stock export:** on the same screen tap **Import stock from
Excel** (the green spreadsheet icon, also at the top right), pick the
`.xlsx` export, choose your name and enter your PIN. New Tag Nos are
added, existing ones updated (never duplicated), and new suppliers get the
address Delhi and mobile 9717000000. Run it again with a newer export at
any time. Edit suppliers' address and mobile in the admin panel.

## Tag lookup (Manual Jewellery Entry)

Type the Tag No and press Enter (or tap the search icon): the app finds it
in `stock_items` and fills in gross and gold weight, purity (from Gold Std,
when the export has it), diamonds, stones / polki and making charges.
Rates in the export are read like tag rate codes (diamond and polki × 100
per ct, stones per piece); everything stays editable.

## Personal PINs

* Every staff member creates their own PIN (4–8 digits): Stock screen →
  key icon "My PIN", or the first time they start a count.
* Starting a count needs the counter's PIN; approving (verify,
  adjustment, reopen) needs the approver's PIN.
* The person who counted cannot approve the same count — the app and the
  PC both refuse it.
* PINs are stored on the PC only as salted hashes (hidden from the API).
  5 wrong tries lock that person for 5 minutes.
* Forgotten PIN: admin panel → `staff` → that person → clear `pin_hash`,
  then they create a new one.

## Staff

Add, edit or deactivate staff in the admin panel: `http://127.0.0.1:8090/_/`
→ `staff`. Phones pick up changes on their next sync (every 20 seconds).

## Notes

* Anyone on the shop Wi-Fi can read and save the shop's records (no login
  yet); deleting is only possible in the admin panel. Keep the Wi-Fi
  password private.
* Back up the `pb_data` folder (all data) regularly.
