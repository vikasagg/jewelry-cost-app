// Inventory, item master and QR labels, daily stock tally, repairs.
import { state, api, can, esc, fmt, table, bindRows, toast, fail, badge, scanner, ask, fieldHtml, formValues, loadMasters,
  qrSvg, ICONS } from './core.js';
import { itemCards } from './views.js';
import { partyPicker } from './trade.js';

const FAMILIES = [['', 'All types'], ['GOLD', 'Gold'], ['DIAMOND', 'Diamond'], ['PLATINUM', 'Platinum'], ['SILVER', 'Silver'],
  ['SILVER_ORNAMENT', 'Silver ornaments'], ['GIFTING', 'Gifting']];

// ---------- inventory ----------

export async function inventory(el) {
  const m = await loadMasters();
  const saved = new URLSearchParams(sessionStorage.getItem('inv-filters') || 'status=IN_STOCK');
  el.innerHTML = `<div class="pagehead"><div><h1>Inventory</h1><p id="sum"></p></div>
    <div class="row">${can('ITEM_EDIT') ? '<a class="btn primary" href="#/item/new">Add opening stock</a>' : ''}
    <button id="labels">${ICONS.print} Labels for list</button><button id="check">Ledger check</button></div></div>
    <form class="card" id="flt"><div class="fields">
      ${fieldHtml({ name: 'q', label: 'Search', placeholder: 'Tag, name, design, HUID', value: saved.get('q') })}
      ${fieldHtml({ name: 'family', label: 'Type', type: 'select', options: FAMILIES, value: saved.get('family') || '' })}
      ${fieldHtml({ name: 'category_id', label: 'Category', type: 'select', options: [['', 'All']].concat(m.categories.map(c => [c.id, c.name])), value: saved.get('category_id') || '' })}
      ${fieldHtml({ name: 'purity', label: 'Purity', type: 'select', options: [['', 'All']].concat([...new Set(m.purities.map(p => p.code))].map(c => [c, c])), value: saved.get('purity') || '' })}
      ${fieldHtml({ name: 'location_id', label: 'Location', type: 'select', options: [['', 'All']].concat(m.locations.map(l => [l.id, l.name])), value: saved.get('location_id') || '' })}
      ${fieldHtml({ name: 'status', label: 'Status', type: 'select', options: [['IN_STOCK', 'In stock'], ['SOLD', 'Sold'], ['LOST', 'Lost'], ['RETURNED', 'Returned to vendor'], ['ALL', 'All']], value: saved.get('status') || 'IN_STOCK' })}
      ${fieldHtml({ name: 'min_wt', label: 'Net g from', type: 'number', value: saved.get('min_wt') })}
      ${fieldHtml({ name: 'max_wt', label: 'Net g to', type: 'number', value: saved.get('max_wt') })}
      ${fieldHtml({ name: 'min_price', label: 'Price from ₹', type: 'number', value: saved.get('min_price') })}
      ${fieldHtml({ name: 'max_price', label: 'Price to ₹', type: 'number', value: saved.get('max_price') })}
      ${can('VIEW_PURCHASE_CLASS') ? fieldHtml({ name: 'purchase_class', label: 'Purchase class', type: 'select', options: [['', 'All'], ['SEEN', 'Seen'], ['UNSEEN', 'Unseen']], value: saved.get('purchase_class') || '' }) : ''}
    </div><div class="row"><button class="primary">Apply</button><button type="button" id="clear">Clear</button>
      <span class="spacer"></span><div class="seg"><button type="button" data-v="table" class="on">Table</button><button type="button" data-v="cards">Cards</button></div></div></form>
    <div id="list" style="margin-top:1rem"></div>`;
  let rows = [];
  let view = sessionStorage.getItem('inv-view') || 'table';
  const draw = () => {
    el.querySelectorAll('[data-v]').forEach(b => b.classList.toggle('on', b.dataset.v === view));
    const box = el.querySelector('#list');
    if (view === 'cards') {
      box.innerHTML = itemCards(rows);
      box.querySelectorAll('[data-item]').forEach(c => c.onclick = () => location.hash = '#/item/' + c.dataset.item);
      return;
    }
    const cols = [{ k: 'tag_code', l: 'Tag' }, { k: 'name', l: 'Item' }, { k: 'category_name', l: 'Category' }, { k: 'purity_code', l: 'Purity' },
      { k: 'gross_wt', l: 'Gross g', t: 'wt' }, { k: 'net_wt', l: 'Net g', t: 'wt' }, { k: 'stone_carat', l: 'Stone ct', t: 'num' },
      { k: 'location_name', l: 'Location' }, { k: 'price', l: 'Price today', t: 'money' }, { k: 'status', l: 'Status', t: 'badge' }];
    if (can('VIEW_PURCHASE_CLASS')) cols.splice(9, 0, { k: 'purchase_class', l: 'Class', t: 'badge' });
    const foot = { gross_wt: rows.reduce((s, r) => s + +r.gross_wt, 0), net_wt: rows.reduce((s, r) => s + +r.net_wt, 0),
      price: rows.reduce((s, r) => s + (+r.price || 0), 0) };
    box.innerHTML = table(cols, rows, { click: true, foot, empty: 'No items match.' });
    bindRows(box, rows, r => location.hash = '#/item/' + r.id);
  };
  const load = async () => {
    const params = new URLSearchParams();
    Object.entries(formValues(el.querySelector('#flt'))).forEach(([k, v]) => { if (v) params.set(k, v); });
    sessionStorage.setItem('inv-filters', params.toString());
    rows = await api('/items?' + params);
    const value = rows.reduce((s, r) => s + (+r.price || 0), 0);
    el.querySelector('#sum').textContent = `${rows.length} item(s) · net ${fmt.wt(rows.reduce((s, r) => s + +r.net_wt, 0))} · ${fmt.rupees(value)} at today's rate`;
    draw();
  };
  el.querySelector('#flt').onsubmit = e => { e.preventDefault(); load().catch(fail); };
  el.querySelector('#clear').onclick = () => { sessionStorage.removeItem('inv-filters'); inventory(el); };
  el.querySelectorAll('[data-v]').forEach(b => b.onclick = () => { view = b.dataset.v; sessionStorage.setItem('inv-view', view); draw(); });
  el.querySelector('#labels').onclick = () => rows.length ? location.hash = '#/labels/' + rows.slice(0, 200).map(r => r.id).join(',') : toast('No items.');
  el.querySelector('#check').onclick = async () => {
    const bad = await api('/items/ledger-check');
    toast(bad.length ? `${bad.length} item(s) differ from the stock ledger: ${bad.map(b => b.tag_code).join(', ')}` : 'Every item matches the stock ledger.', bad.length ? 'bad' : 'ok');
  };
  await load();
}

