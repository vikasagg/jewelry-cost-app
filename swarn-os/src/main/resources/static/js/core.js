// Shared helpers: API calls, formatting, dialogs, tables, QR codes, camera scanner, voice input.

export const state = { session: null, masters: null, rateToday: null };

const SESSION_KEY = 'swarn-os-session';

export function loadSession() {
  try {
    state.session = JSON.parse(localStorage.getItem(SESSION_KEY) || 'null');
  } catch { state.session = null; }
  return state.session;
}

export function saveSession(s) {
  state.session = s;
  try { s ? localStorage.setItem(SESSION_KEY, JSON.stringify(s)) : localStorage.removeItem(SESSION_KEY); } catch { /* private mode */ }
}

export function logout() {
  saveSession(null);
  state.masters = null;
  location.hash = '#/login';
}

export function can(permission) {
  return !!state.session?.permissions?.[permission];
}

export async function api(path, { method = 'GET', body, form, raw } = {}) {
  const headers = {};
  if (state.session?.token) headers.Authorization = 'Bearer ' + state.session.token;
  let payload;
  if (form) payload = form;
  else if (body !== undefined) { headers['Content-Type'] = 'application/json'; payload = JSON.stringify(body); }
  let res;
  try {
    res = await fetch('/api' + path, { method, headers, body: payload });
  } catch {
    throw new Error('Cannot reach the shop server. Check the network or that the server is running.');
  }
  if (res.status === 401 && !path.includes('/login')) { logout(); throw new Error('Please sign in again.'); }
  if (raw) return res;
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) throw new Error(data?.error || ('Error ' + res.status));
  return data;
}

export function fileUrl(path) {
  return '/api' + path + (path.includes('?') ? '&' : '?') + 'token=' + encodeURIComponent(state.session?.token || '');
}

export async function loadMasters(force) {
  if (!state.masters || force) state.masters = await api('/masters');
  return state.masters;
}

// ---------- formatting (3 decimals for money, weights and rates: owner decision D-04) ----------

const money3 = new Intl.NumberFormat('en-IN', { minimumFractionDigits: 3, maximumFractionDigits: 3 });
const money0 = new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0 });
const wt3 = new Intl.NumberFormat('en-IN', { minimumFractionDigits: 3, maximumFractionDigits: 3 });

