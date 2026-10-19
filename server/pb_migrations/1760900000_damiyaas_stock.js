/// <reference path="../pb_data/types.d.ts" />

// Damiyaas Jewelers — daily stock counts and staff.
// PocketBase applies this automatically when it starts (pb_migrations
// folder next to pocketbase.exe). Safe to keep: it runs only once.
migrate(
  (app) => {
    const staff = new Collection({
      type: "base",
      name: "staff",
      // The app reads the staff list; only the admin panel can change it.
      listRule: "",
      viewRule: "",
      createRule: null,
      updateRule: null,
      deleteRule: null,
      fields: [
        { type: "text", name: "name", required: true, max: 80 },
        { type: "text", name: "phone", required: true, pattern: "^[0-9]{10}$" },
        { type: "bool", name: "active" },
        { type: "autodate", name: "created", onCreate: true, onUpdate: false },
        { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
      ],
      indexes: ["CREATE UNIQUE INDEX idx_staff_phone ON staff (phone)"],
    });
    app.save(staff);

    const days = new Collection({
      type: "base",
      name: "stock_days",
      // Phones on the shop Wi-Fi read and save counts; deleting a day is
      // only possible from the admin panel.
      listRule: "",
      viewRule: "",
      createRule: "",
      updateRule: "",
      deleteRule: null,
      fields: [
        {
          type: "text",
          name: "date",
          required: true,
          pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
        },
        {
          type: "select",
          name: "status",
          maxSelect: 1,
          values: ["draft", "submitted", "verified"],
        },
        { type: "text", name: "employee", max: 80 },
        { type: "number", name: "total_count" },
        // The full day as the app stores it (counts, opening, remarks,
        // adjustments, approval and audit trail).
        { type: "json", name: "data", maxSize: 2000000 },
        { type: "autodate", name: "created", onCreate: true, onUpdate: false },
        { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
      ],
      indexes: ["CREATE UNIQUE INDEX idx_stock_days_date ON stock_days (date)"],
    });
    app.save(days);

    for (const [name, phone] of [
      ["Anil", "7678405443"],
      ["Bhavna", "9205348300"],
      ["Tanish", "9667725005"],
    ]) {
      const r = new Record(staff);
      r.set("name", name);
      r.set("phone", phone);
      r.set("active", true);
      app.save(r);
    }
  },
  (app) => {
    for (const name of ["stock_days", "staff"]) {
      try {
        app.delete(app.findCollectionByNameOrId(name));
      } catch (_) {}
    }
  },
);