export async function item(el, id) {
  const [it, m] = await Promise.all([api('/items/' + id), loadMasters()]);
  const p = it.price_breakdown;
  el.innerHTML = `<div class="pagehead"><div><h1>${esc(it.name)}</h1><p>${esc(it.tag_code)} · ${esc(it.category_name)} ${badge(it.status)} ${it.purchase_class ? badge(it.purchase_class) : ''}</p></div>
    <div class="row"><a class="btn" href="#/inventory">← Inventory</a><a class="btn" href="#/labels/${it.id}">${ICONS.print} Label</a>
      ${can('ITEM_EDIT') && it.status === 'IN_STOCK' ? '<button id="edit">Edit</button><button id="move">Move</button>' : ''}
      ${can('PURCHASE') && it.status === 'IN_STOCK' && it.vendor_id ? '<button class="danger" id="ret">Return to vendor</button>' : ''}
      ${can('BILL') && it.status === 'IN_STOCK' ? '<a class="btn primary" href="#/sale/new">Bill it</a>' : ''}</div></div>
    <div class="split"><div>
      <div class="card"><div class="row" style="align-items:flex-start"><div style="width:110px">${qrSvg(it.tag_code, 4)}</div>
        <dl class="kv" style="flex:1"><dt>Metal / purity</dt><dd>${esc(fmt.label(it.metal || 'Gifting'))} ${esc(it.purity_code || '')}</dd>
        <dt>Gross weight</dt><dd>${fmt.wt(it.gross_wt)}</dd><dt>Stone weight</dt><dd>${fmt.wt(it.stone_wt)}</dd><dt>Net weight</dt><dd>${fmt.wt(it.net_wt)}</dd>
        ${+it.quantity > 1 ? `<dt>Quantity</dt><dd>${it.quantity}</dd>` : ''}<dt>HUID</dt><dd>${esc(it.huid || '—')}</dd>
        <dt>Design / collection</dt><dd>${esc(it.design_code || '—')} ${esc(it.collection || '')}</dd><dt>Location</dt><dd>${esc(it.location_name || '—')}</dd>
        <dt>Vendor</dt><dd>${esc(it.vendor_name || '—')}</dd>${it.cost_amount !== undefined ? `<dt>Cost</dt><dd>${fmt.money(it.cost_amount)}</dd>` : ''}
        <dt>RFID EPC</dt><dd class="muted">${esc(it.rfid_epc || 'Not encoded (RFID phase)')}</dd></dl></div></div>
      ${it.stones.length ? `<div class="card"><h3>Stones</h3>${table([{ k: 'stone_type', l: 'Type' }, { k: 'pieces', l: 'Pcs', t: 'int' }, { k: 'carat', l: 'Carat', t: 'num' },
        { k: 'rate_per_carat', l: '₹/ct', t: 'money' }, { k: 'stone_value', l: 'Value', t: 'money' }, { k: 'clarity', l: 'Clarity' }, { k: 'colour', l: 'Colour' },
        { k: 'certificate', l: 'Certificate' }], it.stones)}</div>` : ''}
      <div class="card"><h3>Stock movements (ledger)</h3>${table([{ k: 'created_at', l: 'When', t: 'dt' }, { k: 'movement_type', l: 'Movement', t: 'badge' },
        { k: 'qty', l: 'Qty', t: 'int' }, { k: 'doc_type', l: 'Document' }, { k: 'status_after', l: 'Status after', t: 'badge' }, { k: 'username', l: 'By' },
        { k: 'note', l: 'Note' }], it.movements)}</div></div>
      <div class="card"><h3>Price at today's rate</h3>${p ? `<div class="totals">
        ${it.metal ? `<span>${fmt.num(it.net_wt)} g × ${fmt.money(p.rate)}</span><span class="num">${fmt.money(p.metal_value)}</span>
        <span>Wastage</span><span class="num">${fmt.money(p.wastage_value)}</span><span>Making</span><span class="num">${fmt.money(p.making_value)}</span>
        <span>Stones</span><span class="num">${fmt.money(p.stone_value)}</span>` : ''}
        <span>Taxable</span><span class="num">${fmt.money(p.taxable)}</span><span>GST ${fmt.num(p.gst_pct)}%</span><span class="num">${fmt.money(p.gst)}</span>
        <span class="grand">Price</span><span class="grand num">${fmt.money(p.total)}</span></div>`
        : '<p class="muted">Approve today\'s rate to see the price.</p>'}</div></div>`;
  el.querySelector('#edit')?.addEventListener('click', async () => {
    const v = await ask('Edit ' + it.tag_code, [
      { name: 'name', label: 'Name', value: it.name }, { name: 'gross_wt', label: 'Gross g', type: 'number', value: it.gross_wt },
      { name: 'stone_wt', label: 'Stone g', type: 'number', value: it.stone_wt }, { name: 'net_wt', label: 'Net g', type: 'number', value: it.net_wt },
      { name: 'making_type', label: 'Making type (blank = category default)', type: 'select', options: [['', 'Category default'], ['PER_GRAM', '₹ per gram'], ['PERCENT', '% of metal value'], ['FIXED', 'Fixed ₹']], value: it.making_type || '' },
      { name: 'making_value', label: 'Making value', type: 'number', value: it.making_value ?? '' },
      { name: 'wastage_pct', label: 'Wastage %', type: 'number', value: it.wastage_pct ?? '' },
      ...(it.metal ? [] : [{ name: 'fixed_price', label: 'MRP ₹', type: 'number', value: it.fixed_price }]),
      { name: 'huid', label: 'HUID', value: it.huid }, { name: 'design_code', label: 'Design code', value: it.design_code }, { name: 'notes', label: 'Notes', value: it.notes }],
    { note: 'Weight changes are recorded in the audit log.' });
    if (!v) return;
    try { await api('/items/' + id, { method: 'PUT', body: v }); toast('Saved.', 'ok'); item(el, id); } catch (e) { fail(e); }
  });
  el.querySelector('#move')?.addEventListener('click', async () => {
    const v = await ask('Move to', [{ name: 'loc', label: 'Location', type: 'select', options: m.locations.filter(l => l.kind !== 'EXTERNAL').map(l => [l.id, l.name]), value: it.location_id }]);
    if (!v) return;
    try { await api(`/items/${id}/transfer/${v.loc}`, { method: 'POST' }); toast('Moved.', 'ok'); item(el, id); } catch (e) { fail(e); }
  });
  el.querySelector('#ret')?.addEventListener('click', async () => {
    const v = await ask('Return to ' + it.vendor_name, [{ name: 'reason', label: 'Reason', required: true }]);
    if (!v) return;
    try { await api('/purchases/return-item/' + id, { method: 'POST', body: v }); toast('Returned to vendor.', 'ok'); item(el, id); } catch (e) { fail(e); }
  });
}

