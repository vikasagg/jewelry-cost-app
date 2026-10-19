// Sales billing and invoices, purchases (cash / bank / against gold / against silver), customers and vendors.
import { state, api, can, esc, fmt, table, bindRows, toast, fail, badge, scanner, modal, ask, fieldHtml, formValues,
  loadMasters, qrSvg, listen, today, daysAgo, ICONS } from './core.js';

const PAY_MODES = ['CASH', 'UPI', 'CARD', 'BANK', 'CHEQUE'];

// ---------- customer / party picker ----------

export function partyPicker(el, type, onPick, { allowNew = true, label = 'Customer' } = {}) {
  el.innerHTML = `<label>${esc(label)}</label><div class="row" style="flex-wrap:nowrap"><input class="pp-in" placeholder="Name or phone" autocomplete="off">
    ${allowNew ? `<button type="button" class="pp-new" title="New">${ICONS.plus}</button>` : ''}</div><div class="pp-list list" style="margin-top:.4rem"></div>
    <div class="pp-sel"></div>`;
  const input = el.querySelector('.pp-in');
  const list = el.querySelector('.pp-list');
  const sel = el.querySelector('.pp-sel');
  const show = p => {
    sel.innerHTML = p ? `<div class="item-card"><div class="ic">${esc(p.name[0])}</div><div style="flex:1"><b>${esc(p.name)}</b>
      <div class="small muted">${esc(p.phone || '')} ${p.balance && +p.balance !== 0 ? '· balance ' + fmt.money(p.balance) : ''}</div></div>
      <button type="button" class="small ghost pp-clear">Change</button></div>` : '';
    sel.querySelector('.pp-clear')?.addEventListener('click', () => { onPick(null); show(null); input.parentElement.classList.remove('hidden'); input.focus(); });
    input.parentElement.classList.toggle('hidden', !!p);
    list.innerHTML = '';
  };
  input.addEventListener('input', () => {
    clearTimeout(input._t);
    input._t = setTimeout(async () => {
      const q = input.value.trim();
      if (!q) { list.innerHTML = ''; return; }
      const types = type.split(',');
      const rows = (await Promise.all(types.map(t => api(`/parties?type=${t}&q=${encodeURIComponent(q)}`)))).flat().slice(0, 8);
      list.innerHTML = rows.map((p, i) => `<button type="button" class="small" data-i="${i}" style="justify-content:flex-start">
        ${esc(p.name)} <span class="muted">${esc(p.phone || '')} · ${esc(fmt.label(p.party_type))}</span></button>`).join('')
        || '<span class="muted small">No match.</span>';
      list.querySelectorAll('[data-i]').forEach(b => b.onclick = () => { const p = rows[+b.dataset.i]; onPick(p); show(p); });
    }, 200);
  });
  el.querySelector('.pp-new')?.addEventListener('click', async () => {
    const v = await ask('New ' + label.toLowerCase(), partyFields({ party_type: type.split(',')[0], name: input.value }));
    if (!v) return;
    try {
      const p = await api('/parties', { method: 'POST', body: v });
      onPick(p); show(p);
    } catch (e) { fail(e); }
  });
  return { set: p => { onPick(p); show(p); } };
}

function partyFields(p = {}) {
  return [
    { name: 'party_type', label: 'Type', type: 'select', options: [['CUSTOMER', 'Customer'], ['VENDOR', 'Vendor'], ['KARIGAR', 'Karigar']], value: p.party_type },
    { name: 'name', label: 'Name', required: true, value: p.name },
    { name: 'phone', label: 'Mobile', type: 'tel', value: p.phone, inputmode: 'tel' },
    { name: 'address', label: 'Address', value: p.address },
    { name: 'gstin', label: 'GSTIN', value: p.gstin },
    { name: 'pan', label: 'PAN', value: p.pan },
    { name: 'id_proof', label: 'Aadhaar / ID (optional)', value: p.id_proof },
    { name: 'birthday', label: 'Birthday', type: 'date', value: p.birthday },
    { name: 'anniversary', label: 'Anniversary', type: 'date', value: p.anniversary },
    { name: 'email', label: 'Email', type: 'email', value: p.email },
  ];
}

// ---------- new bill ----------

