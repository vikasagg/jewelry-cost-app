// App shell: sign-in, navigation, the "ask" bar with voice, and the hash router.
import { state, api, loadSession, saveSession, logout, can, esc, fmt, toast, fail, listen, voiceSupported, ICONS, loadMasters } from './core.js';
import * as views from './views.js';
import * as trade from './trade.js';
import * as stock from './stock.js';
import * as admin from './admin.js';

const NAV = [
  ['#/', 'Dashboard', 'home'],
  ['#/rates', 'Metal rates', 'rate'],
  ['#/sale/new', 'New bill', 'bill', 'BILL'],
  ['#/sales', 'Sales', 'bill'],
  ['#/inventory', 'Inventory', 'stock'],
  ['#/purchases', 'Purchases', 'buy', 'PURCHASE'],
  ['#/tally', 'Daily stock tally', 'tally'],
  ['#/repairs', 'Repairs', 'repair'],
  ['#/parties/CUSTOMER', 'Customers', 'people'],
  ['#/parties/VENDOR', 'Vendors & karigars', 'people'],
  null,
  ['#/reports', 'Reports', 'report'],
  ['#/ledgers', 'Cash, bank & metal books', 'ledger', 'REPORTS_LEDGER'],
  ['#/settings', 'Settings & backup', 'settings'],
];

