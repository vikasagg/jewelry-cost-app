// Helpers for app_data.pb.js.
module.exports = {
  registerLines: (app, reg) => {
    const existing = app.findRecordsByFilter(
      "sales_register_lines",
      "register = {:id}",
      "",
      0,
      0,
      { id: reg.id },
    );
    for (const r of existing) app.delete(r);
    if (reg.getBool("deleted")) return;
    let lines;
    try {
      lines = JSON.parse(reg.getString("lines") || "[]");
    } catch (_) {
      return;
    }
    if (!Array.isArray(lines)) return;
    const col = app.findCollectionByNameOrId("sales_register_lines");
    for (const l of lines) {
      const r = new Record(col);
      r.set("register", reg.id);
      r.set("register_date", reg.getString("register_date"));
      r.set("no", l.no || 0);
      r.set("customer_type", l.customer_type || "");
      r.set("name", l.name || "");
      r.set("mobile", l.mobile || "");
      r.set("deal", l.deal || "");
      r.set("metal", l.metal || "");
      r.set("item", l.item || "");
      r.set("checked", !!l.checked);
      app.save(r);
    }
  },

  // Body {name, min}: returns {value} = max(stored + 1, min), saved in the
  // settings record with that key.
  counter: (e) => {
    const body = e.requestInfo().body || {};
    const name = String(body.name || "");
    if (!/^[a-z_]{1,40}_counter$/.test(name)) {
      return e.json(400, { message: "Unknown counter" });
    }
    const min = Math.max(1, parseInt(body.min || 1, 10) || 1);
    let value = 0;
    e.app.runInTransaction((tx) => {
      const col = tx.findCollectionByNameOrId("settings");
      let rec;
      try {
        rec = tx.findFirstRecordByFilter("settings", "key = {:k}", { k: name });
      } catch (_) {
        rec = new Record(col);
        rec.set("key", name);
      }
      let stored = 0;
      try {
        stored = parseInt(JSON.parse(rec.getString("data") || "{}").value, 10) || 0;
      } catch (_) {}
      value = Math.max(stored + 1, min);
      rec.set("data", { value: String(value) });
      rec.set("deleted", false);
      tx.save(rec);
    });
    return e.json(200, { value });
  },
};