export async function newSale(el) {
  const m = await loadMasters();
  const bill = { lines: [], exchange: [], payments: [{ mode: 'CASH', amount: '' }], customer: null, quote: null, notes: '' };
  const rateOk = state.rateToday?.approved || (await api('/rates/today')).approved;
  el.innerHTML = `
    <div class="pagehead"><div><h1>New bill</h1><p>Scan the QR tag (camera or scanner), type the tag, or find the item by voice.</p></div></div>
    ${rateOk ? '' : '<div class="alert bad">Today\'s rate is not approved yet. <a href="#/rates">Approve it first</a> — billing uses only the approved morning rate.</div>'}
    <div class="split">
      <div>
        <div class="card"><div id="scan"></div><div class="row" style="margin-top:.5rem">
          <button type="button" id="find">${ICONS.mic} Find item by voice / text</button><span class="muted small">Tip: a USB/Bluetooth scanner types the code and Enter.</span></div></div>
        <div class="card"><h3>Items</h3><div id="lines"></div></div>
        <div class="card"><div class="row"><h3>Old gold / silver exchange</h3><span class="spacer"></span><button type="button" class="small" id="addx">${ICONS.plus} Add exchange</button></div><div id="xlines"></div></div>
      </div>
      <div>
        <div class="card"><div id="cust"></div></div>
        <div class="card"><h3>Bill total</h3><div id="totals"><p class="muted">Add an item to see the price.</p></div></div>
        <div class="card"><div class="row"><h3>Payment</h3><span class="spacer"></span><button type="button" class="small" id="addp">${ICONS.plus} Split</button></div>
          <div id="pays"></div><div id="due" class="small" style="margin-top:.4rem"></div>
          <div class="field" style="margin-top:.5rem"><label>Notes</label><input id="notes" placeholder="Optional"></div>
          <button class="primary big" id="save" style="width:100%;justify-content:center" ${rateOk ? '' : 'disabled'}>Save bill</button></div>
      </div>
    </div>`;

  partyPicker(el.querySelector('#cust'), 'CUSTOMER', p => { bill.customer = p; });
  const addTag = async code => {
    if (bill.lines.some(l => l.tag_code?.toUpperCase() === code.toUpperCase())) return toast('Already on the bill.');
    try {
      const it = await api('/items/code/' + encodeURIComponent(code));
      if (it.status !== 'IN_STOCK') return toast(`${it.tag_code} is ${fmt.label(it.status).toLowerCase()}.`, 'bad');
      bill.lines.push({ item_id: it.id, tag_code: it.tag_code, discount: '' });
      refresh();
    } catch (e) { fail(e); }
  };
  scanner(el.querySelector('#scan'), addTag);
  el.querySelector('#find').onclick = () => findItem(addTag);

  const refresh = async () => {
    renderLines();
    if (!bill.lines.length) { bill.quote = null; renderTotals(); return; }
    try {
      bill.quote = await api('/sales/quote', { method: 'POST', body: body() });
    } catch (e) { fail(e); bill.quote = null; }
    renderLines();
    renderTotals();
  };
  const body = () => ({
    customer_id: bill.customer?.id, notes: el.querySelector('#notes').value,
    lines: bill.lines.map(l => ({ item_id: l.item_id, discount: l.discount || 0 })),
    exchange: bill.exchange.filter(x => +x.gross_wt > 0),
    payments: bill.payments.filter(p => +p.amount > 0),
  });
  const renderLines = () => {
    const q = bill.quote;
    const box = el.querySelector('#lines');
    if (!bill.lines.length) { box.innerHTML = '<div class="empty">No items yet — scan a tag.</div>'; return; }
    box.innerHTML = `<div class="tablewrap"><table class="resp"><thead><tr><th>Item</th><th class="num">Value</th><th class="num">Discount ₹</th>
      <th class="num">GST</th><th class="num">Total</th><th></th></tr></thead>
      <tbody>${bill.lines.map((l, i) => {
        const ql = q?.lines?.find(x => x.item_id === l.item_id) || {};
        const parts = ql.metal ? [`metal ${fmt.money(ql.metal_value)}`, `making ${fmt.money((+ql.making_value || 0) + (+ql.wastage_value || 0))}`]
          .concat(+ql.stone_value ? [`stones ${fmt.money(ql.stone_value)}`] : []) : [];
        return `<tr><td data-l="Item"><b>${esc(ql.description || l.tag_code)}</b><div class="small muted">${esc(l.tag_code)}${ql.huid ? ' · HUID ' + esc(ql.huid) : ''}
            ${ql.metal ? `<br>${fmt.num(ql.net_wt)} g × ${fmt.money(ql.rate)}/g` : ''}</div></td>
          <td class="num" data-l="Value">${fmt.money((+ql.taxable || 0) + (+ql.discount || 0))}<div class="small muted">${parts.join('<br>')}</div></td>
          <td class="num" data-l="Discount"><input data-disc="${i}" type="number" step="0.001" min="0" value="${esc(l.discount)}" style="width:110px;min-height:32px"></td>
          <td class="num" data-l="GST">${fmt.money(ql.gst)}</td><td class="num" data-l="Total"><b>${fmt.money(ql.line_total)}</b></td>
          <td><button class="small ghost danger" data-del="${i}" title="Remove">✕</button></td></tr>`;
      }).join('')}</tbody></table></div>`;
    box.querySelectorAll('[data-disc]').forEach(inp => inp.onchange = () => { bill.lines[+inp.dataset.disc].discount = inp.value; refresh(); });
    box.querySelectorAll('[data-del]').forEach(b => b.onclick = () => { bill.lines.splice(+b.dataset.del, 1); refresh(); });
  };
  const renderX = () => {
    const box = el.querySelector('#xlines');
    box.innerHTML = bill.exchange.length ? bill.exchange.map((x, i) => `<div class="fields" data-x="${i}" style="align-items:end;border-bottom:1px solid var(--line);padding-bottom:.5rem;margin-bottom:.5rem">
      ${fieldHtml({ name: 'description', label: 'Description', value: x.description })}
      ${fieldHtml({ name: 'metal', label: 'Metal', type: 'select', options: ['GOLD', 'SILVER'], value: x.metal })}
      ${fieldHtml({ name: 'purity_code', label: 'Tested purity', type: 'select', options: m.purities.filter(p => p.metal === x.metal).map(p => p.code), value: x.purity_code })}
      ${fieldHtml({ name: 'gross_wt', label: 'Gross g', type: 'number', value: x.gross_wt })}
      ${fieldHtml({ name: 'net_wt', label: 'Net g (after melt/stone)', type: 'number', value: x.net_wt })}
      ${fieldHtml({ name: 'deduction_pct', label: 'Deduction %', type: 'number', value: x.deduction_pct, placeholder: 'default' })}
      <div class="field"><button type="button" class="small danger" data-xdel="${i}">Remove</button></div></div>`).join('')
      : '<p class="muted small">Customer\'s old gold or silver is valued at today\'s rate for its tested purity, less the deduction, and adjusted against the bill.</p>';
    box.querySelectorAll('[data-x]').forEach(row => row.addEventListener('change', e => {
      const x = bill.exchange[+row.dataset.x];
      x[e.target.name] = e.target.value;
      if (e.target.name === 'metal') { x.purity_code = m.purities.find(p => p.metal === x.metal)?.code; renderX(); }
      refresh();
    }));
    box.querySelectorAll('[data-xdel]').forEach(b => b.onclick = () => { bill.exchange.splice(+b.dataset.xdel, 1); renderX(); refresh(); });
  };
  el.querySelector('#addx').onclick = () => { bill.exchange.push({ metal: 'GOLD', purity_code: '22K', description: 'Old gold' }); renderX(); };
  renderX();

  const renderPays = () => {
    const box = el.querySelector('#pays');
    box.innerHTML = bill.payments.map((p, i) => `<div class="row" style="flex-wrap:nowrap;margin-bottom:.4rem">
      <select data-pm="${i}" style="width:110px">${PAY_MODES.map(mo => `<option ${mo === p.mode ? 'selected' : ''}>${mo}</option>`).join('')}</select>
      <input data-pa="${i}" type="number" step="0.001" min="0" placeholder="Amount" value="${esc(p.amount)}" inputmode="decimal">
      ${p.mode !== 'CASH' ? `<input data-pr="${i}" placeholder="Ref / UTR" value="${esc(p.reference || '')}" style="width:120px">` : ''}
      ${bill.payments.length > 1 ? `<button type="button" class="small ghost" data-pdel="${i}">✕</button>` : ''}</div>`).join('');
    box.querySelectorAll('[data-pm]').forEach(s => s.onchange = () => { bill.payments[+s.dataset.pm].mode = s.value; renderPays(); });
    box.querySelectorAll('[data-pa]').forEach(s => s.oninput = () => { bill.payments[+s.dataset.pa].amount = s.value; renderDue(); });
    box.querySelectorAll('[data-pr]').forEach(s => s.oninput = () => { bill.payments[+s.dataset.pr].reference = s.value; });
    box.querySelectorAll('[data-pdel]').forEach(b => b.onclick = () => { bill.payments.splice(+b.dataset.pdel, 1); renderPays(); renderDue(); });
    renderDue();
  };
  const renderDue = () => {
    const net = +(bill.quote?.net_payable || 0);
    const paid = bill.payments.reduce((s, p) => s + (+p.amount || 0), 0);
    const due = net - paid;
    el.querySelector('#due').innerHTML = !net ? '' : Math.abs(due) < 0.0005 ? '<span class="badge ok">Fully paid</span>'
      : due > 0 ? `Balance due <b>${fmt.money(due)}</b> ${bill.customer ? '(goes to the customer\'s account)' : '— choose a customer for credit'}`
        : `<span style="color:var(--bad)">Paid ${fmt.money(-due)} more than the bill</span>`;
  };
  el.querySelector('#addp').onclick = () => {
    const net = +(bill.quote?.net_payable || 0);
    const paid = bill.payments.reduce((s, p) => s + (+p.amount || 0), 0);
    bill.payments.push({ mode: 'UPI', amount: net > paid ? (net - paid).toFixed(3) : '' });
    renderPays();
  };
  const renderTotals = () => {
    const q = bill.quote;
    const box = el.querySelector('#totals');
    if (!q) { box.innerHTML = '<p class="muted">Add an item to see the price.</p>'; renderDue(); return; }
    box.innerHTML = `<div class="totals">
      <span>Taxable value</span><span class="num">${fmt.money(q.taxable_total)}</span>
      ${+q.discount ? `<span>Discount given</span><span class="num">−${fmt.money(q.discount)}</span>` : ''}
      <span>GST (CGST + SGST)</span><span class="num">${fmt.money(q.gst_total)}</span>
      <span>Items total</span><span class="num">${fmt.money(q.items_total)}</span>
      ${+q.exchange_total ? `<span>Less old gold/silver</span><span class="num">−${fmt.money(q.exchange_total)}</span>` : ''}
      ${+q.round_off ? `<span>Round off</span><span class="num">${fmt.money(q.round_off)}</span>` : ''}
      <span class="grand">Net payable</span><span class="grand num">${fmt.money(q.net_payable)}</span></div>
      <button type="button" class="small" id="fill" style="margin-top:.5rem">Fill payment with full amount</button>`;
    box.querySelector('#fill').onclick = () => {
      const others = bill.payments.slice(1).reduce((s, p) => s + (+p.amount || 0), 0);
      bill.payments[0].amount = Math.max(0, q.net_payable - others).toFixed(3);
      renderPays();
    };
    renderDue();
  };
  renderPays();
  renderLines();

  el.querySelector('#save').onclick = async e => {
    if (!bill.lines.length) return toast('Add at least one item.', 'bad');
    e.target.disabled = true;
    try {
      const s = await api('/sales', { method: 'POST', body: body() });
      (s.warnings || []).forEach(w => toast(w));
      toast('Bill ' + s.invoice_no + ' saved.', 'ok');
      location.hash = '#/sale/' + s.id;
    } catch (err) { fail(err); e.target.disabled = false; }
  };
}

