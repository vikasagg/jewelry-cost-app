// Sign-in, settings (configuration, users, purities, categories, USB backup, audit) and the platform console.
import { state, api, can, esc, fmt, table, bindRows, toast, fail, badge, ask, saveSession, loadMasters, fileUrl, ICONS } from './core.js';

// ---------- sign in ----------

export async function login(el) {
  el.innerHTML = `<div class="login"><div class="card">
    <div class="row" style="margin-bottom:.75rem"><img src="icon.svg" width="44" alt=""><div><h1 style="margin:0">Swarn-OS</h1>
    <div class="muted small">Inventory · billing · purchase · repairs · tally · voice</div></div></div>
    <form id="f"><div class="field"><label>Shop code</label><input name="shop" required autocomplete="organization" value="${esc(localStorage.getItem('last-shop') || '')}"></div>
    <div class="field"><label>Username</label><input name="username" required autocomplete="username" autocapitalize="none"></div>
    <div class="field"><label>Password</label><input name="password" type="password" required autocomplete="current-password"></div>
    <button class="primary big" style="width:100%;justify-content:center">Sign in</button></form>
    <div class="demo"><b>Demo shop</b> — shop code <code>demo</code>, users <code>owner</code>, <code>manager</code>, <code>sales</code>, <code>accounts</code>, <code>stock</code>, password <code>demo123</code>.</div>
    <p class="small" style="margin-top:1rem"><a href="#/platform">Platform operator sign-in →</a></p></div></div>`;
  el.querySelector('#f').onsubmit = async e => {
    e.preventDefault();
    const f = e.target;
    try {
      const s = await api('/auth/login', { method: 'POST', body: { shop: f.shop.value.trim(), username: f.username.value.trim(), password: f.password.value } });
      saveSession(s);
      try { localStorage.setItem('last-shop', f.shop.value.trim()); } catch { /* ignore */ }
      state.masters = null;
      location.hash = '#/';
    } catch (err) { fail(err); }
  };
}

// ---------- settings ----------

const CONFIG_GROUPS = [
  ['Shop details (printed on bills)', k => k.startsWith('shop.')],
  ['Metal rate', k => k.startsWith('rate.')],
  ['Billing, discounts and exchange', k => /^(bill|discount|exchange|oldmetal|invoice|purchase|repair|tag)\./.test(k)],
  ['Cash, KYC and GST limits (blank = no limit)', k => /^(cash|kyc)\./.test(k)],
  ['Offline, tally, backup and voice', k => /^(offline|tally|backup|ai)\./.test(k)],
];

export async function settings(el, tab) {
  tab = tab || sessionStorage.getItem('set-tab') || 'Backup to USB';
  const tabs = ['Backup to USB', 'Business rules', 'Purities & categories', 'Users', 'Audit log'].filter(t =>
    t === 'Users' ? can('USERS') : t === 'Audit log' ? can('CONFIG') : t === 'Backup to USB' ? can('BACKUP') : true);
  if (!tabs.includes(tab)) tab = tabs[0];
  el.innerHTML = `<div class="pagehead"><div><h1>Settings</h1><p>Every business rule is a setting — nothing is hard-coded.</p></div></div>
    <div class="tabs">${tabs.map(t => `<button class="${t === tab ? 'on' : ''}">${t}</button>`).join('')}</div><div id="tab"></div>`;
  el.querySelectorAll('.tabs button').forEach(b => b.onclick = () => { sessionStorage.setItem('set-tab', b.textContent); settings(el, b.textContent); });
  const box = el.querySelector('#tab');
  if (tab === 'Business rules') return rules(box);
  if (tab === 'Purities & categories') return masters(box);
  if (tab === 'Users') return users(box);
  if (tab === 'Audit log') {
    const rows = await api('/audit');
    box.innerHTML = table([{ k: 'at', l: 'When', t: 'dt' }, { k: 'username', l: 'User' }, { k: 'action', l: 'Action', t: 'badge' },
      { k: 'entity', l: 'Record' }, { k: 'entity_id', l: 'Id' }, { k: 'detail', l: 'Detail' }], rows);
    return;
  }
  return backup(box);
}

