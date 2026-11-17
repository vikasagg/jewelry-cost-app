/// <reference path="../pb_data/types.d.ts" />

// Keeps sales_register_lines (one row per register line) in step with
// each saved register.
onRecordAfterCreateSuccess((e) => {
  require(`${__hooks}/app_data_lib.js`).registerLines(e.app, e.record);
  e.next();
}, "sales_registers");

onRecordAfterUpdateSuccess((e) => {
  require(`${__hooks}/app_data_lib.js`).registerLines(e.app, e.record);
  e.next();
}, "sales_registers");

// Shared counters (bill numbers): every phone gets a different number.
routerAdd("POST", "/api/damiyaas/counter", (e) => {
  return require(`${__hooks}/app_data_lib.js`).counter(e);
});