/** Voice or text search that returns one tag to the caller. */
function findItem(onPick) {
  const m = modal(`<h2>Find item</h2><form id="ff" class="row" style="flex-wrap:nowrap"><input id="fq" placeholder='e.g. "22 carat jhumka" or "diamond ring below 60000"'>
    <button type="button" class="mic" id="fmic">${ICONS.mic}</button><button class="primary">Search</button></form>
    <div id="fres" style="margin-top:1rem"></div><div class="row end"><button data-close>Close</button></div>`, { wide: true });
  const run = async q => {
    const r = await api('/search/ask', { method: 'POST', body: { text: q } });
    const res = m.el.querySelector('#fres');
    res.innerHTML = `<div class="chips" style="margin-bottom:.5rem">${(r.chips || []).map(c => `<span class="chip">${esc(c)}</span>`).join('')}</div>` +
      table([{ k: 'tag_code', l: 'Tag' }, { k: 'name', l: 'Item' }, { k: 'purity_code', l: 'Purity' }, { k: 'net_wt', l: 'Net g', t: 'wt' },
        { k: 'price', l: 'Price', t: 'money' }], r.results || [], { click: true, empty: 'Nothing found.' });
    bindRows(res, r.results || [], it => { onPick(it.tag_code); m.close(); });
  };
  m.el.querySelector('#ff').onsubmit = e => { e.preventDefault(); run(m.el.querySelector('#fq').value).catch(fail); };
  m.el.querySelector('#fmic').onclick = async () => {
    try {
      const t = await listen(state.masters?.voiceLang);
      if (t) { m.el.querySelector('#fq').value = t; run(t); }
    } catch (e) { fail(e); }
  };
}

// ---------- sales list & invoice ----------

export async function sales(el) {
  const from = sessionStorage.getItem('sales-from') || daysAgo(30);
  const to = today();
  const rows = await api(`/sales?from=${from}&to=${to}`);
  el.innerHTML = `<div class="pagehead"><div><h1>Sales</h1><p>${rows.length} bill(s) since ${fmt.date(from)}</p></div>
    <div class="row"><input id="q" placeholder="Invoice, name or phone" style="width:220px">${can('BILL') ? '<a class="btn primary" href="#/sale/new">New bill</a>' : ''}</div></div><div id="t"></div>`;
  const draw = list => {
    el.querySelector('#t').innerHTML = table([{ k: 'invoice_no', l: 'Invoice' }, { k: 'business_date', l: 'Date', t: 'date' },
      { k: 'customer_name', l: 'Customer' }, { k: 'item_count', l: 'Items', t: 'int' }, { k: 'exchange_total', l: 'Exchange', t: 'money' },
      { k: 'net_payable', l: 'Net', t: 'money' }, { k: 'balance_due', l: 'Due', t: 'money' }, { k: 'status', l: 'Status', t: 'badge' }], list, { click: true });
    bindRows(el.querySelector('#t'), list, r => location.hash = '#/sale/' + r.id);
  };
  draw(rows);
  el.querySelector('#q').oninput = e => {
    const q = e.target.value.toLowerCase();
    draw(rows.filter(r => `${r.invoice_no} ${r.customer_name || ''}`.toLowerCase().includes(q)));
  };
}