async function rules(box) {
  const cfg = await api('/config');
  const editable = can('CONFIG');
  box.innerHTML = `<form id="f">${CONFIG_GROUPS.map(([title, test]) => `<div class="card"><h2>${esc(title)}</h2><div class="fields" style="grid-template-columns:repeat(auto-fill,minmax(260px,1fr))">
    ${cfg.filter(c => test(c.config_key)).map(c => `<div class="field"><label>${esc(c.config_key)}</label>
      <input name="${esc(c.config_key)}" value="${esc(c.config_value ?? '')}" ${editable ? '' : 'disabled'}>
      <div class="muted small">${esc(c.description || '')}${c.updated_by ? ` · changed by ${esc(c.updated_by)} ${fmt.dt(c.updated_at)}` : ''}</div></div>`).join('')}
    </div></div>`).join('')}${editable ? '<button class="primary">Save settings</button>' : '<p class="muted">Only the owner can change settings.</p>'}</form>`;
  box.querySelector('#f').onsubmit = async e => {
    e.preventDefault();
    const changed = {};
    for (const inp of e.target.elements) {
      if (!inp.name) continue;
      const orig = cfg.find(c => c.config_key === inp.name)?.config_value ?? '';
      if (inp.value !== orig) changed[inp.name] = inp.value;
    }
    if (!Object.keys(changed).length) return toast('Nothing changed.');
    try { await api('/config', { method: 'PUT', body: changed }); toast(`${Object.keys(changed).length} setting(s) saved and logged.`, 'ok'); rules(box); } catch (err) { fail(err); }
  };
}

async function masters(box) {
  const m = await loadMasters(true);
  const editable = can('CONFIG');
  box.innerHTML = `<div class="card"><h2>Purity factors</h2><p class="muted small">Selling rate = base rate × factor. Gold factors are the owner's pricing rule
    (22K = 92%, 20K = 84%, 18K = 76%, 14K = 60%, 9K = 40% of 24K). Fineness is the true metal content used for fine weight.</p><div id="pur"></div></div>
    <div class="card"><div class="row"><h2>Categories</h2><span class="spacer"></span>${editable ? '<button id="newcat">' + ICONS.plus + ' New category</button>' : ''}</div><div id="cat"></div></div>
    <div class="card"><h2>Locations</h2>${table([{ k: 'code', l: 'Code' }, { k: 'name', l: 'Name' }, { k: 'kind', l: 'Kind', t: 'badge' }], m.locations)}</div>`;
  box.querySelector('#pur').innerHTML = table([{ k: 'metal', l: 'Metal' }, { k: 'code', l: 'Purity' },
    { k: 'price_factor', l: 'Price factor', f: r => `${(+r.price_factor * 100).toFixed(3)}%` }, { k: 'fineness', l: 'Fineness', f: r => (+r.fineness).toFixed(3) }],
  m.purities, { click: editable });
  bindRows(box.querySelector('#pur'), m.purities, async r => {
    const v = await ask(`Price factor for ${r.metal} ${r.code}`, [{ name: 'price_factor', label: 'Factor (0.920000 = 92%)', type: 'number', step: '0.000001', value: r.price_factor }],
      { note: 'Takes effect from the next approved rate set. Bills already made keep their rate.' });
    if (!v) return;
    try { await api('/purities/' + r.id, { method: 'PUT', body: v }); toast('Saved.', 'ok'); masters(box); } catch (e) { fail(e); }
  });
  const catFields = c => [
    { name: 'code', label: 'Code', value: c.code, required: true }, { name: 'name', label: 'Name', value: c.name, required: true },
    { name: 'family', label: 'Family', type: 'select', options: ['GOLD', 'DIAMOND', 'PLATINUM', 'SILVER', 'SILVER_ORNAMENT', 'GIFTING'], value: c.family },
    { name: 'tracking', label: 'Tracking', type: 'select', options: [['PIECE', 'One tag per piece'], ['QUANTITY', 'Quantity (SKU)']], value: c.tracking },
    { name: 'making_type', label: 'Making charge', type: 'select', options: [['PER_GRAM', '₹ per gram'], ['PERCENT', '% of metal value'], ['FIXED', 'Fixed ₹']], value: c.making_type },
    { name: 'making_value', label: 'Making value', type: 'number', value: c.making_value }, { name: 'wastage_pct', label: 'Wastage %', type: 'number', value: c.wastage_pct },
    { name: 'gst_pct', label: 'GST %', type: 'number', value: c.gst_pct ?? 3 }];
  box.querySelector('#cat').innerHTML = table([{ k: 'code', l: 'Code' }, { k: 'name', l: 'Name' }, { k: 'family', l: 'Family', t: 'badge' },
    { k: 'making', l: 'Making', f: r => r.making_type === 'PERCENT' ? `${fmt.num(r.making_value)}%` : r.making_type === 'FIXED' ? fmt.money(r.making_value) : `${fmt.money(r.making_value)}/g` },
    { k: 'wastage_pct', l: 'Wastage %', t: 'num' }, { k: 'gst_pct', l: 'GST %', t: 'num' }, { k: 'tracking', l: 'Tracking', t: 'badge' }], m.categories, { click: editable });
  bindRows(box.querySelector('#cat'), m.categories, async c => {
    const v = await ask('Edit ' + c.name, catFields(c));
    if (!v) return;
    try { await api('/categories', { method: 'POST', body: { ...v, id: c.id } }); toast('Saved.', 'ok'); masters(box); } catch (e) { fail(e); }
  });
  box.querySelector('#newcat')?.addEventListener('click', async () => {
    const v = await ask('New category', catFields({ family: 'GOLD', tracking: 'PIECE', making_type: 'PERCENT' }));
    if (!v) return;
    try { await api('/categories', { method: 'POST', body: v }); toast('Category added.', 'ok'); masters(box); } catch (e) { fail(e); }
  });
}

