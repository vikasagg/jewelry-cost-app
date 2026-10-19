// Dashboard, metal rates, voice/AI search results, reports and ledgers.
import { state, api, can, esc, fmt, table, bindRows, toast, fail, badge, speak, fileUrl, today, ask as askDialog } from './core.js';

const PURITY_ORDER = { GOLD: ['24K', '22K', '20K', '18K', '14K', '9K'], SILVER: ['999', '925', '800'], PLATINUM: ['950', '900'] };

// ---------- dashboard ----------

export async function dashboard(el) {
  const d = await api('/dashboard');
  const s = state.session;
  const r = d.rate.approved;
  const metals = d.stock.by_metal;
  el.innerHTML = `
    <div class="pagehead"><div><h1>Namaste, ${esc(s.user.full_name.split(' ')[0])}</h1>
      <p>${fmt.date(d.business_date)} · ${esc(s.shop.name)}</p></div>
      <div class="row">${can('BILL') ? `<a class="btn primary big" href="#/sale/new">New bill</a>` : ''}
      <a class="btn big" href="#/tally">Stock tally</a></div></div>
    ${d.alerts.map(a => `<div class="alert ${a.includes('not approved') ? 'bad' : ''}">${esc(a)}</div>`).join('')}
    <div class="grid g4 stats" style="margin-top:.75rem">
      <div class="card stat"><div class="k">Sales today</div><div class="v">${fmt.rupees(d.sales_today.net)}</div>
        <div class="s">${d.sales_today.bills} bill(s) · ${d.sales_today.pieces} piece(s)</div></div>
      <div class="card stat"><div class="k">Stock value (today's rate)</div><div class="v">${fmt.rupees(d.stock.value)}</div>
        <div class="s">${fmt.int(d.stock.pieces)} pieces in stock</div></div>
      <div class="card stat"><div class="k">Purchases today</div><div class="v">${fmt.rupees(d.purchases_today.total)}</div>
        <div class="s">${d.purchases_today.purchases} purchase(s)</div></div>
      <div class="card stat"><div class="k">Repairs</div><div class="v">${d.repairs.open} open</div>
        <div class="s">${d.repairs.ready} ready · <span style="color:var(--bad)">${d.repairs.overdue} overdue</span></div></div>
    </div>
    <div class="split" style="margin-top:1rem">
      <div>
        <div class="card"><h3>Stock by metal</h3>
          ${table([{ k: 'metal', l: 'Metal', f: m => esc(fmt.label(m.metal)) }, { k: 'pieces', l: 'Pieces', t: 'int' },
            { k: 'net_wt', l: 'Net weight (g)', t: 'wt' }, { k: 'value', l: 'Value', t: 'rupees' }], metals)}
        </div>
        <div class="card"><div class="row"><h3>Recent bills</h3><span class="spacer"></span><a href="#/sales" class="small">All sales</a></div>
          <div id="recent"></div></div>
      </div>
      <div>
        <div class="card"><div class="row"><h3>Today's rate</h3><span class="spacer"></span>${r ? badge('APPROVED') : badge('PROPOSED')}</div>
          ${r ? `<table>${r.lines.filter(l => l.metal === 'GOLD').map(l => `<tr><td>Gold ${esc(l.purity_code)}</td>
            <td class="num">${fmt.money(l.rate_per_gram)}/g</td><td class="num muted">${fmt.rupees(l.rate_per_gram * 10)}/10g</td></tr>`).join('')}
            <tr><td>Silver 999</td><td class="num">${fmt.money(r.silver_base)}/g</td><td class="num muted">${fmt.rupees(r.silver_base * 1000)}/kg</td></tr>
            <tr><td>Platinum</td><td class="num">${fmt.money(r.platinum_base)}/g</td><td></td></tr></table>
            <p class="muted small">Approved by ${esc(r.approved_by)} at ${fmt.dt(r.approved_at)}. Holds for the whole day.</p>`
            : `<p>Billing waits until today's rate is approved.</p><a class="btn primary" href="#/rates">Set today's rate</a>`}
        </div>
        ${d.books ? `<div class="card"><h3>Books</h3><dl class="kv">
          <dt>Cash in hand</dt><dd class="num">${fmt.money(d.books.CASH)}</dd>
          <dt>Bank</dt><dd class="num">${fmt.money(d.books.BANK)}</dd>
          <dt>Fine gold</dt><dd class="num">${fmt.wt(d.books.GOLD)}</dd>
          <dt>Fine silver</dt><dd class="num">${fmt.wt(d.books.SILVER)}</dd></dl>
          <a class="small" href="#/ledgers">Open cash, bank and metal books</a></div>` : ''}
        <div class="card"><h3>Try asking</h3><div class="list small">
          ${['diamond jewellery below 50000', '22 carat gold chains between 20 and 30 grams', 'how many silver anklets in stock',
            'sone ki angoothi 50 hazar se kam', 'aaj ka 22 carat rate kya hai', 'repair for rahul'].map(q =>
            `<a href="#/ask/${encodeURIComponent(q)}">“${esc(q)}”</a>`).join('')}</div></div>
      </div>
    </div>`;
  const recent = el.querySelector('#recent');
  recent.innerHTML = table([{ k: 'invoice_no', l: 'Invoice' }, { k: 'customer_name', l: 'Customer' },
    { k: 'created_at', l: 'Time', t: 'dt' }, { k: 'net_payable', l: 'Amount', t: 'money' }], d.recent_sales, { click: true, empty: 'No bills yet.' });
  bindRows(recent, d.recent_sales, r => location.hash = '#/sale/' + r.id);
}