export async function newItem(el) {
  const m = await loadMasters();
  const cats = m.categories;
  el.innerHTML = `<div class="pagehead"><div><h1>Add opening stock</h1><p>For pieces already in the shop. New stock from vendors is added through Purchases.</p></div></div>
    <form class="card" id="f"><div class="fields" id="ff"></div><div class="row"><button class="primary">Save and print label</button></div></form>`;
  const draw = (v = {}) => {
    const c = cats.find(x => String(x.id) === String(v.category_id)) || cats[0];
    const fields = [{ name: 'category_id', label: 'Category', type: 'select', options: cats.map(x => [x.id, x.name]), value: c.id },
      { name: 'name', label: 'Item name', value: v.name, placeholder: c.name }, { name: 'tag_code', label: 'Tag code', value: v.tag_code, placeholder: 'auto' }];
    if (c.metal) {
      fields.push({ name: 'purity_code', label: 'Purity', type: 'select', options: m.purities.filter(p => p.metal === c.metal).map(p => p.code), value: v.purity_code },
        { name: 'gross_wt', label: 'Gross g', type: 'number', value: v.gross_wt, required: true }, { name: 'stone_wt', label: 'Stone g', type: 'number', value: v.stone_wt },
        { name: 'net_wt', label: 'Net g', type: 'number', value: v.net_wt, placeholder: 'gross − stone' }, { name: 'huid', label: 'HUID', value: v.huid });
      if (c.family === 'DIAMOND') fields.push({ name: 'carat', label: 'Diamond ct', type: 'number', value: v.carat }, { name: 'rate_per_carat', label: '₹ per ct', type: 'number', value: v.rate_per_carat });
    } else {
      fields.push({ name: 'fixed_price', label: 'MRP ₹', type: 'number', value: v.fixed_price, required: true }, { name: 'quantity', label: 'Quantity', type: 'number', step: 1, value: v.quantity || 1 });
    }
    fields.push({ name: 'design_code', label: 'Design code', value: v.design_code }, { name: 'location_id', label: 'Location', type: 'select', options: m.locations.map(l => [l.id, l.name]), value: v.location_id },
      { name: 'cost_amount', label: 'Cost ₹ (optional)', type: 'number', value: v.cost_amount });
    el.querySelector('#ff').innerHTML = fields.map(fieldHtml).join('');
    el.querySelector('[name=category_id]').onchange = () => draw(formValues(el.querySelector('#f')));
  };
  draw();
  el.querySelector('#f').onsubmit = async e => {
    e.preventDefault();
    const v = formValues(e.target);
    if (v.carat) v.stones = [{ stone_type: 'DIAMOND', carat: v.carat, rate_per_carat: v.rate_per_carat || 0 }];
    try { const it = await api('/items', { method: 'POST', body: v }); toast('Saved ' + it.tag_code, 'ok'); location.hash = '#/labels/' + it.id; } catch (err) { fail(err); }
  };
}

