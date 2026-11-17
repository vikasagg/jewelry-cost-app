/// <reference path="../pb_data/types.d.ts" />

// Everything the app records (besides stock counts): estimates with their
// tag photos, bills, Today's Sales registers (and one row per line), gold
// & silver prices and shared settings (gold rate, counters). Every record
// is found by `key`; `data` holds it as the app stores it, and the other
// columns make it readable in the admin panel.
migrate(
  (app) => {
    const common = () => [
      { type: "text", name: "key", required: true, max: 200 },
      { type: "json", name: "data", maxSize: 5000000 },
      { type: "bool", name: "deleted" },
      { type: "date", name: "client_updated" },
    ];
    const stamps = [
      { type: "autodate", name: "created", onCreate: true, onUpdate: false },
      { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
    ];
    // Phones on the shop Wi-Fi read and save; deleting only in the admin
    // panel (phones mark records as deleted instead).
    const open = {
      listRule: "",
      viewRule: "",
      createRule: "",
      updateRule: "",
      deleteRule: null,
    };
    const make = (name, fields, extraIndexes = []) => {
      const c = new Collection({
        type: "base",
        name,
        ...open,
        fields: [...common(), ...fields, ...stamps],
        indexes: [
          `CREATE UNIQUE INDEX idx_${name}_key ON ${name} (key)`,
          `CREATE INDEX idx_${name}_updated ON ${name} (updated)`,
          ...extraIndexes,
        ],
      });
      app.save(c);
      return c;
    };

    make("estimates", [
      { type: "text", name: "tag_number" },
      { type: "text", name: "item" },
      { type: "text", name: "purity" },
      { type: "number", name: "gross_weight" },
      { type: "number", name: "net_weight" },
      { type: "number", name: "total" },
      { type: "text", name: "source" },
      { type: "date", name: "estimated_at" },
      {
        type: "file",
        name: "photo",
        maxSelect: 1,
        maxSize: 5242880,
        mimeTypes: ["image/jpeg", "image/png"],
      },
    ]);
    make("bills", [
      { type: "text", name: "bill_no" },
      { type: "text", name: "customer_name" },
      { type: "text", name: "phone" },
      { type: "text", name: "address" },
      { type: "text", name: "payment" },
      { type: "number", name: "items" },
      { type: "number", name: "total" },
      { type: "date", name: "billed_at" },
    ]);
    const registers = make("sales_registers", [
      { type: "text", name: "register_date" },
      { type: "number", name: "line_count" },
      { type: "json", name: "lines", maxSize: 2000000 },
    ]);
    make("metal_prices", [
      { type: "text", name: "price_date" },
      { type: "number", name: "gold24_per_10g" },
      { type: "number", name: "silver_per_kg" },
    ]);
    make("settings", []);

    // One row per register line, kept up to date by pb_hooks (read-only).
    app.save(
      new Collection({
        type: "base",
        name: "sales_register_lines",
        listRule: "",
        viewRule: "",
        createRule: null,
        updateRule: null,
        deleteRule: null,
        fields: [
          {
            type: "relation",
            name: "register",
            required: true,
            collectionId: registers.id,
            cascadeDelete: true,
            maxSelect: 1,
          },
          { type: "text", name: "register_date" },
          { type: "number", name: "no" },
          { type: "text", name: "customer_type" },
          { type: "text", name: "name" },
          { type: "text", name: "mobile" },
          { type: "text", name: "deal" },
          { type: "text", name: "metal" },
          { type: "text", name: "item" },
          { type: "bool", name: "checked" },
          ...stamps,
        ],
        indexes: [
          "CREATE INDEX idx_register_lines_date ON sales_register_lines (register_date)",
        ],
      }),
    );
  },
  (app) => {
    for (const name of [
      "sales_register_lines",
      "estimates",
      "bills",
      "sales_registers",
      "metal_prices",
      "settings",
    ]) {
      try {
        app.delete(app.findCollectionByNameOrId(name));
      } catch (_) {}
    }
  },
);
