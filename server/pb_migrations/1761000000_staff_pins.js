/// <reference path="../pb_data/types.d.ts" />

// Personal PINs. Only a salted hash is stored, in hidden fields the API
// never returns; phones set and check PINs through pb_hooks/staff_pins.pb.js.
// To reset a forgotten PIN: admin panel → staff → clear pin_hash.
migrate(
  (app) => {
    const staff = app.findCollectionByNameOrId("staff");
    staff.fields.add(new TextField({ name: "pin_hash", hidden: true }));
    staff.fields.add(new TextField({ name: "pin_salt", hidden: true }));
    staff.fields.add(new NumberField({ name: "pin_fails", hidden: true }));
    staff.fields.add(new DateField({ name: "pin_locked_until", hidden: true }));
    app.save(staff);
  },
  (app) => {
    const staff = app.findCollectionByNameOrId("staff");
    for (const n of ["pin_hash", "pin_salt", "pin_fails", "pin_locked_until"]) {
      staff.fields.removeByName(n);
    }
    app.save(staff);
  },
);
