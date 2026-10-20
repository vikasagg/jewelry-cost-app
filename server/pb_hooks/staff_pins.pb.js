/// <reference path="../pb_data/types.d.ts" />

// Personal PINs for counting and approving stock (see staff_pin_lib.js).
routerAdd("POST", "/api/damiyaas/pin/set", (e) => {
  return require(`${__hooks}/staff_pin_lib.js`).set(e);
});

routerAdd("POST", "/api/damiyaas/pin/check", (e) => {
  return require(`${__hooks}/staff_pin_lib.js`).check(e);
});

routerAdd("GET", "/api/damiyaas/pin/status", (e) => {
  return require(`${__hooks}/staff_pin_lib.js`).status(e);
});
