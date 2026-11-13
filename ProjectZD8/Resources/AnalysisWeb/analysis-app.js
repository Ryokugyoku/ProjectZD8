// Application shell: navigation, responsive layout, host bridge and demo mode.
import { h, clear, formatDate } from './analysis-dom.js';
import { makeTranslator, resolveLanguage } from './analysis-i18n.js';
import { buildSession, rebuildDerived } from './analysis-model.js';
import { buildDemoDataset, buildDemoTrend } from './analysis-demo.js';
import { exportCsv, exportPng, hasHost, onHostMessage, postToHost } from './analysis-host.js';
import { invalidateTheme, theme, watchTheme } from './analysis-theme.js';
import { createOverviewView } from './analysis-view-overview.js';
import { createTimeSeriesView } from './analysis-view-timeseries.js';
import { createScatterView } from './analysis-view-scatter.js';
import { createDistributionView } from './analysis-view-distribution.js';
import { createMapTableView } from './analysis-view-maptable.js';
import { createDerivedView } from './analysis-view-derived.js';
import { createCompareView } from './analysis-view-compare.js';
import { createTrendsView } from './analysis-view-trends.js';
import { createQualityView } from './analysis-view-quality.js';
import { createExportView } from './analysis-view-export.js';

const VIEWS = [
  { id: 'overview', create: createOverviewView, icon: '▦' },
  { id: 'timeseries', create: createTimeSeriesView, icon: '≈' },
  { id: 'scatter', create: createScatterView, icon: '∴' },
  { id: 'distribution', create: createDistributionView, icon: '▁' },
  { id: 'maptable', create: createMapTableView, icon: '▩' },
  { id: 'derived', create: createDerivedView, icon: 'ƒ' },
  { id: 'compare', create: createCompareView, icon: '⇅' },
  { id: 'trends', create: createTrendsView, icon: '↗' },
  { id: 'quality', create: createQualityView, icon: '✓' },
  { id: 'export', create: createExportView, icon: '⇩' },
];

const params = new URLSearchParams(location.search);
const hosted = hasHost();
const demo = !hosted && params.get('demo') === '1';
const demoRate = Number(params.get('rate')) || 10;

let lang = resolveLanguage(params.get('lang') || navigator.language);
let t = makeTranslator(lang);

const ctx = {
  get lang() { return lang; },
  get t() { return t; },
  sessions: [],
  get primary() { return this.sessions[0] || null; },
  trend: null,
  range: null,
  view: 'overview',
  exportables: new Map(),
  hostState: { phase: 'idle', progress: null, failure: null },
  setRange(range) {
    this.range = range;
    for (const v of Object.values(instances)) v.onRange();
  },
  navigate(id) { activate(id); },
  jumpTo(t0, t1) {
    activate('timeseries');
    instances.timeseries.jump(t0, t1);
  },
  rebuildDerived() { return this.primary ? rebuildDerived(this.primary, t) : {}; },
  registerExport(label, getter) { this.exportables.set(label, getter); },
  exportCsv,
  exportPng,
  host: {
    requestSession() { if (hosted) postToHost({ type: 'requestSession' }); else demoAddSession(); },
    openPicker() { if (hosted) postToHost({ type: 'openSessionPicker' }); },
    requestTrend(includeDemo) { if (hosted) postToHost({ type: 'requestTrend', includeDemo }); else demoTrend(includeDemo); },
    removeSession(id) { if (hosted) postToHost({ type: 'removeSession', id }); else demoRemove(id); },
  },
};

const instances = {};
const dirty = new Set(VIEWS.map((v) => v.id));
const root = document.getElementById('app');
let shell = null;

function viewTitle(id) { return t(`view.${id}`); }