const ROUTES = [
  [/^#\/login$/, admin.login, { bare: true }],
  [/^#\/platform$/, admin.platform, { bare: true }],
  [/^#\/?$/, views.dashboard],
  [/^#\/rates$/, views.rates],
  [/^#\/ask\/(.+)$/, views.ask],
  [/^#\/reports$/, views.reports],
  [/^#\/report\/([a-z_]+)$/, views.report],
  [/^#\/ledgers$/, views.ledgers],
  [/^#\/sale\/new$/, trade.newSale],
  [/^#\/sales$/, trade.sales],
  [/^#\/sale\/(\d+)$/, trade.invoice],
  [/^#\/purchase\/new$/, trade.newPurchase],
  [/^#\/purchases$/, trade.purchases],
  [/^#\/purchase\/(\d+)$/, trade.purchase],
  [/^#\/parties\/([A-Z]+)$/, trade.parties],
  [/^#\/party\/(\d+)$/, trade.party],
  [/^#\/inventory$/, stock.inventory],
  [/^#\/item\/new$/, stock.newItem],
  [/^#\/item\/(\d+)$/, stock.item],
  [/^#\/labels\/([\d,]+)$/, stock.labels],
  [/^#\/tally$/, stock.tallyList],
  [/^#\/tally\/(\d+)$/, stock.tallySession],
  [/^#\/repairs$/, stock.repairs],
  [/^#\/repair\/new$/, stock.newRepair],
  [/^#\/repair\/(\d+)$/, stock.repair],
  [/^#\/settings$/, admin.settings],
];

function shell() {
  const s = state.session;
  const app = document.getElementById('app');
  app.innerHTML = `<div class="shell">
    <aside class="side">
      <div class="brand"><img src="icon.svg" alt=""><div><b>${esc(s.shop.name)}</b><span>AI Jewellery ERP · ${esc(s.shop.storageMode === 'LOCAL' ? 'Local database' : 'Cloud database')}</span></div></div>
      <nav class="nav">${NAV.map(n => n === null ? '<div class="sep"></div>' : (n[3] && !can(n[3])) ? '' :
        `<a href="${n[0]}" data-path="${n[0]}">${ICONS[n[2]]}<span>${n[1]}</span></a>`).join('')}</nav>
      <div class="who">${esc(s.user.fullName)} · ${esc(fmt.label(s.user.role))}<br>Shop code: <b>${esc(s.shop.code)}</b><br>
        <button class="small dark" id="logout">Sign out</button></div>
    </aside>
    <div class="main">
      <header class="top">
        <button class="menu ghost" id="menu" aria-label="Menu">${ICONS.menu}</button>
        <form class="askbar" id="askbar" autocomplete="off">
          ${ICONS.search}<input id="askin" placeholder='Ask or say: "diamond jewellery below 50000", "tag T000012", "22 carat chains 20 to 30 grams"'>
          <button type="button" class="mic" id="mic" title="Speak (English / Hindi)">${ICONS.mic}</button>
        </form>
        <a href="#/rates" id="ratechip" class="ratechip bad">Rate…</a>
      </header>
      <main class="content" id="view"></main>
    </div>
  </div>`;
  document.getElementById('logout').onclick = logout;
  document.getElementById('menu').onclick = () => app.querySelector('.shell').classList.toggle('open');
  app.querySelector('.side').addEventListener('click', e => { if (e.target.closest('a')) app.querySelector('.shell').classList.remove('open'); });
  document.getElementById('askbar').addEventListener('submit', e => {
    e.preventDefault();
    const q = document.getElementById('askin').value.trim();
    if (q) location.hash = '#/ask/' + encodeURIComponent(q);
  });
  const mic = document.getElementById('mic');
  if (!voiceSupported()) mic.title = 'Voice needs Chrome, Edge or Safari';
  mic.onclick = async () => {
    mic.classList.add('listening');
    try {
      const lang = (state.masters?.voiceLang) || 'en-IN';
      const text = await listen(lang);
      if (text) {
        document.getElementById('askin').value = text;
        location.hash = '#/ask/' + encodeURIComponent(text);
      }
    } catch (e) { fail(e); } finally { mic.classList.remove('listening'); }
  };
}

export async function refreshRateChip() {
  const chip = document.getElementById('ratechip');
  if (!chip) return;
  try {
    const r = await api('/rates/today');
    state.rateToday = r;
    if (r.approved) {
      const g22 = r.approved.lines.find(l => l.metal === 'GOLD' && l.purity_code === '22K');
      chip.className = 'ratechip ok';
      chip.textContent = `22K ${fmt.rupees(g22?.rate_per_gram * 10)}/10g · 24K ${fmt.rupees(r.approved.gold_24k * 10)}`;
    } else {
      chip.className = 'ratechip bad';
      chip.textContent = r.pending.length ? 'Rate waiting for approval' : 'Set today\'s rate';
    }
  } catch { /* shown elsewhere */ }
}

async function route() {
  const hash = location.hash || '#/';
  for (const [re, view, opt] of ROUTES) {
    const m = hash.match(re);
    if (!m) continue;
    if (!opt?.bare && !state.session) { location.hash = '#/login'; return; }
    if (opt?.bare) {
      document.getElementById('app').innerHTML = '<div id="view"></div>';
    } else if (!document.querySelector('.shell')) {
      shell();
      try {
        await loadMasters();
        const cfg = await api('/config');
        state.masters.voiceLang = cfg.find(c => c.config_key === 'ai.voice.language')?.config_value || 'en-IN';
      } catch (e) { fail(e); }
    }
    document.querySelectorAll('.nav a').forEach(a => a.classList.toggle('active',
      a.dataset.path === hash || (a.dataset.path !== '#/' && hash.startsWith(a.dataset.path))));
    const el = document.getElementById('view');
    const askin = document.getElementById('askin');
    if (askin && !hash.startsWith('#/ask/')) askin.value = '';
    el.innerHTML = '<div class="empty">Loading…</div>';
    window.scrollTo(0, 0);
    try {
      await view(el, ...m.slice(1).map(decodeURIComponent));
    } catch (e) {
      el.innerHTML = `<div class="alert bad">${esc(e.message)}</div>`;
    }
    if (!opt?.bare) refreshRateChip();
    return;
  }
  document.getElementById('view').innerHTML = '<div class="empty">Page not found.</div>';
}

window.addEventListener('hashchange', route);
window.addEventListener('rate-changed', refreshRateChip);
loadSession();
if (state.session) {
  api('/auth/me').then(s => saveSession(s)).catch(() => {});
}
route();
if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
export { toast };