// ---------- metal rates ----------

export async function rates(el) {
  const [t, history, cfg] = await Promise.all([api('/rates/today'), api('/rates/history'), api('/config')]);
  const conf = Object.fromEntries(cfg.map(c => [c.config_key, c.config_value]));
  const unit = { GOLD: +conf['rate.entryUnit.gold'] || 10, SILVER: +conf['rate.entryUnit.silver'] || 1000, PLATINUM: +conf['rate.entryUnit.platinum'] || 10 };
  const unitLabel = g => g === 1 ? 'per gram' : g === 1000 ? 'per kg' : `per ${g} g`;
  const last = t.approved || t.last_approved;
  const approved = t.approved;
  el.innerHTML = `
    <div class="pagehead"><div><h1>Metal rates</h1><p>Set once each morning. A live rate only becomes a proposal; prices change only after approval.</p></div></div>
    ${approved ? `<div class="alert ok">Today's rate is approved (${esc(approved.source === 'LIVE' ? 'from live feed' : 'entered by hand')}) by ${esc(approved.approved_by)} at ${fmt.dt(approved.approved_at)} and holds all day. Entering a new rate needs approval again.</div>`
      : `<div class="alert bad">No approved rate for today — billing is paused until one is approved.</div>`}
    <div class="split">
      <div class="card">
        <h2>Enter today's base rate</h2>
        <p class="muted small">Only the 24K gold rate is needed for gold — 22K, 20K, 18K, 14K and 9K are calculated as 92%, 84%, 76%, 60% and 40% (Settings → Purities).</p>
        <form id="rf"><div class="fields">
          <div class="field"><label>Gold 24K (₹ ${unitLabel(unit.GOLD)})</label><input name="gold" type="number" step="0.001" min="0" inputmode="decimal" required value="${last ? (last.gold_24k * unit.GOLD).toFixed(3) : ''}"></div>
          <div class="field"><label>Silver 999 (₹ ${unitLabel(unit.SILVER)})</label><input name="silver" type="number" step="0.001" min="0" inputmode="decimal" required value="${last ? (last.silver_base * unit.SILVER).toFixed(3) : ''}"></div>
          <div class="field"><label>Platinum (₹ ${unitLabel(unit.PLATINUM)})</label><input name="platinum" type="number" step="0.001" min="0" inputmode="decimal" required value="${last ? (last.platinum_base * unit.PLATINUM).toFixed(3) : ''}"></div>
        </div>
        <div id="preview"></div>
        <div class="row" style="margin-top:.75rem">
          ${can('RATE_APPROVE') ? `<button class="primary" name="approve" value="1">Save and approve for today</button>` : ''}
          ${can('RATE_ENTER') ? `<button name="propose" value="1">Save as proposal</button>` : ''}
          <span class="spacer"></span>
          ${can('RATE_ENTER') && t.live_provider !== 'NONE' ? `<button type="button" id="live">Fetch live rate (${esc(t.live_provider)})</button>` : ''}
        </div></form>
      </div>
      <div>
        <div class="card"><h2>Waiting for approval</h2><div id="pending"></div></div>
        ${approved ? `<div class="card"><h2>Approved for today</h2>${rateLines(approved.lines)}</div>` : ''}
      </div>
    </div>
    <div class="card"><h2>Rate history</h2>${table([{ k: 'business_date', l: 'Date', t: 'date' }, { k: 'source', l: 'Source', t: 'badge' },
      { k: 'provider', l: 'Provider' }, { k: 'gold_24k', l: 'Gold 24K /g', t: 'money' }, { k: 'silver_base', l: 'Silver /g', t: 'money' },
      { k: 'platinum_base', l: 'Platinum /g', t: 'money' }, { k: 'status', l: 'Status', t: 'badge' }, { k: 'entered_by', l: 'Entered' },
      { k: 'approved_by', l: 'Approved / rejected' }], history)}</div>`;

  const form = el.querySelector('#rf');
  const perGram = () => ({
    gold24k: (+form.gold.value / unit.GOLD).toFixed(3),
    silver: (+form.silver.value / unit.SILVER).toFixed(3),
    platinum: (+form.platinum.value / unit.PLATINUM).toFixed(3),
  });
  const preview = async () => {
    if (!(+form.gold.value > 0 && +form.silver.value > 0 && +form.platinum.value > 0)) return;
    try {
      const lines = await api('/rates/preview', { method: 'POST', body: perGram() });
      el.querySelector('#preview').innerHTML = `<h3 style="margin-top:.5rem">Calculated rates</h3>${rateLines(lines)}`;
    } catch (e) { fail(e); }
  };
  form.addEventListener('input', () => { clearTimeout(form._t); form._t = setTimeout(preview, 300); });
  preview();
  form.addEventListener('submit', async e => {
    e.preventDefault();
    const approve = e.submitter?.name === 'approve';
    try {
      await api('/rates/manual', { method: 'POST', body: { ...perGram(), approve_now: approve } });
      toast(approve ? 'Rate approved for today.' : 'Rate saved as a proposal.', 'ok');
      window.dispatchEvent(new Event('rate-changed'));
      rates(el);
    } catch (err) { fail(err); }
  });
  el.querySelector('#live')?.addEventListener('click', async () => {
    try {
      await api('/rates/live', { method: 'POST' });
      toast('Live rate fetched as a proposal. Review and approve it.', 'ok');
      rates(el);
    } catch (err) { fail(err); }
  });

  const pend = el.querySelector('#pending');
  if (!t.pending.length) pend.innerHTML = '<p class="muted">Nothing waiting.</p>';
  else {
    pend.innerHTML = t.pending.map(p => `<div class="card" style="box-shadow:none">
      <div class="row"><b>${esc(p.source === 'LIVE' ? 'Live: ' + (p.provider || '') : 'Manual')}</b><span class="spacer"></span>${badge(p.status)}</div>
      <div class="small muted">by ${esc(p.entered_by)} at ${fmt.dt(p.entered_at)}</div>
      <dl class="kv" style="margin:.5rem 0"><dt>Gold 24K</dt><dd>${fmt.money(p.gold_24k)}/g · ${fmt.rupees(p.gold_24k * 10)}/10g</dd>
      <dt>Silver</dt><dd>${fmt.money(p.silver_base)}/g</dd><dt>Platinum</dt><dd>${fmt.money(p.platinum_base)}/g</dd></dl>
      ${can('RATE_APPROVE') ? `<div class="row"><button class="primary small" data-ok="${p.id}">Approve</button>
        <button class="small danger" data-no="${p.id}">Reject</button></div>` : ''}</div>`).join('');
    pend.querySelectorAll('[data-ok]').forEach(b => b.onclick = async () => {
      try { await api(`/rates/${b.dataset.ok}/approve`, { method: 'POST' }); toast('Approved.', 'ok'); window.dispatchEvent(new Event('rate-changed')); rates(el); } catch (e) { fail(e); }
    });
    pend.querySelectorAll('[data-no]').forEach(b => b.onclick = async () => {
      try { await api(`/rates/${b.dataset.no}/reject`, { method: 'POST' }); toast('Rejected.'); rates(el); } catch (e) { fail(e); }
    });
  }
}

function rateLines(lines) {
  const groups = {};
  lines.forEach(l => (groups[l.metal] ||= []).push(l));
  return `<table>${Object.entries(groups).map(([m, ls]) => ls.sort((a, b) =>
    (PURITY_ORDER[m] || []).indexOf(a.purity_code) - (PURITY_ORDER[m] || []).indexOf(b.purity_code)).map(l =>
    `<tr><td>${esc(fmt.label(m))} ${esc(l.purity_code)}${l.price_factor ? ` <span class="muted small">× ${(+l.price_factor * 100).toFixed(1)}%</span>` : ''}</td>
     <td class="num">${fmt.money(l.rate_per_gram)}/g</td>
     <td class="num muted">${m === 'SILVER' ? fmt.rupees(l.rate_per_gram * 1000) + '/kg' : fmt.rupees(l.rate_per_gram * 10) + '/10g'}</td></tr>`).join('')).join('')}</table>`;
}

// ---------- AI / voice search ----------

export async function ask(el, q) {
  const r = await api('/search/ask', { method: 'POST', body: { text: q } });
  const input = document.getElementById('askin');
  if (input) input.value = q;
  const items = r.results || [];
  el.innerHTML = `
    <div class="pagehead"><div><h1>“${esc(q)}”</h1><p>${esc(r.answer || '')}</p></div></div>
    <div class="card"><div class="row"><b class="small muted">Understood as:</b><div class="chips">${(r.chips || []).map(c => `<span class="chip">${esc(c)}</span>`).join('')}</div>
      <span class="spacer"></span><button class="small" id="edit">Refine filters</button></div></div>
    <div id="res" style="margin-top:1rem"></div>`;
  if (r.repairs) {
    el.querySelector('#res').innerHTML = table([{ k: 'job_no', l: 'Job' }, { k: 'customer_name', l: 'Customer' }, { k: 'description', l: 'Item' },
      { k: 'status', l: 'Status', t: 'badge' }, { k: 'promised_date', l: 'Promised', t: 'date' }], r.repairs, { click: true });
    bindRows(el.querySelector('#res'), r.repairs, j => location.hash = '#/repair/' + j.id);
  } else {
    el.querySelector('#res').innerHTML = itemCards(items);
    el.querySelectorAll('[data-item]').forEach(c => c.onclick = () => location.hash = '#/item/' + c.dataset.item);
  }
  el.querySelector('#edit').onclick = () => {
    const f = r.filters || {};
    const params = new URLSearchParams();
    if (f.metal) params.set('metal', f.metal);
    if (f.purity) params.set('purity', f.purity);
    if (f.min_price) params.set('min_price', f.min_price);
    if (f.max_price) params.set('max_price', f.max_price);
    if (f.min_wt) params.set('min_wt', f.min_wt);
    if (f.max_wt) params.set('max_wt', f.max_wt);
    if (f.families?.length === 1) params.set('family', f.families[0]);
    sessionStorage.setItem('inv-filters', params.toString());
    location.hash = '#/inventory';
  };
  if (r.answer && q.length < 120) speak(r.answer);
}

export function itemCards(items) {
  if (!items.length) return '<div class="empty">No matching items in stock.</div>';
  return `<div class="grid g3">${items.map(i => `<div class="item-card click" data-item="${i.id}" style="cursor:pointer">
    <div class="ic ${esc(i.family)}">${esc(i.purity_code || 'GIFT')}</div>
    <div style="min-width:0;flex:1"><div class="row"><b>${esc(i.name)}</b></div>
      <div class="small muted">${esc(i.tag_code)} · ${esc(i.category_name)}${i.net_wt > 0 ? ' · ' + fmt.wt(i.net_wt) : ''}${i.stone_carat > 0 ? ' · ' + fmt.num(i.stone_carat) + ' ct' : ''}</div></div>
    <div class="num"><b>${i.price != null ? fmt.rupees(i.price) : '—'}</b><div>${badge(i.status)}</div></div></div>`).join('')}</div>`;
}

// ---------- reports ----------

export async function reports(el) {
  const cat = await api('/reports');
  const groups = { Stock: ['stock_summary', 'stock_metal', 'stock_ageing', 'tag_stock', 'tally_history', 'huid_register'],
    Sales: ['sales_register', 'sales_items', 'sales_by_category', 'sales_by_salesperson', 'gst_summary'],
    Purchase: ['purchase_register', 'purchase_by_mode', 'purchase_by_class', 'old_metal'],
    'Ledgers & parties': ['outstanding'], Repairs: ['repairs_open', 'repairs_karigar'], Other: ['rate_history', 'backup_log'] };
  const hidden = { purchase_by_class: 'VIEW_PURCHASE_CLASS', outstanding: 'REPORTS_LEDGER', backup_log: 'BACKUP' };
  el.innerHTML = `<div class="pagehead"><div><h1>Reports</h1><p>Every report filters by date and exports to Excel (CSV) or print/PDF.</p></div></div>
    <div class="grid g3">${Object.entries(groups).map(([g, names]) => `<div class="card"><h3>${esc(g)}</h3><div class="list">
      ${names.filter(n => !hidden[n] || can(hidden[n])).map(n => `<a href="#/report/${n}">${esc(cat[n])}</a>`).join('')}</div></div>`).join('')}</div>`;
}

export async function report(el, name) {
  const from = sessionStorage.getItem('rep-from') || today().slice(0, 8) + '01';
  const to = sessionStorage.getItem('rep-to') || today();
  const r = await api(`/reports/${name}?from=${from}&to=${to}`);
  el.innerHTML = `<div class="pagehead"><div><h1>${esc(r.title)}</h1><p>${fmt.date(from)} – ${fmt.date(to)}</p></div>
    <div class="row noprint"><input type="date" id="from" value="${from}" style="width:auto"><input type="date" id="to" value="${to}" style="width:auto">
      <button id="go">Apply</button><a class="btn" href="${fileUrl(`/reports/${name}/csv?from=${from}&to=${to}`)}">Excel (CSV)</a>
      <button onclick="window.print()">Print / PDF</button></div></div>
    ${table(r.columns.map(c => ({ k: c.key, l: c.label, t: c.type === 'text' ? undefined : c.type })), r.rows,
      { foot: Object.keys(r.totals || {}).length ? r.totals : null })}`;
  el.querySelector('#go').onclick = () => {
    sessionStorage.setItem('rep-from', el.querySelector('#from').value);
    sessionStorage.setItem('rep-to', el.querySelector('#to').value);
    report(el, name);
  };
}

// ---------- ledgers ----------

export async function ledgers(el, book = 'CASH') {
  const balances = await api('/ledgers');
  const from = sessionStorage.getItem('led-from') || today().slice(0, 8) + '01';
  const to = sessionStorage.getItem('led-to') || today();
  const b = await api(`/ledgers/${book}?from=${from}&to=${to}`);
  const metal = ['GOLD', 'SILVER', 'PLATINUM'].includes(book);
  const t = metal ? 'wt' : 'money';
  el.innerHTML = `<div class="pagehead"><div><h1>Cash, bank & metal books</h1><p>Cash and bank in rupees; gold, silver and platinum in fine grams.</p></div>
    ${can('CONFIG') ? '<button id="opening">Opening balance</button>' : ''}</div>
    <div class="grid g4 stats">${Object.entries(balances).map(([k, v]) => `<a class="card stat" href="javascript:void 0" data-book="${k}"
      style="${k === book ? 'outline:2px solid var(--gold)' : ''}"><div class="k">${esc(fmt.label(k))}</div>
      <div class="v">${['GOLD', 'SILVER', 'PLATINUM'].includes(k) ? fmt.wt(v) : fmt.rupees(v)}</div></a>`).join('')}</div>
    <div class="card" style="margin-top:1rem"><div class="row"><h2>${esc(fmt.label(book))} book</h2><span class="spacer"></span>
      <input type="date" id="from" value="${from}" style="width:auto"><input type="date" id="to" value="${to}" style="width:auto"><button id="go">Apply</button></div>
      <p class="muted small">Opening ${metal ? fmt.wt(b.opening) : fmt.money(b.opening)} · In ${metal ? fmt.wt(b.total_debit) : fmt.money(b.total_debit)}
        · Out ${metal ? fmt.wt(b.total_credit) : fmt.money(b.total_credit)} · Closing <b>${metal ? fmt.wt(b.closing) : fmt.money(b.closing)}</b></p>
      ${table([{ k: 'business_date', l: 'Date', t: 'date' }, { k: 'doc_type', l: 'Document', t: 'badge' }, { k: 'narration', l: 'Details' },
        { k: 'party_name', l: 'Party' }, { k: 'debit', l: 'In', t }, { k: 'credit', l: 'Out', t }, { k: 'balance', l: 'Balance', t }], b.entries)}</div>`;
  el.querySelectorAll('[data-book]').forEach(a => a.onclick = () => ledgers(el, a.dataset.book));
  el.querySelector('#go').onclick = () => {
    sessionStorage.setItem('led-from', el.querySelector('#from').value);
    sessionStorage.setItem('led-to', el.querySelector('#to').value);
    ledgers(el, book);
  };
  el.querySelector('#opening')?.addEventListener('click', async () => {
    const v = await askDialog('Opening balance', [
      { name: 'book', label: 'Book', type: 'select', options: ['CASH', 'BANK', 'GOLD', 'SILVER', 'PLATINUM'], value: book },
      { name: 'amount', label: 'Amount (₹, or fine grams for metal)', type: 'number', required: true }]);
    if (!v) return;
    try { await api('/ledgers/opening', { method: 'POST', body: v }); toast('Opening balance posted.', 'ok'); ledgers(el, v.book); } catch (e) { fail(e); }
  });
}