function buildShell() {
  clear(root);
  const nav = h('nav', { class: 'nav', 'aria-label': 'views' }, VIEWS.map((v) => h('button', {
    type: 'button', class: 'nav-item', dataset: { view: v.id }, 'aria-current': ctx.view === v.id ? 'page' : null, onclick: () => activate(v.id),
  }, h('span', { class: 'nav-icon', text: v.icon, 'aria-hidden': 'true' }), h('span', { class: 'nav-label', text: viewTitle(v.id) }))));
  const chips = h('div', { class: 'session-chips' });
  const banner = h('div', { class: 'banner', hidden: true });
  const content = h('main', { class: 'content' });
  const top = h('header', { class: 'topbar' }, h('div', { class: 'brand', text: t('app.title') }), chips,
    h('div', { class: 'top-actions' },
      hosted ? h('button', { type: 'button', class: 'btn', onclick: () => ctx.host.openPicker(), text: t('app.changeSession') }) : null,
      h('button', { type: 'button', class: 'btn', onclick: () => ctx.host.requestSession(), text: t('app.addSession'), disabled: ctx.sessions.length >= 3 || (!hosted && !demo) })));
  root.append(top, banner, h('div', { class: 'body' }, nav, content));
  shell = { nav, chips, banner, content, top };
  for (const id of Object.keys(instances)) shell.content.append(instances[id].el);
  renderChips();
  renderBanner();
}

function renderChips() {
  if (!shell) return;
  clear(shell.chips);
  ctx.sessions.forEach((s, i) => {
    shell.chips.append(h('span', { class: 'chip', style: { borderColor: theme().series[i] } },
      h('i', { style: { background: theme().series[i] } }),
      h('span', { class: 'chip-label', text: `${s.vehicle.name} · ${formatDate(s.startedAtMs, lang)}${s.info.isDemo ? ' · ' + t('common.demo') : ''}` }),
      i > 0 ? h('button', { type: 'button', class: 'chip-x', title: t('common.remove'), 'aria-label': t('common.remove'), onclick: () => ctx.host.removeSession(s.id), text: '×' }) : null));
  });
}

function renderBanner() {
  if (!shell) return;
  const { phase, progress, failure } = ctx.hostState;
  clear(shell.banner);
  shell.banner.hidden = phase === 'idle' || phase === 'ready';
  if (shell.banner.hidden) return;
  shell.banner.className = `banner ${phase}`;
  if (phase === 'loading') shell.banner.append(h('span', { text: t('host.loading') }), h('div', { class: 'spinner' }));
  if (phase === 'downloading') shell.banner.append(h('span', { text: t('host.downloading', { percent: Math.round((progress || 0) * 100) }) }), h('progress', { max: 1, value: progress || 0 }));
  if (phase === 'failed') {
    const key = `host.failure.${failure}`;
    shell.banner.append(h('span', { text: t(key) === key ? t('host.failure.generic') : t(key) }),
      h('button', { type: 'button', class: 'btn', text: t('common.dismiss'), onclick: () => postToHost({ type: 'dismissFailure' }) }));
  }
}

function instance(id) {
  if (!instances[id]) {
    const def = VIEWS.find((v) => v.id === id);
    instances[id] = def.create(ctx);
    instances[id].el.hidden = true;
    shell.content.append(instances[id].el);
  }
  return instances[id];
}

function activate(id) {
  ctx.view = id;
  for (const item of shell.nav.children) item.setAttribute('aria-current', item.dataset.view === id ? 'page' : 'false');
  for (const [key, view] of Object.entries(instances)) view.el.hidden = key !== id;
  const view = instance(id);
  view.el.hidden = false;
  if (dirty.has(id)) { dirty.delete(id); view.refresh(); }
  const active = shell.nav.querySelector('[aria-current="page"]');
  if (active && active.scrollIntoView) active.scrollIntoView({ block: 'nearest', inline: 'center' });
}

function markAllDirty() {
  ctx.exportables.clear();
  for (const v of VIEWS) dirty.add(v.id);
  activate(ctx.view);
}

function setSessions(sessions) {
  const previous = ctx.primary;
  ctx.sessions = sessions;
  if (previous && ctx.primary && previous.id === ctx.primary.id) { ctx.primary.derivedDefs = previous.derivedDefs; rebuildDerived(ctx.primary, t); }
  else ctx.range = null;
  renderChips();
  if (shell) shell.top.querySelector('.top-actions .btn:last-child').disabled = sessions.length >= 3 || (!hosted && !demo);
  markAllDirty();
}

// ---- host mode ----------------------------------------------------------------------------------------------
const loaded = new Map();
let syncGeneration = 0;