export const fmt = {
  money: v => v === null || v === undefined || v === '' ? '—' : '₹' + money3.format(Number(v)),
  rupees: v => v === null || v === undefined || v === '' ? '—' : '₹' + money0.format(Number(v)),
  wt: v => v === null || v === undefined || v === '' ? '—' : wt3.format(Number(v)) + ' g',
  num: v => v === null || v === undefined || v === '' ? '—' : wt3.format(Number(v)),
  int: v => v === null || v === undefined ? '—' : money0.format(Number(v)),
  date: v => {
    if (!v) return '—';
    const d = new Date(String(v).length === 10 ? v + 'T00:00:00' : v);
    return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
  },
  dt: v => v ? new Date(v).toLocaleString('en-IN', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—',
  label: s => s ? String(s).replace(/_/g, ' ').toLowerCase().replace(/^\w/, c => c.toUpperCase()) : '',
};

export function esc(v) {
  return String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

export function today() {
  const d = new Date();
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
}

export function daysAgo(n) {
  const d = new Date(Date.now() - n * 86400000);
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
}

const STATUS_TONE = {
  IN_STOCK: 'ok', SOLD: 'gold', RESERVED: 'warn', LOST: 'bad', RETURNED: 'info', WITH_KARIGAR: 'warn',
  APPROVED: 'ok', PROPOSED: 'warn', REJECTED: 'bad', SUPERSEDED: '', FINAL: 'ok', OPEN: 'warn', CLOSED: 'ok',
  RECEIVED: 'info', IN_PROGRESS: 'warn', READY: 'ok', DELIVERED: '', SEEN: 'info', UNSEEN: 'gold',
  MISSING: 'bad', UNEXPECTED: 'warn', UNKNOWN: 'warn', MARK_LOST: 'bad', ACCEPTED: 'ok', OVERDUE: 'bad', ACTIVE: 'ok',
  SUSPENDED: 'bad', CASH: 'gold', BANK: 'info', GOLD: 'gold', SILVER: '', MIXED: 'warn', CREDIT: 'bad',
};

export function badge(status) {
  if (!status) return '';
  return `<span class="badge ${STATUS_TONE[status] ?? ''}">${esc(fmt.label(status))}</span>`;
}

// ---------- toast & dialogs ----------

export function toast(msg, kind = '') {
  const el = document.createElement('div');
  el.className = 'toast ' + kind;
  el.textContent = msg;
  document.getElementById('toasts').append(el);
  setTimeout(() => el.remove(), kind === 'bad' ? 6000 : 3500);
}

export function fail(e) {
  toast(e.message || String(e), 'bad');
}

export function modal(html, { wide = false, onClose } = {}) {
  const root = document.getElementById('modal-root');
  const bg = document.createElement('div');
  bg.className = 'modal-bg';
  bg.innerHTML = `<div class="modal ${wide ? 'wide' : ''}" role="dialog">${html}</div>`;
  const close = () => { bg.remove(); onClose?.(); };
  bg.addEventListener('click', e => { if (e.target === bg) close(); });
  bg.querySelectorAll('[data-close]').forEach(b => b.addEventListener('click', close));
  root.append(bg);
  bg.querySelector('input,select,textarea')?.focus();
  return { el: bg.querySelector('.modal'), close };
}

/** Simple form dialog; resolves with the values or null when cancelled. */
export function ask(title, fields, { okText = 'Save', note = '' } = {}) {
  return new Promise(resolve => {
    const body = fields.map(f => fieldHtml(f)).join('');
    const m = modal(`<h2>${esc(title)}</h2>${note ? `<p class="muted small">${esc(note)}</p>` : ''}
      <form>${body}<div class="row end"><button type="button" data-close>Cancel</button>
      <button class="primary" type="submit">${esc(okText)}</button></div></form>`, { onClose: () => resolve(null) });
    m.el.querySelector('form').addEventListener('submit', e => {
      e.preventDefault();
      const v = formValues(e.target);
      resolve(v);
      m.el.parentElement.remove();
    });
  });
}

export function fieldHtml(f) {
  const id = 'f_' + f.name;
  const val = f.value ?? '';
  let input;
  if (f.type === 'select') {
    input = `<select id="${id}" name="${f.name}" ${f.required ? 'required' : ''}>${(f.options || []).map(o => {
      const [v, l] = Array.isArray(o) ? o : [o, o];
      return `<option value="${esc(v)}" ${String(v) === String(val) ? 'selected' : ''}>${esc(l)}</option>`;
    }).join('')}</select>`;
  } else if (f.type === 'textarea') {
    input = `<textarea id="${id}" name="${f.name}" rows="${f.rows || 3}" placeholder="${esc(f.placeholder || '')}">${esc(val)}</textarea>`;
  } else if (f.type === 'checkbox') {
    return `<label class="check field"><input type="checkbox" name="${f.name}" ${val ? 'checked' : ''}> ${esc(f.label)}</label>`;
  } else {
    input = `<input id="${id}" name="${f.name}" type="${f.type || 'text'}" value="${esc(val)}" ${f.required ? 'required' : ''}
      ${f.step ? `step="${f.step}"` : (f.type === 'number' ? 'step="0.001"' : '')} ${f.min !== undefined ? `min="${f.min}"` : ''}
      placeholder="${esc(f.placeholder || '')}" ${f.inputmode ? `inputmode="${f.inputmode}"` : ''} autocomplete="off">`;
  }
  return `<div class="field ${f.cls || ''}"><label for="${id}">${esc(f.label)}</label>${input}${f.hint ? `<div class="muted small">${esc(f.hint)}</div>` : ''}</div>`;
}

export function formValues(form) {
  const out = {};
  for (const el of form.elements) {
    if (!el.name) continue;
    out[el.name] = el.type === 'checkbox' ? el.checked : el.value;
  }
  return out;
}

// ---------- tables ----------

/**
 * columns: [{k, l, t: 'money'|'wt'|'num'|'int'|'date'|'dt'|'badge', f: row => html}]
 */
export function table(columns, rows, { click, foot, empty = 'Nothing to show yet.', resp = true } = {}) {
  if (!rows || rows.length === 0) return `<div class="empty">${esc(empty)}</div>`;
  const cell = (c, r) => {
    if (c.f) return c.f(r);
    const v = r[c.k];
    switch (c.t) {
      case 'money': return fmt.money(v);
      case 'rupees': return fmt.rupees(v);
      case 'wt': return fmt.num(v);
      case 'num': return fmt.num(v);
      case 'int': return fmt.int(v);
      case 'date': return fmt.date(v);
      case 'dt': return fmt.dt(v);
      case 'datetime': return fmt.dt(v);
      case 'badge': return badge(v);
      default: return esc(v);
    }
  };
  const isNum = c => ['money', 'rupees', 'wt', 'num', 'int'].includes(c.t);
  return `<div class="tablewrap"><table class="${resp ? 'resp' : ''}"><thead><tr>${columns.map(c =>
    `<th class="${isNum(c) ? 'num' : ''}">${esc(c.l)}</th>`).join('')}</tr></thead><tbody>${rows.map((r, i) =>
    `<tr ${click ? `class="click" data-i="${i}"` : ''}>${columns.map(c =>
      `<td class="${isNum(c) ? 'num' : c.t === 'date' || c.t === 'dt' ? 'nowrap' : ''}" data-l="${esc(c.l)}">${cell(c, r)}</td>`).join('')}</tr>`).join('')}</tbody>
    ${foot ? `<tfoot><tr>${columns.map((c, i) => `<td class="${isNum(c) ? 'num' : ''}">${i === 0 ? 'Total' :
      (foot[c.k] !== undefined ? cell({ ...c, f: null }, foot) : '')}</td>`).join('')}</tr></tfoot>` : ''}
    </table></div>`;
}

export function bindRows(el, rows, onClick) {
  el.querySelectorAll('tr.click').forEach(tr => tr.addEventListener('click', () => onClick(rows[+tr.dataset.i])));
}

// ---------- QR codes ----------

export function qrSvg(text, cell = 3) {
  if (!window.qrcode) return '';
  const q = window.qrcode(0, 'M');
  q.addData(String(text));
  q.make();
  return q.createSvgTag({ cellSize: cell, margin: 0, scalable: true });
}

// ---------- scanner: keyboard-wedge scanners, typed codes and the phone/laptop camera ----------

/**
 * Renders a scan box into `el`. A USB/Bluetooth barcode or QR scanner types the code and presses Enter;
 * the camera button decodes QR codes with the browser's BarcodeDetector or jsQR.
 * RFID handhelds (CX1500N) will feed the same callback in the RFID phase.
 */
export function scanner(el, onCode, { placeholder = 'Scan QR / type tag code and press Enter', keepFocus = true } = {}) {
  el.innerHTML = `<div class="scanbox"><input class="scan-in" placeholder="${esc(placeholder)}" autocomplete="off"
      autocapitalize="characters" enterkeyhint="go"><button type="button" class="cam" title="Scan with camera">${ICONS.camera} <span class="hide-sm">Camera</span></button></div>
      <div class="cam-area hidden"><video class="video" playsinline muted></video><div class="row" style="margin-top:.5rem">
      <span class="muted small cam-msg">Point the camera at the QR label…</span><span class="spacer"></span>
      <button type="button" class="small cam-stop">Stop camera</button></div></div>`;
  const input = el.querySelector('.scan-in');
  const go = () => {
    const code = input.value.trim();
    input.value = '';
    if (code) onCode(code);
  };
  input.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); go(); } });
  if (keepFocus) setTimeout(() => input.focus(), 50);

  let stream = null, timer = null, last = '', lastAt = 0;
  const area = el.querySelector('.cam-area');
  const video = el.querySelector('video');
  const stop = () => {
    clearTimeout(timer);
    stream?.getTracks().forEach(t => t.stop());
    stream = null;
    area.classList.add('hidden');
  };
  el.querySelector('.cam-stop').addEventListener('click', stop);
  el.querySelector('.cam').addEventListener('click', async () => {
    if (stream) return stop();
    try {
      stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
    } catch {
      return toast('Camera not available. Allow camera access, or use a scanner / type the code.', 'bad');
    }
    area.classList.remove('hidden');
    video.srcObject = stream;
    await video.play();
    const detector = 'BarcodeDetector' in window ? new window.BarcodeDetector({ formats: ['qr_code', 'code_128', 'ean_13'] }) : null;
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const tick = async () => {
      if (!stream) return;
      let code = null;
      try {
        if (detector) {
          const found = await detector.detect(video);
          code = found[0]?.rawValue;
        } else if (window.jsQR && video.videoWidth) {
          canvas.width = video.videoWidth;
          canvas.height = video.videoHeight;
          ctx.drawImage(video, 0, 0);
          code = window.jsQR(ctx.getImageData(0, 0, canvas.width, canvas.height).data, canvas.width, canvas.height)?.data;
        }
      } catch { /* keep trying */ }
      if (code && (code !== last || Date.now() - lastAt > 2500)) {
        last = code; lastAt = Date.now();
        navigator.vibrate?.(60);
        onCode(code.trim());
      }
      timer = setTimeout(tick, 180);
    };
    tick();
  });
  const observer = new MutationObserver(() => { if (!document.body.contains(el)) { stop(); observer.disconnect(); } });
  observer.observe(document.body, { childList: true, subtree: true });
  return { focus: () => input.focus(), stop };
}