async function users(box) {
  const rows = await api('/users');
  const roleNote = 'OWNER: everything. MANAGER: approvals, billing, tally close. SALES: billing, tally scan, repairs. ACCOUNTANT: purchases, ledgers, Seen/Unseen reports. STOCK: tagging, purchases, tally scan.';
  box.innerHTML = `<div class="card"><div class="row"><h2>Users</h2><span class="spacer"></span><button class="primary" id="new">${ICONS.plus} New user</button></div>
    <p class="muted small">${esc(roleNote)}</p><div id="t"></div></div>`;
  box.querySelector('#t').innerHTML = table([{ k: 'username', l: 'Username' }, { k: 'full_name', l: 'Name' }, { k: 'role', l: 'Role', t: 'badge' },
    { k: 'active', l: 'Active', f: r => r.active ? badge('ACTIVE') : badge('SUSPENDED') }, { k: 'created_at', l: 'Created', t: 'dt' }], rows, { click: true });
  const roles = ['OWNER', 'MANAGER', 'SALES', 'ACCOUNTANT', 'STOCK'];
  bindRows(box.querySelector('#t'), rows, async u => {
    const v = await ask('Edit ' + u.username, [{ name: 'fullName', label: 'Name', value: u.full_name }, { name: 'role', label: 'Role', type: 'select', options: roles, value: u.role },
      { name: 'password', label: 'New password (leave blank to keep)', type: 'password' }, { name: 'active', label: 'Active', type: 'checkbox', value: u.active }]);
    if (!v) return;
    try { await api('/users/' + u.id, { method: 'PUT', body: v }); toast('Saved.', 'ok'); users(box); } catch (e) { fail(e); }
  });
  box.querySelector('#new').onclick = async () => {
    const v = await ask('New user', [{ name: 'username', label: 'Username', required: true }, { name: 'fullName', label: 'Full name' },
      { name: 'role', label: 'Role', type: 'select', options: roles, value: 'SALES' }, { name: 'password', label: 'Password (min 6)', type: 'password', required: true }]);
    if (!v) return;
    try { await api('/users', { method: 'POST', body: v }); toast('User created.', 'ok'); users(box); } catch (e) { fail(e); }
  };
}

