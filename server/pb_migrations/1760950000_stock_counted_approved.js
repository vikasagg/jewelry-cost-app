/// <reference path="../pb_data/types.d.ts" />

// Who counted and who approved, as their own columns, plus one row per
// counted item (stock_count_items, filled by pb_hooks/stock_items.pb.js).
migrate(
  (app) => {
    const days = app.findCollectionByNameOrId("stock_days");
    days.fields.getByName("employee").name = "counted_by";
    days.fields.add(new TextField({ name: "approved_by", max: 80 }));
    days.fields.add(new DateField({ name: "approved_at" }));
    days.fields.add(new NumberField({ name: "total_expected" }));
    days.fields.add(new NumberField({ name: "total_difference" }));
    // Per-item lines as sent by the app (also expanded into
    // stock_count_items).
    days.fields.add(new JSONField({ name: "lines", maxSize: 500000 }));
    app.save(days);

    const items = new Collection({
      type: "base",
      name: "stock_count_items",
      // Read-only for phones; rows are written by the server hook.
      listRule: "",
      viewRule: "",
      createRule: null,
      updateRule: null,
      deleteRule: null,
      fields: [
        {
          type: "relation",
          name: "day",
          required: true,
          collectionId: days.id,
          cascadeDelete: true,
          maxSelect: 1,
        },
        { type: "text", name: "date", required: true },
        { type: "text", name: "code", required: true },
        { type: "text", name: "item" },
        { type: "text", name: "group" },
        { type: "number", name: "expected" },
        { type: "number", name: "counted" },
        // False on the very first count (nothing to compare with yet).
        { type: "bool", name: "compared" },
        { type: "number", name: "difference" },
        { type: "text", name: "remark" },
        // How the count was added up on the keypad, e.g. "5+3-1".
        { type: "text", name: "working" },
        { type: "text", name: "counted_by" },
        { type: "text", name: "approved_by" },
        { type: "text", name: "status" },
        { type: "autodate", name: "created", onCreate: true, onUpdate: false },
        { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
      ],
      indexes: [
        "CREATE UNIQUE INDEX idx_stock_items_day_code ON stock_count_items (day, code)",
        "CREATE INDEX idx_stock_items_date ON stock_count_items (date)",
      ],
    });
    app.save(items);
  },
  (app) => {
    try {
      app.delete(app.findCollectionByNameOrId("stock_count_items"));
    } catch (_) {}
    const days = app.findCollectionByNameOrId("stock_days");
    for (const n of [
      "approved_by",
      "approved_at",
      "total_expected",
      "total_difference",
      "lines",
    ]) {
      days.fields.removeByName(n);
    }
    days.fields.getByName("counted_by").name = "employee";
    app.save(days);
  },
);
