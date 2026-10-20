// Expands a stock_days record's "lines" into stock_count_items rows.
module.exports = {
  checkApprover: (day) => {
    const counted = day.getString("counted_by").trim().toLowerCase();
    const approved = day.getString("approved_by").trim().toLowerCase();
    if (counted && counted === approved) {
      throw new BadRequestError(
        "The person who counted cannot approve the same count.",
      );
    }
  },
  sync: (app, day) => {
    let lines;
    try {
      lines = JSON.parse(day.getString("lines") || "[]");
    } catch (_) {
      return;
    }
    if (!Array.isArray(lines)) return;
    const col = app.findCollectionByNameOrId("stock_count_items");
    const existing = app.findRecordsByFilter(
      "stock_count_items",
      "day = {:id}",
      "",
      0,
      0,
      { id: day.id },
    );
    const byCode = {};
    for (const r of existing) byCode[r.getString("code")] = r;
    const seen = {};
    for (const l of lines) {
      if (!l || !l.code) continue;
      const r = byCode[l.code] || new Record(col);
      r.set("day", day.id);
      r.set("date", day.getString("date"));
      r.set("code", l.code);
      r.set("item", l.item || "");
      r.set("group", l.group || "");
      r.set("expected", l.expected || 0);
      r.set("counted", l.counted || 0);
      r.set("compared", l.difference !== null && l.difference !== undefined);
      r.set("difference", l.difference || 0);
      r.set("remark", l.remark || "");
      r.set("working", l.working || "");
      r.set("counted_by", day.getString("counted_by"));
      r.set("approved_by", day.getString("approved_by"));
      r.set("status", day.getString("status"));
      app.save(r);
      seen[l.code] = true;
    }
    for (const r of existing) {
      if (!seen[r.getString("code")]) app.delete(r);
    }
  },
};
