# Shop PC database (PocketBase)

Daily stock counts are kept on each phone (they work offline) and shared
through PocketBase running on the shop PC. Tested with PocketBase 0.40.5.

## One-time setup

1. Put the `pb_migrations` folder from this zip next to `pocketbase.exe`
   (e.g. `C:\pocketbase\pb_migrations\1760900000_damiyaas_stock.js`).
2. Stop PocketBase (Ctrl+C) and start it again so phones on the Wi-Fi can
   reach it:

   ```
   pocketbase serve --http=0.0.0.0:8090
   ```

   On start it creates two tables, once:
   * `staff` — Anil (7678405443), Bhavna (9205348300), Tanish (9667725005)
   * `stock_days` — one record per counted day

3. Find the PC address with `ipconfig` (IPv4 Address, e.g. `192.168.1.10`).
   Reserve this address in the Wi-Fi router so it does not change.

## Connect the phones

* **Android app:** Stock Reconciliation → server icon (top right) → enter
  `192.168.1.10:8090` → Test → Save.
* **iPhone / any browser:** unzip `damiyaas-web-for-shop-pc.zip` (from the
  same release) into a `pb_public` folder next to `pocketbase.exe`, restart
  PocketBase, then open `http://192.168.1.10:8090` on the phone and use
  Share → Add to Home Screen. It connects to the PC by itself.

The status bar on the Stock screen shows "Synced with shop PC", or
"Shop PC not reachable — saved on this phone" (counts are sent when the PC
is back).

## Staff

Add, edit or deactivate staff in the admin panel: `http://127.0.0.1:8090/_/`
→ `staff`. Phones pick up changes on their next sync (every 20 seconds).

## Notes

* Anyone on the shop Wi-Fi can read and save stock counts (no login yet);
  deleting a day is only possible in the admin panel. Keep the Wi-Fi
  password private.
* The manager PIN is still set per phone.
* Back up the `pb_data` folder (all data) regularly.