async function backup(box) {
  const b = await api('/backup');
  box.innerHTML = `<div class="split"><div class="card"><h2>${ICONS.usb} Full backup to USB</h2>
      <p>Takes an encrypted copy of the whole shop database, checks it by reading it back, and logs it. Plug in the USB drive first.</p>
      <form id="bf"><div class="field"><label>Save to folder</label><input name="target_dir" value="${esc(b.target_dir)}">
        <div class="muted small">Windows example: <code>E:\\SwarnOSBackup</code> · Linux: <code>/media/usb/SwarnOSBackup</code>. Set the default in Business rules → backup.targetDir.</div></div>
      <div class="field"><label>Backup password (needed to restore — keep it safe)</label><input name="password" type="password" minlength="6" required></div>
      <button class="primary big">Back up now</button></form><div id="res" style="margin-top:1rem"></div></div>
    <div class="card"><h2>Check a backup file</h2><p class="muted small">Opens a backup and lists what is inside, without changing anything.</p>
      <form id="vf"><div class="field"><label>Backup file (.swarn)</label><input type="file" name="file" accept=".swarn" required></div>
      <div class="field"><label>Password</label><input type="password" name="password" required></div><button>Check file</button></form><div id="vres"></div>
      <p class="small muted" style="margin-top:1rem">To restore, the platform operator loads the file as a new shop (Platform console → Restore), checks it, then switches over — live data is never overwritten.</p></div></div>
    <div class="card"><h2>Backup log</h2>${table([{ k: 'at', l: 'When', t: 'dt' }, { k: 'username', l: 'By' }, { k: 'file_name', l: 'File',
      f: r => `<a href="${fileUrl('/backup/download?file=' + encodeURIComponent(r.file_name))}">${esc(r.file_name)}</a>` }, { k: 'target', l: 'Saved to' },
      { k: 'row_count', l: 'Rows', t: 'int' }, { k: 'size_bytes', l: 'Bytes', t: 'int' }, { k: 'verified', l: 'Restore test', f: r => r.verified ? badge('ACCEPTED') : badge('REJECTED') },
      { k: 'sha256', l: 'SHA-256', f: r => `<code class="small">${esc(r.sha256.slice(0, 16))}…</code>` }], b.log, { empty: 'No backup yet.' })}</div>`;
  box.querySelector('#bf').onsubmit = async e => {
    e.preventDefault();
    const btn = e.target.querySelector('button');
    btn.disabled = true;
    try {
      const r = await api('/backup', { method: 'POST', body: { password: e.target.password.value, target_dir: e.target.target_dir.value } });
      box.querySelector('#res').innerHTML = `<div class="alert block ${r.verified ? 'ok' : 'bad'}">${r.verified ? 'Backup verified.' : 'Backup could not be verified!'}
        ${esc(r.rows)} rows · ${esc(r.size_bytes)} bytes<br>Saved to <code>${esc(r.path)}</code><br>SHA-256 <code class="small">${esc(r.sha256)}</code>
        <br><a href="${fileUrl('/backup/download?file=' + encodeURIComponent(r.file))}">Download a copy through the browser</a></div>`;
      toast('Backup done.', 'ok');
      setTimeout(() => backup(box), 2500);
    } catch (err) { fail(err); btn.disabled = false; }
  };
  box.querySelector('#vf').onsubmit = async e => {
    e.preventDefault();
    try {
      const r = await api('/backup/verify', { method: 'POST', form: new FormData(e.target) });
      box.querySelector('#vres').innerHTML = `<div class="alert block ok" style="margin-top:.75rem">Shop <b>${esc(r.shop)}</b> · taken ${esc(fmt.dt(r.created_at))} by ${esc(r.created_by)} · ${esc(r.rows)} rows</div>`
        + table([{ k: 't', l: 'Table' }, { k: 'n', l: 'Rows', t: 'int' }], Object.entries(r.tables).map(([t, n]) => ({ t, n })), { resp: false });
    } catch (err) { fail(err); }
  };
}

// ---------- platform operator ----------