// ---------- voice ----------

export function voiceSupported() {
  return 'webkitSpeechRecognition' in window || 'SpeechRecognition' in window;
}

/** Listens once and returns the text. Language en-IN or hi-IN from Settings (ai.voice.language). */
export function listen(lang = 'en-IN') {
  return new Promise((resolve, reject) => {
    const R = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!R) return reject(new Error('Voice input needs Chrome, Edge or Safari. You can type the question instead.'));
    const r = new R();
    r.lang = lang;
    r.interimResults = false;
    r.maxAlternatives = 1;
    r.onresult = e => resolve(e.results[0][0].transcript);
    r.onerror = e => reject(new Error(e.error === 'not-allowed' ? 'Microphone permission was refused.' : 'Did not catch that - please try again.'));
    r.onend = () => resolve('');
    r.start();
  });
}

export function speak(text, lang = 'en-IN') {
  try {
    if (!('speechSynthesis' in window)) return;
    const u = new SpeechSynthesisUtterance(text);
    u.lang = lang;
    speechSynthesis.cancel();
    speechSynthesis.speak(u);
  } catch { /* optional */ }
}

// ---------- icons (inline SVG, stroke = currentColor) ----------

const i = d => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
export const ICONS = {
  home: i('<path d="M3 11 12 4l9 7"/><path d="M5 10v10h14V10"/>'),
  rate: i('<path d="M4 19h16"/><path d="m5 15 4-5 4 3 6-7"/>'),
  bill: i('<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6"/>'),
  stock: i('<path d="M7 4 4 9l8 11 8-11-3-5z"/><path d="M4 9h16"/>'),
  buy: i('<path d="M4 6h16l-2 10H6z"/><circle cx="9" cy="20" r="1"/><circle cx="17" cy="20" r="1"/>'),
  people: i('<circle cx="9" cy="8" r="3"/><path d="M3 20c0-3 3-5 6-5s6 2 6 5"/><path d="M16 4a3 3 0 0 1 0 6M21 20c0-2-1-4-4-5"/>'),
  repair: i('<path d="M14 6a4 4 0 0 0 5 5l-9 9-3-3 9-9a4 4 0 0 0-2-2z"/>'),
  tally: i('<path d="M9 5H5v14h14V5h-4"/><path d="M9 3h6v4H9z"/><path d="m9 13 2 2 4-4"/>'),
  report: i('<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>'),
  ledger: i('<path d="M4 4h12a4 4 0 0 1 4 4v12H8a4 4 0 0 1-4-4z"/><path d="M8 8h8M8 12h8"/>'),
  settings: i('<circle cx="12" cy="12" r="3"/><path d="M19 12a7 7 0 0 0-.1-1.2l2-1.6-2-3.4-2.4 1a7 7 0 0 0-2-1.2L14 3h-4l-.5 2.6a7 7 0 0 0-2 1.2l-2.4-1-2 3.4 2 1.6a7 7 0 0 0 0 2.4l-2 1.6 2 3.4 2.4-1a7 7 0 0 0 2 1.2L10 21h4l.5-2.6a7 7 0 0 0 2-1.2l2.4 1 2-3.4-2-1.6c.1-.4.1-.8.1-1.2z"/>'),
  mic: i('<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>'),
  camera: i('<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>'),
  menu: i('<path d="M4 7h16M4 12h16M4 17h16"/>'),
  search: i('<circle cx="11" cy="11" r="6"/><path d="m20 20-4-4"/>'),
  print: i('<path d="M7 9V3h10v6"/><rect x="4" y="9" width="16" height="8" rx="2"/><path d="M7 14h10v7H7z"/>'),
  plus: i('<path d="M12 5v14M5 12h14"/>'),
  share: i('<circle cx="6" cy="12" r="2"/><circle cx="18" cy="6" r="2"/><circle cx="18" cy="18" r="2"/><path d="m8 11 8-4M8 13l8 4"/>'),
  usb: i('<path d="M12 3v14"/><path d="m9 6 3-3 3 3"/><path d="M8 10v3l4 3 4-3v-3"/><circle cx="12" cy="19" r="2"/>'),
};
