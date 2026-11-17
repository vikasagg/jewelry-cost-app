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