export async function invoice(el, id) {
  const s = await api('/sales/' + id);
  const shop = s.shop;
  const cgst = +s.gst_total / 2;
  el.innerHTML = `<div class="row noprint" style="margin-bottom:1rem"><a href="#/sales" class="btn">← Sales</a><span class="spacer"></span>
      <button id="share">${ICONS.share} Share (WhatsApp)</button><button class="primary" onclick="window.print()">${ICONS.print} Print / PDF</button>
      ${can('SALE_RETURN') && s.status === 'FINAL' ? '<button class="danger" id="ret">Return bill</button>' : ''}</div>
    <div class="doc">
      <div class="head"><div><h1>${esc(shop.name)}</h1><div class="small">${esc(shop.address)}<br>${esc(shop.phone)}${shop.gstin ? ' · GSTIN ' + esc(shop.gstin) : ''}</div></div>
        <div style="text-align:right"><b>TAX INVOICE</b><div>${esc(s.invoice_no)}</div><div class="small">${fmt.date(s.business_date)} ${badge(s.status)}</div></div></div>
      <div class="row" style="justify-content:space-between;align-items:flex-start;margin-bottom:.8rem"><div class="small"><b>Bill to:</b> ${esc(s.customer_name || 'Walk-in customer')}<br>
        ${esc(s.customer_phone || '')} ${esc(s.customer_address || '')}${s.customer_gstin ? '<br>GSTIN ' + esc(s.customer_gstin) : ''}${s.customer_pan ? '<br>PAN ' + esc(s.customer_pan) : ''}</div>
        <div style="width:70px">${qrSvg(s.invoice_no, 2)}</div></div>
      <table class="small"><thead><tr><th>#</th><th style="min-width:190px">Item (HSN 7113)</th><th class="num">Net g</th><th class="num">Rate/g</th><th class="num">Metal</th>
        <th class="num">Making</th><th class="num">Stones</th>${s.lines.some(l => +l.discount) ? '<th class="num">Disc.</th>' : ''}<th class="num">Taxable</th></tr></thead><tbody>
        ${s.lines.map((l, i) => `<tr><td>${i + 1}</td><td>${esc(l.description)}<div class="muted">${esc(l.tag_code)} · gross ${fmt.num(l.gross_wt)} g${l.huid ? ' · HUID ' + esc(l.huid) : ''}</div></td>
          <td class="num">${fmt.num(l.net_wt)}</td><td class="num">${fmt.money(l.rate)}</td><td class="num">${fmt.money(l.metal_value)}</td>
          <td class="num">${fmt.money(+l.making_value + +l.wastage_value)}</td><td class="num">${fmt.money(l.stone_value)}</td>
          ${s.lines.some(x => +x.discount) ? `<td class="num">${fmt.money(l.discount)}</td>` : ''}<td class="num">${fmt.money(l.taxable)}</td></tr>`).join('')}</tbody></table>
      ${s.exchange.length ? `<h3 style="margin-top:1rem">Old gold / silver received</h3><table><thead><tr><th>Description</th><th>Purity</th><th class="num">Gross g</th>
        <th class="num">Net g</th><th class="num">Rate/g</th><th class="num">Deduction</th><th class="num">Value</th></tr></thead><tbody>
        ${s.exchange.map(x => `<tr><td>${esc(x.description)}</td><td>${esc(x.metal)} ${esc(x.purity_code)}</td><td class="num">${fmt.num(x.gross_wt)}</td><td class="num">${fmt.num(x.net_wt)}</td>
          <td class="num">${fmt.money(x.rate)}</td><td class="num">${fmt.num(x.deduction_pct)}%</td><td class="num">${fmt.money(x.exchange_value)}</td></tr>`).join('')}</tbody></table>` : ''}
      <div class="row" style="justify-content:space-between;align-items:flex-start;margin-top:1rem">
        <div class="small" style="max-width:55%">Payments: ${s.payments.filter(p => p.doc_type === 'SALE').map(p => `${esc(p.mode)} ${fmt.money(p.amount)}${p.reference ? ' (' + esc(p.reference) + ')' : ''}`).join(', ') || '—'}
          <br>Rate used: 24K ${fmt.money(s.rate_set.gold_24k)}/g, approved ${fmt.dt(s.rate_set.approved_at)}.
          <br>Prices include making and stone values as shown. Goods once sold are subject to the shop's exchange policy.</div>
        <div class="totals" style="min-width:280px"><span>Taxable value</span><span class="num">${fmt.money(s.taxable_total)}</span>
          <span>CGST</span><span class="num">${fmt.money(cgst)}</span><span>SGST</span><span class="num">${fmt.money(cgst)}</span>
          <span>Items total</span><span class="num">${fmt.money(s.items_total)}</span>
          ${+s.exchange_total ? `<span>Less exchange</span><span class="num">−${fmt.money(s.exchange_total)}</span>` : ''}
          ${+s.round_off ? `<span>Round off</span><span class="num">${fmt.money(s.round_off)}</span>` : ''}
          <span class="grand">Net payable</span><span class="grand num">${fmt.money(s.net_payable)}</span>
          <span>Paid</span><span class="num">${fmt.money(s.paid_total)}</span><span>Balance due</span><span class="num">${fmt.money(s.balance_due)}</span></div></div>
      <p class="small muted" style="margin-top:1.5rem">${esc(s.notes || '')}</p>
      <div class="row" style="justify-content:space-between;margin-top:2rem" class="small"><span>Customer signature</span><span>For ${esc(shop.name)}</span></div>
    </div>`;
  el.querySelector('#share').onclick = async () => {
    const text = `${shop.name}\nInvoice ${s.invoice_no} dated ${fmt.date(s.business_date)}\n` +
      s.lines.map(l => `• ${l.description} (${l.tag_code}) ${fmt.num(l.net_wt)} g – ${fmt.money(l.line_total)}`).join('\n') +
      (+s.exchange_total ? `\nLess exchange ${fmt.money(s.exchange_total)}` : '') + `\nNet payable ${fmt.money(s.net_payable)}\nThank you!`;
    if (navigator.share) { try { await navigator.share({ title: s.invoice_no, text }); return; } catch { /* cancelled */ } }
    const phone = (s.customer_phone || '').replace(/\D/g, '');
    window.open(`https://wa.me/${phone ? (phone.length === 10 ? '91' + phone : phone) : ''}?text=${encodeURIComponent(text)}`, '_blank');
  };
  el.querySelector('#ret')?.addEventListener('click', async () => {
    const v = await ask('Return this bill', [{ name: 'reason', label: 'Reason', required: true },
      { name: 'refund_mode', label: 'Refund by', type: 'select', options: PAY_MODES, value: 'CASH' }],
    { okText: 'Return bill', note: 'All items go back to stock and the amount paid plus any exchange value is refunded.' });
    if (!v) return;
    try { await api(`/sales/${id}/return`, { method: 'POST', body: v }); toast('Bill returned.', 'ok'); invoice(el, id); } catch (e) { fail(e); }
  });
}

