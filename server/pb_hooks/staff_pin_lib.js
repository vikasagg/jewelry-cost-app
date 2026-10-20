// Personal PIN helpers (see staff_pins.pb.js).
const MAX_FAILS = 5;
const LOCK_MINUTES = 5;

function hash(salt, pin) {
  return $security.sha256(salt + ":" + pin);
}

function find(app, name) {
  try {
    return app.findFirstRecordByFilter(
      "staff",
      "name = {:n} && active = true",
      { n: String(name || "").trim() },
    );
  } catch (_) {
    return null;
  }
}

function lockedFor(rec) {
  const until = rec.getDateTime("pin_locked_until");
  if (until.isZero()) return 0;
  const ms = until.time().unixMilli() - Date.now();
  return ms > 0 ? Math.ceil(ms / 60000) : 0;
}

// Returns {ok, status, message}; counts failures and locks after MAX_FAILS.
function check(app, rec, pin) {
  if (!rec.getString("pin_hash")) {
    return { ok: false, status: 409, message: "No PIN set yet" };
  }
  const mins = lockedFor(rec);
  if (mins > 0) {
    return {
      ok: false,
      status: 423,
      message: "Too many wrong PINs. Try again in " + mins + " min.",
    };
  }
  if (hash(rec.getString("pin_salt"), String(pin || "")) === rec.getString("pin_hash")) {
    if (rec.getInt("pin_fails") !== 0) {
      rec.set("pin_fails", 0);
      app.save(rec);
    }
    return { ok: true, status: 200 };
  }
  const fails = rec.getInt("pin_fails") + 1;
  if (fails >= MAX_FAILS) {
    rec.set("pin_fails", 0);
    rec.set(
      "pin_locked_until",
      new DateTime().add(LOCK_MINUTES * 60 * 1000 * 1000 * 1000),
    );
  } else {
    rec.set("pin_fails", fails);
  }
  app.save(rec);
  return { ok: false, status: 401, message: "Incorrect PIN" };
}

module.exports = {
  set: (e) => {
    const body = e.requestInfo().body || {};
    const pin = String(body.pin || "");
    if (!/^[0-9]{4,8}$/.test(pin)) {
      return e.json(400, { message: "PIN must be 4–8 digits" });
    }
    const rec = find(e.app, body.name);
    if (!rec) return e.json(404, { message: "Unknown staff member" });
    if (rec.getString("pin_hash")) {
      const r = check(e.app, rec, body.current);
      if (!r.ok) {
        return e.json(r.status, {
          message: r.status === 401 ? "Current PIN is incorrect" : r.message,
        });
      }
    }
    const salt = $security.randomString(24);
    rec.set("pin_salt", salt);
    rec.set("pin_hash", hash(salt, pin));
    rec.set("pin_fails", 0);
    e.app.save(rec);
    return e.json(200, { ok: true });
  },
  check: (e) => {
    const body = e.requestInfo().body || {};
    const rec = find(e.app, body.name);
    if (!rec) return e.json(404, { message: "Unknown staff member" });
    const r = check(e.app, rec, body.pin);
    return e.json(r.ok ? 200 : r.status, r.ok ? { ok: true } : { message: r.message });
  },
  // Which staff have a PIN (names only).
  status: (e) => {
    const recs = e.app.findRecordsByFilter("staff", "active = true", "name", 0, 0);
    return e.json(200, {
      items: recs.map((r) => ({
        name: r.getString("name"),
        has_pin: !!r.getString("pin_hash"),
      })),
    });
  },
};
