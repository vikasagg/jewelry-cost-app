DAMIYAAS JEWELERS - SHOP PC (Windows)
=====================================

Everything to run the app and its database on this PC.

FIRST TIME
1. Unzip this folder to C:\damiyaas  (or over your existing C:\pocketbase
   folder - your data in pb_data is kept).
2. Double-click "Start Damiyaas.bat".
   - If Windows asks, click "More info" > "Run anyway".
   - If the firewall asks, tick "Private networks" and click "Allow".
3. The app opens in the browser at http://127.0.0.1:8090
4. Admin panel (see all records): http://127.0.0.1:8090/_/
   The first time it asks you to create an admin email and password.

PHONES (same Wi-Fi as this PC)
- The black window shows "On phones: http://192.168.x.x:8090".
- iPhone / any browser: open that address. Safari: Share > Add to Home Screen.
- Android app: tap the line at the bottom of the home screen, enter
  192.168.x.x:8090, Test, Save.
- Reserve this PC's address in the Wi-Fi router so it never changes.

EVERY DAY
- Double-click "Start Damiyaas.bat" and keep the window open.
- To start it with Windows: Win+R, type  shell:startup , and put a
  shortcut to "Start Damiyaas.bat" there.

BACKUP
- All data is in the pb_data folder. Copy it regularly (USB / Google Drive).

UPDATING
- Unzip the new version over this folder (pb_data is not in the zip, so
  your data stays), then start again.

FOLDERS
- pocketbase.exe   the database server
- pb_public        the app (served to browsers)
- pb_migrations    creates the tables
- pb_hooks         server rules (PINs, bill numbers, register lines)
- pb_data          your data (created on first start)