export async function platform(el) {
  const token = sessionStorage.getItem('platform-token');
  if (!token) {
    el.innerHTML = `<div class="login"><div class="card"><h1>Platform console</h1><p class="muted small">Onboard shops, each with its own database.</p>
      <form id="f"><div class="field"><label>Username</label><input name="username" required></div><div class="field"><label>Password</label>
      <input name="password" type="password" required></div><button class="primary big" style="width:100%;justify-content:center">Sign in</button></form>
      <p class="small"><a href="#/login">← Shop sign-in</a></p></div></div>`;
    el.querySelector('#f').onsubmit = async e => {
      e.preventDefault();
      try {
        const r = await api('/platform/login', { method: 'POST', body: { username: e.target.username.value, password: e.target.password.value } });
        sessionStorage.setItem('platform-token', r.token);
        platform(el);
      } catch (err) { fail(err); }
    };
    return;
  }
  const papi = async (path, opts = {}) => {
    const res = await fetch('/api/platform' + path, { method: opts.method || 'GET', headers: { Authorization: 'Bearer ' + token,
      ...(opts.body ? { 'Content-Type': 'application/json' } : {}) }, body: opts.form || (opts.body ? JSON.stringify(opts.body) : undefined) });
    const data = await res.json().catch(() => null);
    if (res.status === 401) { sessionStorage.removeItem('platform-token'); platform(el); throw new Error('Signed out.'); }
    if (!res.ok) throw new Error(data?.error || 'Error ' + res.status);
    return data;
  };
  const tenants = await papi('/tenants');
  el.innerHTML = `<div class="content" style="margin:0 auto"><div class="pagehead"><div><h1>Platform console</h1><p>Every shop has its own database: a local file (in-shop server) or a PostgreSQL database (cloud).</p></div>
    <div class="row"><button id="mig">Upgrade all shop databases</button><button id="out">Sign out</button></div></div>
    <div class="split"><div class="card"><h2>Shops</h2><div id="t"></div></div>
    <div><form class="card" id="nf"><h2>Onboard a new shop</h2>
      <div class="field"><label>Shop code (used to sign in)</label><input name="code" required pattern="[a-z][a-z0-9]{1,19}" placeholder="e.g. tanishq01"></div>
      <div class="field"><label>Shop name</label><input name="name" required></div>
      <div class="field"><label>Database</label><select name="storageMode"><option value="LOCAL">Local — file database on the shop server (works with no internet)</option>
        <option value="CLOUD">Cloud — separate PostgreSQL database</option></select></div>
      <div class="field"><label>Owner username</label><input name="ownerUsername" value="owner" required></div>
      <div class="field"><label>Owner name</label><input name="ownerName"></div>
      <div class="field"><label>Owner password</label><input name="ownerPassword" type="password" minlength="6" required></div>
      <button class="primary">Create shop and database</button></form>
      <form class="card" id="rf"><h2>Restore a backup as a new shop</h2>
        <div class="field"><label>Backup file (.swarn)</label><input type="file" name="file" required accept=".swarn"></div>
        <div class="field"><label>Backup password</label><input type="password" name="password" required></div>
        <div class="field"><label>New shop code</label><input name="code" required></div>
        <div class="field"><label>Database</label><select name="storageMode"><option>LOCAL</option><option>CLOUD</option></select></div>
        <button>Restore</button></form></div></div></div>`;
  el.querySelector('#t').innerHTML = table([{ k: 'code', l: 'Code' }, { k: 'name', l: 'Name' }, { k: 'storageMode', l: 'Mode', t: 'badge' },
    { k: 'database', l: 'Database', f: r => `<code class="small">${esc(r.database)}</code>` }, { k: 'schemaVersion', l: 'Schema' },
    { k: 'status', l: 'Status', f: r => `${badge(r.status)} <button class="small" data-code="${esc(r.code)}" data-s="${r.status === 'ACTIVE' ? 'SUSPENDED' : 'ACTIVE'}">${r.status === 'ACTIVE' ? 'Suspend' : 'Activate'}</button>` }],
  tenants, { resp: false });
  el.querySelectorAll('[data-code]').forEach(b => b.onclick = async () => {
    try { await papi(`/tenants/${b.dataset.code}/status/${b.dataset.s}`, { method: 'POST' }); platform(el); } catch (e) { fail(e); }
  });
  el.querySelector('#nf').onsubmit = async e => {
    e.preventDefault();
    const body = Object.fromEntries(new FormData(e.target));
    try { const t = await papi('/tenants', { method: 'POST', body }); toast(`Shop ${t.code} created with its own ${t.storageMode.toLowerCase()} database.`, 'ok'); platform(el); } catch (err) { fail(err); }
  };
  el.querySelector('#rf').onsubmit = async e => {
    e.preventDefault();
    try { const r = await papi('/restore', { method: 'POST', form: new FormData(e.target) }); toast(`Restored ${r.rows} rows into shop ${r.code}.`, 'ok'); platform(el); } catch (err) { fail(err); }
  };
  el.querySelector('#mig').onclick = async () => {
    try { const r = await papi('/tenants/migrate', { method: 'POST' }); toast(r.failed.length ? 'Failed: ' + r.failed.join('; ') : 'All shops are up to date.', r.failed.length ? 'bad' : 'ok'); platform(el); } catch (e) { fail(e); }
  };
  el.querySelector('#out').onclick = () => { sessionStorage.removeItem('platform-token'); location.hash = '#/login'; };
}