// ---------- purchases ----------

export async function newPurchase(el) {
  const m = await loadMasters();
  const rt = state.rateToday || await api('/rates/today');
  const rateOf = (metal, purity) => +(rt.approved?.lines.find(l => l.metal === metal && l.purity_code === purity)?.rate_per_gram || 0);
  const p = { party: null, kind: 'FINISHED', lines: [], pay: {} };
  el.innerHTML = `
    <div class="pagehead"><div><h1>New purchase</h1><p>Finished jewellery and gifting get a QR tag each; old metal goes into the gold/silver book in fine weight.</p></div></div>
    <div class="split"><div>
      <div class="card"><div class="fields">
        <div class="field"><label>Purchase type</label><select id="kind"><option value="FINISHED">Finished jewellery (from vendor)</option>
          <option value="GIFTING">Gifting products</option><option value="OLD_METAL">Old gold / silver ("treat" purchase)</option></select></div>
        <div class="field"><label>GST invoice no.</label><input id="gstinv" placeholder="Blank = no GST invoice"></div>
        <div class="field"><label>GST %</label><input id="gstpct" type="number" step="0.001" value="3"></div></div>
        <div id="party"></div></div>
      <div class="card"><div class="row"><h3>Lines</h3><span class="spacer"></span><button type="button" class="small" id="addl">${ICONS.plus} Add line</button></div><div id="lines"></div></div>
    </div><div>
      <div class="card"><h3>Payment</h3><p class="small muted">Use one leg or several (mixed). Anything left unpaid stays on the party's account.</p>
        <div class="fields">
          ${fieldHtml({ name: 'cash', label: 'Cash ₹', type: 'number' })}
          ${fieldHtml({ name: 'bank', label: 'Bank / UPI / cheque ₹', type: 'number' })}
          ${fieldHtml({ name: 'bank_mode', label: 'Bank mode', type: 'select', options: ['BANK', 'UPI', 'CHEQUE'] })}
          ${fieldHtml({ name: 'bank_ref', label: 'Bank reference' })}
          ${fieldHtml({ name: 'gold_fine', label: 'Against gold — fine g', type: 'number', hint: 'Valued at today\'s 24K rate' })}
          ${fieldHtml({ name: 'silver_fine', label: 'Against silver — fine g', type: 'number', hint: 'Valued at today\'s 999 rate' })}
        </div>
        <div id="ptotal"></div>
        <div class="field"><label>Notes</label><input id="notes"></div>
        <button class="primary big" id="save" style="width:100%;justify-content:center">Save purchase</button></div>
    </div></div>`;
  const pickerLabel = () => p.kind === 'OLD_METAL' ? 'Seller (customer)' : 'Vendor';
  const picker = () => partyPicker(el.querySelector('#party'), p.kind === 'OLD_METAL' ? 'CUSTOMER,VENDOR' : 'VENDOR', x => { p.party = x; }, { label: pickerLabel() });
  picker();
  const blank = () => p.kind === 'OLD_METAL' ? { metal: 'GOLD', purity_code: '22K', description: 'Old gold' }
    : p.kind === 'GIFTING' ? { category_id: m.categories.find(c => c.family === 'GIFTING')?.id, quantity: 1 }
      : { category_id: m.categories.find(c => c.family === 'GOLD')?.id, purity_code: '22K' };
  el.querySelector('#kind').onchange = e => { p.kind = e.target.value; p.lines = [blank()]; picker(); draw(); };
  el.querySelector('#addl').onclick = () => { p.lines.push({ ...(p.lines.at(-1) || blank()), name: '', gross_wt: '', stone_wt: '', net_wt: '', cost_amount: '', huid: '', carat: '' }); draw(); };
  const cats = fam => m.categories.filter(c => fam === 'GIFTING' ? c.family === 'GIFTING' : c.family !== 'GIFTING');
  const lineValue = l => {
    if (p.kind !== 'OLD_METAL') return +l.cost_amount || 0;
    const net = +(l.net_wt || l.gross_wt) || 0;
    const ded = l.deduction_pct === undefined || l.deduction_pct === '' ? 3 : +l.deduction_pct;
    return net * rateOf(l.metal, l.purity_code) * (1 - ded / 100);
  };
  const draw = () => {
    const box = el.querySelector('#lines');
    box.innerHTML = p.lines.map((l, i) => {
      let f;
      if (p.kind === 'OLD_METAL') {
        f = [{ name: 'description', label: 'Description', value: l.description },
          { name: 'metal', label: 'Metal', type: 'select', options: ['GOLD', 'SILVER'], value: l.metal },
          { name: 'purity_code', label: 'Tested purity', type: 'select', options: m.purities.filter(x => x.metal === l.metal).map(x => x.code), value: l.purity_code },
          { name: 'gross_wt', label: 'Gross g', type: 'number', value: l.gross_wt },
          { name: 'net_wt', label: 'Net g (after melt)', type: 'number', value: l.net_wt },
          { name: 'deduction_pct', label: 'Deduction %', type: 'number', value: l.deduction_pct, placeholder: 'default 3' }];
      } else if (p.kind === 'GIFTING') {
        f = [{ name: 'category_id', label: 'Category', type: 'select', options: cats('GIFTING').map(c => [c.id, c.name]), value: l.category_id },
          { name: 'name', label: 'Item name', value: l.name }, { name: 'fixed_price', label: 'MRP / selling price ₹', type: 'number', value: l.fixed_price },
          { name: 'quantity', label: 'Quantity', type: 'number', step: 1, value: l.quantity }, { name: 'cost_amount', label: 'Purchase value ₹ (line)', type: 'number', value: l.cost_amount }];
      } else {
        const c = m.categories.find(x => String(x.id) === String(l.category_id));
        f = [{ name: 'category_id', label: 'Category', type: 'select', options: cats().map(x => [x.id, x.name]), value: l.category_id },
          { name: 'name', label: 'Item name', value: l.name, placeholder: c?.name },
          { name: 'purity_code', label: 'Purity', type: 'select', options: m.purities.filter(x => x.metal === c?.metal).map(x => x.code), value: l.purity_code },
          { name: 'gross_wt', label: 'Gross g', type: 'number', value: l.gross_wt },
          { name: 'stone_wt', label: 'Stone g', type: 'number', value: l.stone_wt, placeholder: c?.family === 'DIAMOND' ? 'auto from ct' : '0' },
          { name: 'net_wt', label: 'Net g', type: 'number', value: l.net_wt, placeholder: 'gross − stone' },
          ...(c?.family === 'DIAMOND' ? [{ name: 'carat', label: 'Diamond ct', type: 'number', value: l.carat },
            { name: 'rate_per_carat', label: '₹ per ct', type: 'number', value: l.rate_per_carat }] : []),
          { name: 'huid', label: 'HUID', value: l.huid }, { name: 'cost_amount', label: 'Purchase value ₹', type: 'number', value: l.cost_amount }];
      }
      return `<div class="fields" data-l="${i}" style="border-bottom:1px solid var(--line);margin-bottom:.6rem;padding-bottom:.3rem">${f.map(fieldHtml).join('')}
        <div class="field"><label>&nbsp;</label><div class="row"><span class="small muted lv"></span>
        ${p.lines.length > 1 ? `<button type="button" class="small danger" data-del="${i}">Remove</button>` : ''}</div></div></div>`;
    }).join('');
    box.querySelectorAll('[data-l]').forEach(row => row.addEventListener('input', e => {
      p.lines[+row.dataset.l][e.target.name] = e.target.value;
      total();
    }));
    box.querySelectorAll('[data-l]').forEach(row => row.addEventListener('change', e => {
      const l = p.lines[+row.dataset.l];
      l[e.target.name] = e.target.value;
      if (e.target.name === 'category_id' || e.target.name === 'metal') {
        const c = m.categories.find(x => String(x.id) === String(l.category_id));
        const metal = p.kind === 'OLD_METAL' ? l.metal : c?.metal;
        l.purity_code = m.purities.find(x => x.metal === metal)?.code;
        draw();
      }
      total();
    }));
    box.querySelectorAll('[data-del]').forEach(b => b.onclick = () => { p.lines.splice(+b.dataset.del, 1); draw(); });
    total();
  };
  const total = () => {
    if (p.kind === 'OLD_METAL') el.querySelectorAll('#lines [data-l]').forEach(row => {
      row.querySelector('.lv').textContent = 'Value ≈ ' + fmt.money(lineValue(p.lines[+row.dataset.l]));
    });
    const sub = p.lines.reduce((s, l) => s + lineValue(l), 0);
    const gst = el.querySelector('#gstinv').value.trim() ? sub * (+el.querySelector('#gstpct').value || 0) / 100 : 0;
    const cash = +el.querySelector('[name=cash]').value || 0;
    const seen = el.querySelector('#gstinv').value.trim() && cash === 0;
    el.querySelector('#ptotal').innerHTML = `<div class="totals" style="margin:.5rem 0"><span>Value</span><span class="num">${fmt.money(sub)}</span>
      <span>GST</span><span class="num">${fmt.money(gst)}</span><span class="grand">Total</span><span class="grand num">${fmt.money(sub + gst)}</span></div>
      ${can('VIEW_PURCHASE_CLASS') ? `<p class="small">Will be recorded as ${badge(seen ? 'SEEN' : 'UNSEEN')} — ${seen ? 'GST invoice and no cash' : 'no GST invoice or paid in cash'}.</p>` : ''}`;
  };
  el.querySelectorAll('#gstinv,#gstpct,[name=cash]').forEach(i => i.addEventListener('input', total));
  p.lines = [blank()];
  draw();

  el.querySelector('#save').onclick = async e => {
    if (!p.party) return toast('Choose the ' + pickerLabel().toLowerCase() + '.', 'bad');
    const lines = p.lines.map(l => {
      const out = { ...l };
      if (l.carat) out.stones = [{ stone_type: 'DIAMOND', carat: l.carat, rate_per_carat: l.rate_per_carat || 0 }];
      if (l.carat && !l.stone_wt) out.stone_wt = '';
      return out;
    });
    const pay = {};
    ['cash', 'bank', 'bank_mode', 'bank_ref', 'gold_fine', 'silver_fine'].forEach(k => pay[k] = el.querySelector(`[name=${k}]`).value);
    e.target.disabled = true;
    try {
      const r = await api('/purchases', { method: 'POST', body: { party_id: p.party.id, purchase_kind: p.kind,
        gst_invoice_no: el.querySelector('#gstinv').value, gst_pct: el.querySelector('#gstpct').value, lines, payment: pay,
        notes: el.querySelector('#notes').value } });
      (r.warnings || []).forEach(w => toast(w));
      toast('Purchase ' + r.purchase_no + ' saved.', 'ok');
      location.hash = '#/purchase/' + r.id;
    } catch (err) { fail(err); e.target.disabled = false; }
  };
}