async function applyHostConfiguration(message) {
  if (message.language && message.language !== lang) { lang = resolveLanguage(message.language); t = makeTranslator(lang); document.documentElement.lang = lang; buildShell(); for (const v of VIEWS) dirty.add(v.id); }
  ctx.hostState = { phase: message.phase, progress: message.progress, failure: message.failure };
  renderBanner();
  const generation = ++syncGeneration;
  const wanted = message.sessions;
  try {
    const sessions = [];
    for (let i = 0; i < wanted.length; i++) {
      const { id, datasetPath } = wanted[i];
      let session = loaded.get(id);
      if (!session) {
        const response = await fetch(datasetPath);
        if (!response.ok) throw new Error(`dataset ${response.status}`);
        session = buildSession(await response.json(), i);
        loaded.set(id, session);
      }
      session.index = i;
      sessions.push(session);
    }
    if (generation !== syncGeneration) return;
    for (const id of [...loaded.keys()]) if (!wanted.some((w) => w.id === id)) loaded.delete(id);
    const same = sessions.length === ctx.sessions.length && sessions.every((s, i) => s === ctx.sessions[i]);
    if (!same) setSessions(sessions);
    if (message.trendPath && message.trendPath !== lastTrendPath) {
      lastTrendPath = message.trendPath;
      const response = await fetch(message.trendPath);
      if (response.ok) { ctx.trend = await response.json(); dirty.add('trends'); if (ctx.view === 'trends') activate('trends'); }
    }
    if (!message.trendPath) lastTrendPath = null;
  } catch (error) {
    showFatal(error);
  }
}
let lastTrendPath = null;

// ---- demo mode ----------------------------------------------------------------------------------------------
let demoVariants = [];
let demoLastIncludeDemo = false;

function demoLoad() { setSessions(demoVariants.map((v, i) => buildSession(buildDemoDataset({ seed: v.seed, variant: v.variant, lang, rate: demoRate }), i))); }
function demoAddSession() {
  if (demoVariants.length >= 3) return;
  const next = [{ seed: 1, variant: 0 }, { seed: 2, variant: 1 }, { seed: 3, variant: 2 }].find((v) => !demoVariants.some((d) => d.variant === v.variant));
  demoVariants.push(next);
  demoLoad();
}
function demoRemove(id) { const idx = ctx.sessions.findIndex((s) => s.id === id); if (idx > 0) { demoVariants.splice(idx, 1); demoLoad(); } }
function demoTrend(includeDemo) {
  demoLastIncludeDemo = includeDemo;
  const trend = buildDemoTrend({ lang });
  const excluded = includeDemo ? 0 : trend.sessions.filter((s) => s.isDemo).length;
  if (!includeDemo) trend.sessions = trend.sessions.filter((s) => !s.isDemo);
  trend.excludedDemoSessions = excluded;
  ctx.trend = trend;
  dirty.add('trends');
  if (ctx.view === 'trends') activate('trends');
}

function showFatal(error) {
  const message = error && error.code === 'schemaVersion' ? t('app.schemaMismatch') : t('app.loadFailed');
  if (shell) { shell.banner.hidden = false; shell.banner.className = 'banner failed'; shell.banner.replaceChildren(h('span', { text: `${message} (${error && error.message ? error.message : error})` })); }
  console.error(error);
}

// ---- boot --------------------------------------------------------------------------------------------------
document.documentElement.lang = lang;
const trailingInset = Number(params.get('trailingInset'));
if (Number.isFinite(trailingInset) && trailingInset > 0 && trailingInset < 200) document.documentElement.style.setProperty('--inset-trailing', `${trailingInset}px`);
buildShell();
watchTheme(() => { invalidateTheme(); renderChips(); });
window.addEventListener('error', (e) => showFatal(e.error || e.message));
window.addEventListener('unhandledrejection', (e) => showFatal(e.reason));
if (hosted) {
  onHostMessage((message) => { if (message.type === 'configure') applyHostConfiguration(message); });
  activate('overview');
  postToHost({ type: 'ready' });
} else if (demo) {
  demoVariants = [{ seed: 1, variant: 0 }];
  demoLoad();
  const start = params.get('view');
  if (start && VIEWS.some((v) => v.id === start)) activate(start);
  if (params.get('sessions') === '2') demoAddSession();
  if (params.get('sessions') === '3') { demoAddSession(); demoAddSession(); }
  window.rtDemo = { ctx };
} else {
  activate('overview');
  shell.content.prepend(h('div', { class: 'empty', text: t('app.openInApp') }));
}
void demoLastIncludeDemo;