/** Printable QR labels (62 x 30 mm) for jewellery tags. */
export async function labels(el, ids) {
  const items = await Promise.all(ids.split(',').slice(0, 200).map(id => api('/items/' + id)));
  el.innerHTML = `<div class="row noprint" style="margin-bottom:1rem"><button onclick="history.back()">← Back</button><span class="spacer"></span>
    <span class="muted small">62 × 30 mm labels. Print on a label printer or A4 sticker sheet.</span><button class="primary" onclick="window.print()">${ICONS.print} Print labels</button></div>
    <div class="labels">${items.map(i => `<div class="label">${qrSvg(i.tag_code, 3)}<div><b>${esc(i.tag_code)}</b><br>${esc(i.name).slice(0, 26)}<br>
      ${i.metal ? `${esc(i.purity_code)} · G ${fmt.num(i.gross_wt)} · N ${fmt.num(i.net_wt)}` : `MRP ${fmt.rupees(i.fixed_price)}`}
      ${+i.stone_carat ? `<br>Dia ${fmt.num(i.stone_carat)} ct` : ''}${i.huid ? `<br>HUID ${esc(i.huid)}` : ''}</div></div>`).join('')}</div>`;
}

// ---------- daily stock tally ----------

export async function tallyList(el) {
  const [rows, m] = await Promise.all([api('/tally'), loadMasters()]);
  el.innerHTML = `<div class="pagehead"><div><h1>Daily stock tally</h1><p>Scan every tag on the counter or tray; the system lists what is missing, extra or unknown.</p></div></div>
    ${can('TALLY_CAPTURE') ? `<form class="card" id="open"><h2>Start a tally</h2><div class="fields">
      ${fieldHtml({ name: 'location_id', label: 'Counter / location', type: 'select', options: [['', 'Whole shop']].concat(m.locations.filter(l => l.kind !== 'EXTERNAL' && l.kind !== 'REPAIR').map(l => [l.id, l.name])) })}
      ${fieldHtml({ name: 'category_id', label: 'Category (optional)', type: 'select', options: [['', 'All categories']].concat(m.categories.map(c => [c.id, c.name])) })}
      ${fieldHtml({ name: 'notes', label: 'Notes' })}</div><button class="primary">Open tally session</button></form>` : ''}
    <div class="card"><h2>Sessions</h2><div id="t"></div></div>`;
  el.querySelector('#t').innerHTML = table([{ k: 'id', l: '#', t: 'int' }, { k: 'business_date', l: 'Date', t: 'date' }, { k: 'location_name', l: 'Location', f: r => esc(r.location_name || 'Whole shop') },
    { k: 'category_name', l: 'Category', f: r => esc(r.category_name || 'All') }, { k: 'expected_count', l: 'Expected', t: 'int' }, { k: 'scanned_count', l: 'Scanned', t: 'int' },
    { k: 'variance_count', l: 'Variances', t: 'int' }, { k: 'status', l: 'Status', t: 'badge' }, { k: 'opened_by', l: 'Opened by' }], rows, { click: true, empty: 'No tally yet.' });
  bindRows(el.querySelector('#t'), rows, r => location.hash = '#/tally/' + r.id);
  el.querySelector('#open')?.addEventListener('submit', async e => {
    e.preventDefault();
    try { const s = await api('/tally', { method: 'POST', body: formValues(e.target) }); location.hash = '#/tally/' + s.id; } catch (err) { fail(err); }
  });
}

