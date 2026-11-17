// Stock export import (see stock_import.pb.js).
const DEFAULT_ADDRESS = "Delhi";
const DEFAULT_MOBILE = "9717000000";

const NUMBERS = [
  "pcs", "gross_wt", "net_wt", "dia_wt", "stone_wt", "gold_wt",
  "labour_per_gm", "labour_rs", "mrp", "costing", "dia_pcs",
  "dia_detail_wt", "dia_rate", "dia_value", "stn_pcs", "stn_detail_wt",
  "stn_rate", "stn_value",
];
const TEXTS = [
  "item_name", "design", "certificate", "remarks", "colour", "clarity",
  "size", "supplier_name", "dia_item", "dia_quality", "dia_size",
  "stn_item", "stn_quality", "stn_size", "gold_std",
];

function supplierDefaults(rec) {
  if (!rec.getString("address")) rec.set("address", DEFAULT_ADDRESS);
  if (!rec.getString("mobile")) rec.set("mobile", DEFAULT_MOBILE);
  // New suppliers are active (untick in the admin panel to retire one).
  rec.set("active", true);
}

module.exports = {
  supplierDefaults,

  // Body {name, pin, items: [{tag_no, …}]}: creates or updates items by
  // tag_no and creates missing suppliers. All or nothing.
  importItems: (e) => {
    const body = e.requestInfo().body || {};
    const pins = require(`${__hooks}/staff_pin_lib.js`);
    const staff = pins.find(e.app, body.name);
    if (!staff) return e.json(404, { message: "Unknown staff member" });
    const ok = pins.verify(e.app, staff, body.pin);
    if (!ok.ok) return e.json(ok.status, { message: ok.message });

    const items = Array.isArray(body.items) ? body.items : [];
    if (!items.length) return e.json(400, { message: "No items to import" });
    let created = 0, updated = 0, newSuppliers = 0;
    const now = new DateTime();
    e.app.runInTransaction((tx) => {
      const itemCol = tx.findCollectionByNameOrId("stock_items");
      const supCol = tx.findCollectionByNameOrId("suppliers");
      const supplierIds = {};
      const supplierId = (name) => {
        if (!name) return "";
        if (supplierIds[name]) return supplierIds[name];
        let s;
        try {
          s = tx.findFirstRecordByFilter("suppliers", "name = {:n}", { n: name });
        } catch (_) {
          s = new Record(supCol);
          s.set("name", name);
          s.set("address", DEFAULT_ADDRESS);
          s.set("mobile", DEFAULT_MOBILE);
          s.set("active", true);
          tx.save(s);
          newSuppliers++;
        }
        supplierIds[name] = s.id;
        return s.id;
      };
      for (const it of items) {
        const tag = String(it.tag_no || "").trim().toUpperCase();
        if (!tag) continue;
        let r;
        try {
          r = tx.findFirstRecordByFilter("stock_items", "tag_no = {:t}", { t: tag });
          updated++;
        } catch (_) {
          r = new Record(itemCol);
          r.set("tag_no", tag);
          r.set("status", "in_stock");
          created++;
        }
        for (const f of TEXTS) r.set(f, String(it[f] == null ? "" : it[f]));
        for (const f of NUMBERS) r.set(f, Number(it[f]) || 0);
        r.set("hallmark", !!it.hallmark);
        r.set("entry_date", it.entry_date ? it.entry_date + " 00:00:00.000Z" : "");
        r.set("supplier", supplierId(String(it.supplier_name || "").trim()));
        r.set("imported_at", now);
        tx.save(r);
      }
    });
    return e.json(200, { created, updated, suppliers: newSuppliers });
  },
};
