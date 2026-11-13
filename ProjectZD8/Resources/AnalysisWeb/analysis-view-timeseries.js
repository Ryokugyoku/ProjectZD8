// Time series: any number of stacked channels, synchronized zoom, range statistics for the brushed window.
import { h, clear, fmt } from './analysis-dom.js';
import { TimeChartGroup } from './analysis-chart-time.js';
import { theme, withAlpha } from './analysis-theme.js';
import { button, card, checkbox, empty, statCells, table, toggle } from './analysis-ui.js';
import { CH, sessionExtent, usableChannels } from './analysis-model.js';
import { summarize } from './analysis-stats.js';

export function createTimeSeriesView(ctx) {
  const el = h('div', { class: 'view timeseries' });
  const state = { selected: null, overlay: false, segments: false, maintenance: true, filter: '' };
  let group = null;
  let pendingDomain = null;
  const stats = h('div', { class: 'stats-host' });

  function defaultSelection(session) {
    const wanted = [CH.RPM, CH.SPEED, CH.COOLANT, CH.LOAD];
    const have = usableChannels(session).map((c) => c.id);
    const picked = wanted.filter((id) => have.includes(id)).slice(0, 3);
    return picked.length ? picked : have.slice(0, 3);
  }

  function renderStats() {
    clear(stats);
    const s = ctx.primary;
    if (!s || !group) return;
    const range = ctx.range || group.domain;
    const rows = state.selected.map((id) => s.channels.get(id)).filter(Boolean).map((c) => {
      const r = summarize(c.times, c.values, range[0], range[1]);
      return [`${c.name}${c.unit ? ' [' + c.unit + ']' : ''}`, ...statCells(r)];
    });
    const title = ctx.range ? ctx.t('ts.statsBrush', { from: fmtT(range[0]), to: fmtT(range[1]) }) : ctx.t('ts.statsWindow');
    stats.append(card(title, rows.length ? table(['', 'n', 'min', 'max', ctx.t('stat.mean'), ctx.t('stat.median'), 'p05', 'p95', ctx.t('stat.std'), ctx.t('stat.slope')], rows) : empty(ctx.t('ts.pick'))));
  }

  const fmtT = (v) => `${fmt(v, 1)} s`;

  function build() {
    const s = ctx.primary;
    if (!s) return;
    const t = theme();
    if (!state.selected || state.selected.some((id) => !s.channels.has(id))) state.selected = defaultSelection(s);
    const channels = state.selected.map((id) => s.channels.get(id));
    const bands = state.segments ? s.segments.map((seg) => ({ x0: seg.t0, x1: seg.t1, color: withAlpha(t.segment[seg.type], 0.16) })) : [];
    const gapBands = s.gaps.map((g) => ({ x0: g.startSeconds, x1: g.endSeconds, color: t.gap }));
    const markers = state.maintenance ? s.maintenance.filter((m) => m.t >= 0 && m.t <= s.durationSeconds).map((m) => ({ x: m.t, label: m.title, color: t.warn })) : [];
    const make = (list, i) => list.map((c, k) => ({ label: c.name, unit: c.unit, times: c.times, values: c.values, color: t.series[(i ?? k) % t.series.length], normalize: state.overlay ? [c.min, c.max] : null }));
    const specs = state.overlay
      ? [{ id: 'overlay', title: ctx.t('ts.overlay'), series: make(channels), bands: [...gapBands, ...bands], markers, height: 240 }]
      : channels.map((c, i) => ({ id: c.id, title: c.name, unit: c.unit, series: make([c], i), bands: [...gapBands, ...bands], markers, height: 150 }));
    const keep = Boolean(group && group.panels.length);
    group.setPanels(specs, sessionExtent(s), keep);
    if (pendingDomain) { group.setDomain(pendingDomain[0], pendingDomain[1]); pendingDomain = null; }
    renderStats();
  }

  function renderPicker(session, container) {
    clear(container);
    const search = h('input', { type: 'search', class: 'search', placeholder: ctx.t('common.search'), value: state.filter, oninput: (e) => { state.filter = e.target.value.toLowerCase(); renderList(); } });
    const list = h('div', { class: 'picker-list' });
    const renderList = () => {
      clear(list);
      for (const c of usableChannels(session)) {
        if (state.filter && !c.name.toLowerCase().includes(state.filter) && !c.id.toLowerCase().includes(state.filter)) continue;
        list.append(checkbox(`${c.name}${c.unit ? ' [' + c.unit + ']' : ''}`, state.selected.includes(c.id), (on) => {
          state.selected = on ? [...state.selected, c.id] : state.selected.filter((id) => id !== c.id);
          build();
        }));
      }
    };
    renderList();
    container.append(h('h3', { text: ctx.t('ts.channels') }), search, list);
  }

  function refresh() {
    const s = ctx.primary;
    clear(el);
    if (group) { group.destroy(); group = null; }
    if (!s) { el.append(empty(ctx.t('common.noSession'))); return; }
    if (!state.selected || state.selected.some((id) => !s.channels.has(id))) state.selected = defaultSelection(s);
    const t = ctx.t;
    const picker = h('aside', { class: 'picker card' });
    renderPicker(s, picker);
    const chartHost = h('div', { class: 'chart-host stack' });
    const brushToggle = toggle(t('ts.brushMode'), false, (on) => group.setBrushMode(on));
    const toolbar = h('div', { class: 'toolbar' },
      brushToggle,
      button(t('ts.zoomBrush'), () => group.zoomToBrush()),
      button(t('ts.clearBrush'), () => group.setBrush(null)),
      button(t('ts.resetZoom'), () => group.resetZoom()),
      toggle(t('ts.overlayToggle'), state.overlay, (on) => { state.overlay = on; build(); }),
      toggle(t('ts.segments'), state.segments, (on) => { state.segments = on; build(); }),
      toggle(t('ts.maintenance'), state.maintenance, (on) => { state.maintenance = on; build(); }),
      button(t('common.exportPng'), () => ctx.exportPng(`${s.vehicle.name}-timeseries.png`, group.toCanvas(`${s.vehicle.name}`))));
    el.append(h('div', { class: 'ts-layout' }, picker, h('div', { class: 'ts-main' }, toolbar, h('div', { class: 'card chart-card' }, chartHost), stats)));
    group = new TimeChartGroup(chartHost);
    group.on('brush', (r) => { ctx.setRange(r, 'timeseries'); renderStats(); });
    group.on('domain', () => { if (!ctx.range) renderStatsSoon(); });
    if (ctx.range) group.brush = ctx.range;
    build();
    ctx.registerExport(t('export.timeseries'), () => group.toCanvas(s.vehicle.name));
  }

  let statsTimer = null;
  function renderStatsSoon() { clearTimeout(statsTimer); statsTimer = setTimeout(renderStats, 120); }

  return {
    el, refresh,
    onRange() { if (group && ctx.range !== group.brush && !(ctx.range && group.brush && ctx.range[0] === group.brush[0])) { group.brush = ctx.range; group.requestDraw(); } renderStats(); },
    jump(t0, t1) { pendingDomain = [t0, t1]; if (group) { group.setDomain(t0, t1); pendingDomain = null; } },
    destroy() { if (group) group.destroy(); },
  };
}