export async function tallySession(el, id) {
  let s = await api('/tally/' + id);
  const open = s.status === 'OPEN';
  el.innerHTML = `<div class="pagehead"><div><h1>Tally #${s.id}</h1><p>${fmt.date(s.business_date)} · ${esc(s.location_name || 'Whole shop')} · ${esc(s.category_name || 'All categories')} ${badge(s.status)}</p></div>
    <div class="row"><a class="btn" href="#/tally">← Sessions</a>${open ? '<button id="cmp">Compare</button>' : ''}${open && can('TALLY_APPROVE') ? '<button class="primary" id="close">Close tally</button>' : ''}
    ${!open && can('TALLY_APPROVE') ? '<button id="reopen">Reopen</button>' : ''}<button onclick="window.print()">${ICONS.print} Print</button></div></div>
    <div class="grid g4 stats" id="stats"></div>
    <div class="split" style="margin-top:1rem"><div>
      ${open ? `<div class="card noprint"><h3>Scan tags</h3><div id="scan"></div>
        <details style="margin-top:.6rem"><summary class="small">Paste a bulk list (one tag per line — e.g. exported from a handheld)</summary>
        <textarea id="bulk" rows="4" style="margin-top:.4rem"></textarea><button class="small" id="bulkgo" style="margin-top:.4rem">Add all</button></details>
        <div id="last" class="small muted" style="margin-top:.5rem"></div></div>` : ''}
      <div class="card"><h3>By category</h3><div id="cats"></div></div>
      <div class="card"><h3>Variances to review</h3><div id="var"></div></div></div>
      <div><div class="card"><h3>Missing (expected, not scanned)</h3><div id="miss"></div></div>
        <div class="card"><h3>Extra / unknown tags</h3><div id="extra"></div></div>
        <div class="card"><h3>Separate buckets</h3><p class="small">Customer repair pieces in the shop: <b id="rb"></b><br>With karigar: <b id="kb"></b><br>
          <span class="muted">These are never counted as sale stock.</span></p></div></div></div>`;
  const draw = () => {
    el.querySelector('#stats').innerHTML = [['Expected', s.expected_count], ['Scanned', s.scanned_count], ['Matched', s.matched_count],
      ['Missing', s.missing.length + ` <span class="small muted">${fmt.wt(s.missing_wt)}</span>`]].map(([k, v]) =>
      `<div class="card stat"><div class="k">${k}</div><div class="v">${v}</div></div>`).join('');
    el.querySelector('#cats').innerHTML = table([{ k: 'code', l: 'Code' }, { k: 'name', l: 'Category' }, { k: 'expected', l: 'Expected', t: 'int' },
      { k: 'physical', l: 'Physical', t: 'int' }, { k: 'v', l: 'Variance', f: r => { const d = r.physical - r.expected; return d ? `<b style="color:var(--bad)">${d}</b>` : '0'; } },
      { k: 'expected_wt', l: 'Exp. net g', t: 'wt' }, { k: 'physical_wt', l: 'Phys. net g', t: 'wt' }], s.categories, { resp: false });
    el.querySelector('#miss').innerHTML = table([{ k: 'tag_code', l: 'Tag' }, { k: 'name', l: 'Item' }, { k: 'net_wt', l: 'Net g', t: 'wt' }], s.missing, { empty: 'Nothing missing.' });
    el.querySelector('#extra').innerHTML = table([{ k: 'tag_code', l: 'Tag' }, { k: 'name', l: 'Item' }, { k: 'status', l: 'Status', t: 'badge' },
      { k: 'location_name', l: 'Belongs to' }], s.unexpected, { empty: 'No extra tags.' }) +
      (s.unknown.length ? `<p class="small" style="margin-top:.5rem">Unknown codes: ${s.unknown.map(u => `<span class="badge warn">${esc(u.code)}</span>`).join(' ')}</p>` : '');
    el.querySelector('#rb').textContent = s.repair_bucket;
    el.querySelector('#kb').textContent = s.karigar_bucket;
    const v = el.querySelector('#var');
    v.innerHTML = s.variances.length ? `<div class="tablewrap"><table class="resp"><thead><tr><th>Kind</th><th>Tag</th><th>Item</th><th>Decision</th></tr></thead><tbody>
      ${s.variances.map(x => `<tr><td data-l="Kind">${badge(x.kind)}</td><td data-l="Tag">${esc(x.code)}</td><td data-l="Item">${esc(x.name || '')}</td>
        <td data-l="Decision">${x.resolution ? `${badge(x.resolution)} <span class="small muted">${esc(x.reason)} — ${esc(x.resolved_by)}</span>`
          : open && can('TALLY_APPROVE') ? `${x.kind === 'MISSING' ? `<button class="small danger" data-res="${x.id}" data-r="MARK_LOST">Mark lost</button>` : ''}
            <button class="small" data-res="${x.id}" data-r="ACCEPTED">Accept with reason</button>` : '<span class="muted small">Waiting for manager</span>'}</td></tr>`).join('')}
      </tbody></table></div>` : `<p class="muted small">${open ? 'Press Compare when scanning is done.' : 'No variances.'}</p>`;
    v.querySelectorAll('[data-res]').forEach(b => b.onclick = async () => {
      const r = await ask(b.dataset.r === 'MARK_LOST' ? 'Mark item as lost' : 'Accept variance', [{ name: 'reason', label: 'Reason', required: true,
        placeholder: b.dataset.r === 'MARK_LOST' ? 'e.g. not found after search' : 'e.g. sent for polishing, label damaged' }]);
      if (!r) return;
      try { s = await api('/tally/variance/' + b.dataset.res, { method: 'POST', body: { resolution: b.dataset.r, reason: r.reason } }); draw(); } catch (e) { fail(e); }
    });
  };
  draw();
  if (open) {
    const add = async codes => {
      try {
        s = await api(`/tally/${id}/scan`, { method: 'POST', body: { codes } });
        const lastScan = s.recent_scans[0];
        el.querySelector('#last').innerHTML = lastScan ? `Last: <b>${esc(lastScan.code)}</b> ${esc(lastScan.name || '(unknown tag)')} · ${s.added ? 'added' : 'already scanned'}` : '';
        if (s.added) navigator.vibrate?.(40);
        draw();
      } catch (e) { fail(e); }
    };
    scanner(el.querySelector('#scan'), c => add([c]));
    el.querySelector('#bulkgo').onclick = () => { add(el.querySelector('#bulk').value.split(/[\s,;]+/).filter(Boolean)); el.querySelector('#bulk').value = ''; };
    el.querySelector('#cmp').onclick = async () => { try { s = await api(`/tally/${id}/compare`, { method: 'POST' }); draw(); toast('Variance list ready for review.'); } catch (e) { fail(e); } };
    el.querySelector('#close')?.addEventListener('click', async () => {
      try { await api(`/tally/${id}/close`, { method: 'POST' }); toast('Tally closed.', 'ok'); tallySession(el, id); } catch (e) { fail(e); }
    });
  }
  el.querySelector('#reopen')?.addEventListener('click', async () => {
    const r = await ask('Reopen tally', [{ name: 'reason', label: 'Reason (logged)', required: true }]);
    if (!r) return;
    try { await api(`/tally/${id}/reopen`, { method: 'POST', body: r }); tallySession(el, id); } catch (e) { fail(e); }
  });
}

