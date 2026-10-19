/// <reference path="../pb_data/types.d.ts" />

// Keeps stock_count_items (one row per counted item) in step with each
// saved stock day.
onRecordAfterCreateSuccess((e) => {
  require(`${__hooks}/stock_lines.js`).sync(e.app, e.record);
  e.next();
}, "stock_days");

onRecordAfterUpdateSuccess((e) => {
  require(`${__hooks}/stock_lines.js`).sync(e.app, e.record);
  e.next();
}, "stock_days");