export async function purchases(el) {
  const cls = sessionStorage.getItem('pur-class') || 'ALL';
  const from = daysAgo(60);
  const rows = await api(`/purchases?class=${cls}&from=${from}`);
  const showClass = can('VIEW_PURCHASE_CLASS');
  el.innerHTML = `<div class="pagehead"><div><h1>Purchases</h1><p>Last 60 days · cash, bank, against gold, against silver, mixed or credit</p></div>
    <div class="row">${showClass ? `<div class="seg" title="Seen = GST invoice paid by bank/cheque; Unseen = no GST, normally cash">
      ${['ALL', 'SEEN', 'UNSEEN'].map(c => `<button class="${c === cls ? 'on' : ''}" data-c="${c}">${c === 'ALL' ? 'All' : fmt.label(c)}</button>`).join('')}</div>` : ''}
      ${can('PURCHASE') ? '<a class="btn primary" href="#/purchase/new">New purchase</a>' : ''}</div></div>
    ${showClass ? '<p class="small muted">The Seen / Unseen view is a filter for internal reporting. Stock, billing, tally and every statutory export always include all purchases.</p>' : ''}
    <div id="t"></div>`;
  const cols = [{ k: 'purchase_no', l: 'No' }, { k: 'business_date', l: 'Date', t: 'date' }, { k: 'party_name', l: 'Party' },
    { k: 'purchase_kind', l: 'Type', t: 'badge' }, { k: 'payment_mode', l: 'Mode', t: 'badge' }];
  if (showClass) cols.push({ k: 'purchase_class', l: 'Class', t: 'badge' });
  cols.push({ k: 'total_amount', l: 'Total', t: 'money' }, { k: 'balance_due', l: 'Due', t: 'money' });
  el.querySelector('#t').innerHTML = table(cols, rows, { click: true });
  bindRows(el.querySelector('#t'), rows, r => location.hash = '#/purchase/' + r.id);
  el.querySelectorAll('[data-c]').forEach(b => b.onclick = () => { sessionStorage.setItem('pur-class', b.dataset.c); purchases(el); });
}