// ---------- repairs ----------

export async function repairs(el) {
  const st = sessionStorage.getItem('rep-status') || 'OPEN';
  const rows = await api('/repairs?status=' + st);
  el.innerHTML = `<div class="pagehead"><div><h1>Repairs & job work</h1><p>Customer pieces are held in repair custody — never in sale stock.</p></div>
    <div class="row">${can('REPAIR') ? '<a class="btn primary" href="#/repair/new">New repair intake</a>' : ''}</div></div>
    <div class="card"><div id="scan"></div></div>
    <div class="tabs">${[['OPEN', 'Open'], ['RECEIVED', 'Received'], ['WITH_KARIGAR', 'With karigar'], ['READY', 'Ready'], ['DELIVERED', 'Delivered'], ['', 'All']].map(([k, l]) =>
      `<button class="${k === st ? 'on' : ''}" data-s="${k}">${l}</button>`).join('')}</div><div id="t"></div>`;
  el.querySelector('#t').innerHTML = table([{ k: 'job_no', l: 'Job' }, { k: 'customer_name', l: 'Customer' }, { k: 'customer_phone', l: 'Phone' },
    { k: 'description', l: 'Item' }, { k: 'weight_in', l: 'Weight in', t: 'wt' }, { k: 'status', l: 'Status', t: 'badge' }, { k: 'karigar_name', l: 'Karigar' },
    { k: 'promised_date', l: 'Promised', f: r => fmt.date(r.promised_date) + (r.overdue ? ' ' + badge('OVERDUE') : '') }], rows, { click: true, empty: 'No jobs.' });
  bindRows(el.querySelector('#t'), rows, r => location.hash = '#/repair/' + r.id);
  el.querySelectorAll('[data-s]').forEach(b => b.onclick = () => { sessionStorage.setItem('rep-status', b.dataset.s); repairs(el); });
  scanner(el.querySelector('#scan'), async code => {
    try { const j = await api('/repairs/lookup?no=' + encodeURIComponent(code)); location.hash = '#/repair/' + j.id; } catch (e) { fail(e); }
  }, { placeholder: 'Scan the repair tag / type job number', keepFocus: false });
}

