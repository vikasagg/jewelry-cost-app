/// <reference path="../pb_data/types.d.ts" />

// Stock export import from the app (needs a staff PIN), and the default
// address and mobile for suppliers added in the admin panel.
routerAdd("POST", "/api/damiyaas/stock-import", (e) => {
  return require(`${__hooks}/stock_import_lib.js`).importItems(e);
});

onRecordCreate((e) => {
  require(`${__hooks}/stock_import_lib.js`).supplierDefaults(e.record);
  e.next();
}, "suppliers");
