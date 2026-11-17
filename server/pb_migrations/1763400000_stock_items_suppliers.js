/// <reference path="../pb_data/types.d.ts" />

// The shop's stock, item by item, as in the stock export (Excel), and its
// suppliers. Tag No is unique. Phones read both; items are added/updated
// only by the import (pb_hooks/stock_import.pb.js) or the admin panel.
migrate(
  (app) => {
    const stamps = [
      { type: "autodate", name: "created", onCreate: true, onUpdate: false },
      { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
    ];
    const readOnly = {
      listRule: "",
      viewRule: "",
      createRule: null,
      updateRule: null,
      deleteRule: null,
    };

    const suppliers = new Collection({
      type: "base",
      name: "suppliers",
      ...readOnly,
      fields: [
        { type: "text", name: "name", required: true, max: 120 },
        // New suppliers get Delhi / 9717000000 until edited.
        { type: "text", name: "address", max: 300 },
        { type: "text", name: "mobile", max: 15 },
        { type: "bool", name: "active" },
        ...stamps,
      ],
      indexes: ["CREATE UNIQUE INDEX idx_suppliers_name ON suppliers (name)"],
    });
    app.save(suppliers);

    const text = (name) => ({ type: "text", name, max: 200 });
    const num = (name) => ({ type: "number", name });
    const items = new Collection({
      type: "base",
      name: "stock_items",
      ...readOnly,
      fields: [
        { type: "text", name: "tag_no", required: true, max: 40 },
        text("item_name"),
        { type: "date", name: "entry_date" },
        num("pcs"),
        num("gross_wt"),
        num("net_wt"),
        num("dia_wt"),
        num("stone_wt"),
        num("gold_wt"),
        text("design"),
        { type: "bool", name: "hallmark" },
        text("certificate"),
        num("labour_per_gm"),
        num("labour_rs"),
        text("remarks"),
        text("colour"),
        text("clarity"),
        text("size"),
        num("mrp"),
        num("costing"),
        {
          type: "relation",
          name: "supplier",
          collectionId: suppliers.id,
          maxSelect: 1,
          cascadeDelete: false,
        },
        // As written in the export (kept even without a supplier record).
        text("supplier_name"),
        text("dia_item"),
        text("dia_quality"),
        text("dia_size"),
        num("dia_pcs"),
        num("dia_detail_wt"),
        num("dia_rate"),
        num("dia_value"),
        text("stn_item"),
        text("stn_quality"),
        text("stn_size"),
        num("stn_pcs"),
        num("stn_detail_wt"),
        num("stn_rate"),
        num("stn_value"),
        text("gold_std"),
        // in_stock, or sold/removed later.
        text("status"),
        { type: "date", name: "imported_at" },
        ...stamps,
      ],
      indexes: [
        "CREATE UNIQUE INDEX idx_stock_items_tag_no ON stock_items (tag_no)",
        "CREATE INDEX idx_stock_items_item_name ON stock_items (item_name)",
        "CREATE INDEX idx_stock_items_supplier ON stock_items (supplier)",
      ],
    });
    app.save(items);
  },
  (app) => {
    for (const name of ["stock_items", "suppliers"]) {
      try {
        app.delete(app.findCollectionByNameOrId(name));
      } catch (_) {}
    }
  },
);