export async function newRepair(el) {
  const m = await loadMasters();
  el.innerHTML = `<div class="pagehead"><div><h1>Repair intake</h1><p>Weigh the piece in front of the customer; a repair tag and receipt are printed.</p></div></div>
    <form class="card" id="f"><div id="cust"></div><div class="fields" style="margin-top:.75rem">
      ${fieldHtml({ name: 'description', label: 'Item description', required: true, placeholder: 'e.g. Ladies ring with stone' })}
      ${fieldHtml({ name: 'metal', label: 'Metal', type: 'select', options: ['GOLD', 'SILVER', 'PLATINUM'] })}
      ${fieldHtml({ name: 'purity_code', label: 'Purity', type: 'select', options: [['', '—']].concat([...new Set(m.purities.map(p => p.code))].map(c => [c, c])) })}
      ${fieldHtml({ name: 'weight_in', label: 'Weight in (g)', type: 'number', required: true })}
      ${fieldHtml({ name: 'repair_type', label: 'Repair type', placeholder: 'Resize, solder, polish, stone setting…' })}
      ${fieldHtml({ name: 'item_condition', label: 'Condition noted' })}
      ${fieldHtml({ name: 'estimate', label: 'Estimate ₹', type: 'number' })}
      ${fieldHtml({ name: 'promised_date', label: 'Promised date', type: 'date' })}
      ${fieldHtml({ name: 'advance', label: 'Advance ₹', type: 'number' })}
      ${fieldHtml({ name: 'advance_mode', label: 'Advance mode', type: 'select', options: ['CASH', 'UPI', 'CARD', 'BANK'] })}
    </div><button class="primary">Save and print receipt</button></form>`;
  let customer = null;
  partyPicker(el.querySelector('#cust'), 'CUSTOMER', p => { customer = p; });
  el.querySelector('#f').onsubmit = async e => {
    e.preventDefault();
    if (!customer) return toast('Choose the customer.', 'bad');
    try {
      const j = await api('/repairs', { method: 'POST', body: { ...formValues(e.target), customer_id: customer.id } });
      toast('Job ' + j.job_no + ' created.', 'ok');
      location.hash = '#/repair/' + j.id;
    } catch (err) { fail(err); }
  };
}