export async function purchase(el, id) {
  const p = await api('/purchases/' + id);
  const itemIds = p.lines.filter(l => l.item_id).map(l => l.item_id);
  el.innerHTML = `<div class="pagehead"><div><h1>Purchase ${esc(p.purchase_no)}</h1><p>${fmt.date(p.business_date)} · ${esc(p.party_name || '')} ${badge(p.purchase_kind)} ${badge(p.payment_mode)} ${p.purchase_class ? badge(p.purchase_class) : ''}</p></div>
    <div class="row"><a class="btn" href="#/purchases">← Purchases</a>${itemIds.length ? `<a class="btn primary" href="#/labels/${itemIds.join(',')}">${ICONS.print} Print QR labels</a>` : ''}
    ${can('CHANGE_PURCHASE_CLASS') ? '<button id="cls">Change class</button>' : ''}</div></div>
    <div class="split"><div class="card"><h3>Lines</h3>${table([{ k: 'tag_code', l: 'Tag', f: l => l.item_id ? `<a href="#/item/${l.item_id}">${esc(l.tag_code)}</a>` : '—' },
      { k: 'description', l: 'Description' }, { k: 'purity_code', l: 'Purity' }, { k: 'gross_wt', l: 'Gross g', t: 'wt' }, { k: 'net_wt', l: 'Net g', t: 'wt' },
      { k: 'fine_wt', l: 'Fine g', t: 'wt' }, { k: 'rate', l: 'Rate', t: 'money' }, { k: 'amount', l: 'Value', t: 'money' }], p.lines)}</div>
    <div class="card"><h3>Settlement</h3><dl class="kv"><dt>GST invoice</dt><dd>${esc(p.gst_invoice_no || '—')}</dd>
      <dt>Value</dt><dd class="num">${fmt.money(p.taxable_amount)}</dd><dt>GST</dt><dd class="num">${fmt.money(p.gst_amount)}</dd>
      <dt>Total</dt><dd class="num">${fmt.money(p.total_amount)}</dd><dt>Cash paid</dt><dd class="num">${fmt.money(p.cash_paid)}</dd>
      <dt>Bank paid</dt><dd class="num">${fmt.money(p.bank_paid)} ${esc(p.bank_ref || '')}</dd>
      <dt>Fine gold given</dt><dd class="num">${fmt.wt(p.gold_fine_paid)}</dd><dt>Fine silver given</dt><dd class="num">${fmt.wt(p.silver_fine_paid)}</dd>
      <dt>Metal value</dt><dd class="num">${fmt.money(p.metal_value_paid)}</dd><dt>Balance due</dt><dd class="num">${fmt.money(p.balance_due)}</dd>
      <dt>Entered by</dt><dd>${esc(p.created_by)}</dd></dl>${p.notes ? `<p class="small">${esc(p.notes)}</p>` : ''}</div></div>`;
  el.querySelector('#cls')?.addEventListener('click', async () => {
    const v = await ask('Change Seen / Unseen class', [{ name: 'purchase_class', label: 'Class', type: 'select', options: ['SEEN', 'UNSEEN'], value: p.purchase_class },
      { name: 'reason', label: 'Reason (logged)', required: true }]);
    if (!v) return;
    try { await api(`/purchases/${id}/class`, { method: 'PUT', body: v }); toast('Class changed and logged.', 'ok'); purchase(el, id); } catch (e) { fail(e); }
  });
}

// ---------- customers, vendors, karigars ----------

export async function parties(el, type) {
  const tabs = type === 'CUSTOMER' ? ['CUSTOMER'] : ['VENDOR', 'KARIGAR'];
  const cur = sessionStorage.getItem('party-tab-' + type) || tabs[0];
  const rows = await api('/parties?type=' + cur);
  el.innerHTML = `<div class="pagehead"><div><h1>${type === 'CUSTOMER' ? 'Customers' : 'Vendors & karigars'}</h1></div>
    <div class="row"><input id="q" placeholder="Name or phone" style="width:220px"><button class="primary" id="new">${ICONS.plus} New</button></div></div>
    ${tabs.length > 1 ? `<div class="tabs">${tabs.map(t => `<button class="${t === cur ? 'on' : ''}" data-t="${t}">${fmt.label(t)}s</button>`).join('')}</div>` : ''}
    <div id="t"></div>`;
  const draw = list => {
    el.querySelector('#t').innerHTML = table([{ k: 'name', l: 'Name' }, { k: 'phone', l: 'Phone' }, { k: 'gstin', l: 'GSTIN' },
      { k: 'address', l: 'Address' }, { k: 'balance', l: 'Balance', f: r => balanceText(r.balance) }], list, { click: true });
    bindRows(el.querySelector('#t'), list, r => location.hash = '#/party/' + r.id);
  };
  draw(rows);
  el.querySelector('#q').oninput = e => { const q = e.target.value.toLowerCase(); draw(rows.filter(r => `${r.name} ${r.phone || ''}`.toLowerCase().includes(q))); };
  el.querySelectorAll('[data-t]').forEach(b => b.onclick = () => { sessionStorage.setItem('party-tab-' + type, b.dataset.t); parties(el, type); });
  el.querySelector('#new').onclick = async () => {
    const v = await ask('New ' + fmt.label(cur).toLowerCase(), partyFields({ party_type: cur }));
    if (!v) return;
    try { const p = await api('/parties', { method: 'POST', body: v }); location.hash = '#/party/' + p.id; } catch (e) { fail(e); }
  };
}