export async function repair(el, id) {
  const [j, karigars] = await Promise.all([api('/repairs/' + id), api('/parties?type=KARIGAR')]);
  const next = { RECEIVED: ['WITH_KARIGAR', 'IN_PROGRESS', 'READY'], WITH_KARIGAR: ['READY'], IN_PROGRESS: ['READY', 'WITH_KARIGAR'], READY: ['DELIVERED'], DELIVERED: [] }[j.status];
  el.innerHTML = `<div class="row noprint" style="margin-bottom:1rem"><a class="btn" href="#/repairs">← Repairs</a><span class="spacer"></span>
      ${can('REPAIR') ? next.map(n => `<button class="${n === 'DELIVERED' || n === 'READY' ? 'primary' : ''}" data-n="${n}">${n === 'WITH_KARIGAR' ? 'Give to karigar' : n === 'IN_PROGRESS' ? 'Start in-house' : n === 'READY' ? 'Mark ready' : 'Deliver to customer'}</button>`).join('') : ''}
      <button onclick="window.print()">${ICONS.print} Print receipt</button></div>
    <div class="doc"><div class="head"><div><h1>Repair receipt</h1><div>${esc(j.job_no)} ${badge(j.status)}</div></div><div style="width:90px">${qrSvg(j.job_no, 3)}</div></div>
      <div class="split" style="grid-template-columns:1fr 1fr"><dl class="kv"><dt>Customer</dt><dd>${esc(j.customer_name)} ${esc(j.customer_phone || '')}</dd>
        <dt>Item</dt><dd>${esc(j.description)}</dd><dt>Metal</dt><dd>${esc(j.metal || '')} ${esc(j.purity_code || '')}</dd>
        <dt>Repair</dt><dd>${esc(j.repair_type || '—')}</dd><dt>Condition</dt><dd>${esc(j.item_condition || '—')}</dd>
        <dt>Received</dt><dd>${fmt.dt(j.created_at)}</dd><dt>Promised</dt><dd>${fmt.date(j.promised_date)}</dd></dl>
      <dl class="kv"><dt>Weight in</dt><dd>${fmt.wt(j.weight_in)}</dd><dt>Issued to karigar</dt><dd>${fmt.wt(j.weight_issued)} ${esc(j.karigar_name || '')}</dd>
        <dt>Back from karigar</dt><dd>${fmt.wt(j.weight_returned)}${j.karigar_difference !== undefined ? ` (${fmt.num(j.karigar_difference)} g)` : ''}</dd>
        <dt>Extra metal added</dt><dd>${fmt.wt(j.extra_metal_wt)}</dd><dt>Weight out</dt><dd>${fmt.wt(j.weight_out)}</dd>
        <dt>Metal gain / loss</dt><dd>${j.metal_difference !== undefined ? fmt.num(j.metal_difference) + ' g' : '—'}</dd>
        <dt>Estimate</dt><dd>${fmt.money(j.estimate)}</dd><dt>Charges</dt><dd>${fmt.money(j.charges)}</dd><dt>Paid</dt><dd>${fmt.money(j.paid)}</dd></dl></div>
      <h3 style="margin-top:1rem">History</h3>${table([{ k: 'at', l: 'When', t: 'dt' }, { k: 'status', l: 'Step', t: 'badge' }, { k: 'weight', l: 'Weight g', t: 'wt' },
        { k: 'note', l: 'Note' }, { k: 'username', l: 'By' }], j.events, { resp: false })}
      <p class="small muted" style="margin-top:1rem">Please bring this receipt when collecting. The piece was weighed in your presence.</p></div>`;
  el.querySelectorAll('[data-n]').forEach(b => b.onclick = async () => {
    const n = b.dataset.n;
    const fields = n === 'WITH_KARIGAR' ? [{ name: 'karigar_id', label: 'Karigar', type: 'select', options: karigars.map(k => [k.id, k.name]) },
      { name: 'weight', label: 'Weight issued (g)', type: 'number', required: true, value: j.weight_out || j.weight_in }]
      : n === 'READY' ? [{ name: 'weight', label: 'Finished weight (g)', type: 'number', required: true }, { name: 'extra_metal_wt', label: 'Extra metal added (g)', type: 'number' }]
        : n === 'DELIVERED' ? [{ name: 'charges', label: 'Charges ₹', type: 'number', required: true, value: j.estimate },
          { name: 'amount', label: `Collect now ₹ (advance ${fmt.money(j.paid)} already paid)`, type: 'number', value: Math.max(0, (+j.estimate || 0) - (+j.paid || 0)).toFixed(3) },
          { name: 'mode', label: 'Mode', type: 'select', options: ['CASH', 'UPI', 'CARD', 'BANK'] }]
          : [];
    fields.push({ name: 'note', label: 'Note' });
    const v = await ask(b.textContent, fields);
    if (!v) return;
    try { await api(`/repairs/${id}/status`, { method: 'POST', body: { ...v, status: n } }); toast('Updated.', 'ok'); repair(el, id); } catch (e) { fail(e); }
  });
}

export { state };