function balanceText(b) {
  const v = +b || 0;
  if (Math.abs(v) < 0.0005) return '<span class="muted">Settled</span>';
  return v > 0 ? `<span style="color:var(--bad)">${fmt.money(v)} to receive</span>` : `<span style="color:var(--ok)">${fmt.money(-v)} to pay</span>`;
}

export async function party(el, id) {
  const p = await api('/parties/' + id);
  el.innerHTML = `<div class="pagehead"><div><h1>${esc(p.name)}</h1><p>${badge(p.party_type)} ${esc(p.phone || '')} · ${balanceText(p.balance)}</p></div>
    <div class="row"><button id="edit">Edit</button>${can('PAYMENT') ? '<button id="settle">Receive / pay money</button>' : ''}
    ${p.party_type === 'CUSTOMER' && can('BILL') ? '<a class="btn primary" href="#/sale/new">New bill</a>' : ''}</div></div>
    <div class="split"><div>
      <div class="tabs" id="tabs"></div><div id="tab"></div></div>
      <div class="card"><h3>Details</h3><dl class="kv"><dt>Address</dt><dd>${esc(p.address || '—')}</dd><dt>GSTIN</dt><dd>${esc(p.gstin || '—')}</dd>
        <dt>PAN</dt><dd>${esc(p.pan || '—')}</dd><dt>ID proof</dt><dd>${esc(p.id_proof || '—')}</dd><dt>Birthday</dt><dd>${fmt.date(p.birthday)}</dd>
        <dt>Anniversary</dt><dd>${fmt.date(p.anniversary)}</dd><dt>Since</dt><dd>${fmt.date(p.created_at)}</dd></dl></div></div>`;
  const tabs = {
    'Items bought': () => table([{ k: 'invoice_no', l: 'Invoice' }, { k: 'business_date', l: 'Date', t: 'date' }, { k: 'tag_code', l: 'Tag' },
      { k: 'description', l: 'Item' }, { k: 'net_wt', l: 'Net g', t: 'wt' }, { k: 'rate', l: 'Rate', t: 'money' }, { k: 'line_total', l: 'Amount', t: 'money' },
      { k: 'status', l: 'Bill', t: 'badge' }], p.items_bought, { empty: 'No purchases from the shop yet.' }),
    'Exchanged / sold to us': () => table([{ k: 'invoice_no', l: 'Invoice' }, { k: 'business_date', l: 'Date', t: 'date' }, { k: 'description', l: 'Item' },
      { k: 'purity_code', l: 'Purity' }, { k: 'net_wt', l: 'Net g', t: 'wt' }, { k: 'exchange_value', l: 'Value', t: 'money' }], p.exchanges, { empty: 'No exchanges.' })
      + '<h3 style="margin-top:1rem">Purchases from this party</h3>' + table([{ k: 'purchase_no', l: 'No' }, { k: 'business_date', l: 'Date', t: 'date' },
      { k: 'purchase_kind', l: 'Type', t: 'badge' }, { k: 'payment_mode', l: 'Mode', t: 'badge' }, { k: 'total_amount', l: 'Total', t: 'money' }], p.purchases, { empty: 'None.' }),
    Repairs: () => table([{ k: 'job_no', l: 'Job' }, { k: 'description', l: 'Item' }, { k: 'status', l: 'Status', t: 'badge' },
      { k: 'weight_in', l: 'Weight in', t: 'wt' }, { k: 'charges', l: 'Charges', t: 'money' }], p.repairs, { empty: 'No repairs.' }),
    Account: () => table([{ k: 'business_date', l: 'Date', t: 'date' }, { k: 'doc_type', l: 'Document', t: 'badge' }, { k: 'narration', l: 'Details' },
      { k: 'debit', l: 'Debit (they owe)', t: 'money' }, { k: 'credit', l: 'Credit (paid / we owe)', t: 'money' }], p.ledger, { empty: 'No entries.' }),
  };
  const tabEl = el.querySelector('#tabs');
  const show = name => {
    tabEl.innerHTML = Object.keys(tabs).map(t => `<button class="${t === name ? 'on' : ''}">${t}</button>`).join('');
    tabEl.querySelectorAll('button').forEach(b => b.onclick = () => show(b.textContent));
    el.querySelector('#tab').innerHTML = tabs[name]();
  };
  show(p.party_type === 'CUSTOMER' ? 'Items bought' : 'Exchanged / sold to us');
  el.querySelector('#edit').onclick = async () => {
    const v = await ask('Edit ' + p.name, partyFields(p));
    if (!v) return;
    try { await api('/parties/' + id, { method: 'PUT', body: v }); party(el, id); } catch (e) { fail(e); }
  };
  el.querySelector('#settle')?.addEventListener('click', async () => {
    const v = await ask('Receive or pay money', [{ name: 'direction', label: 'Direction', type: 'select', options: [['IN', 'Received from party'], ['OUT', 'Paid to party']],
      value: +p.balance > 0 ? 'IN' : 'OUT' }, { name: 'mode', label: 'Mode', type: 'select', options: PAY_MODES },
    { name: 'amount', label: 'Amount ₹', type: 'number', required: true, value: Math.abs(+p.balance).toFixed(3) }, { name: 'reference', label: 'Reference' }]);
    if (!v) return;
    try { await api(`/parties/${id}/settle`, { method: 'POST', body: v }); toast('Recorded.', 'ok'); party(el, id); } catch (e) { fail(e); }
  });
}

export { formValues };
