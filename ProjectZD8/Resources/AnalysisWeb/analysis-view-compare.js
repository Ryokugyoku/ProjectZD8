// Compare: overlay distributions and per-condition statistics of up to 3 sessions.
import { h, clear, fmt, formatDate } from './analysis-dom.js';
import { HistogramChart } from './analysis-chart-bars.js';
import { TimeChartGroup } from './analysis-chart-time.js';
import { boxStats, histogram, summarize } from './analysis-stats.js';
import { SEGMENT_TYPES } from './analysis-segment.js';
import { button, card, channelSelect, empty, table } from './analysis-ui.js';
import { CH, channelOf, valuesInSegments } from './analysis-model.js';
import { theme } from './analysis-theme.js';

export function createCompareView(ctx) {
  const el = h('div', { class: 'view compare' });
  const st = { channel: null, bins: 40 };
  let hist = null, group = null;

  function commonChannels() {
    const first = ctx.sessions[0];
    if (!first) return [];
    return first.order.map((id) => first.channels.get(id)).filter((c) => c.times.length > 0 && !c.derived && ctx.sessions.every((s) => channelOf(s, c.id)));
  }

  function refresh() {
    if (hist) { hist.destroy(); hist = null; }
    if (group) { group.destroy(); group = null; }
    clear(el);
    const t = ctx.t;
    if (ctx.sessions.length === 0) { el.append(empty(t('common.noSession'))); return; }
    const channels = commonChannels();
    if (!st.channel || !channels.some((c) => c.id === st.channel)) st.channel = (channels.find((c) => c.id === CH.RPM) || channels[0] || {}).id || null;
    const head = h('div', { class: 'controls' },
      channels.length ? channelSelect(t('compare.channel'), channels, st.channel, (v) => { st.channel = v; refresh(); }) : null,
      ctx.sessions.length < 3 ? button(t('compare.add'), () => ctx.host.requestSession(), { primary: true }) : h('span', { class: 'muted', text: t('compare.limit') }));
    el.append(card(t('view.compare'), [head, ctx.sessions.length < 2 ? h('p', { class: 'hint', text: t('compare.needTwo') }) : null,
      h('div', { class: 'seg-legend' }, ctx.sessions.map((s, i) => h('span', { class: 'seg-chip' }, h('i', { style: { background: theme().series[i] } }), `${s.vehicle.name} · ${formatDate(s.startedAtMs, ctx.lang)}`)))], null, 'wide'));
    if (!st.channel) { el.append(empty(t('compare.noCommon'))); return; }
    const first = channelOf(ctx.sessions[0], st.channel);

    // overlaid distribution on a shared axis
    let lo = Infinity, hi = -Infinity;
    for (const s of ctx.sessions) { const c = channelOf(s, st.channel); lo = Math.min(lo, c.min); hi = Math.max(hi, c.max); }
    const histHost = h('div', { class: 'chart-host dist-host' });
    el.append(card(`${t('compare.distribution')} — ${first.name}`, histHost, [button(t('common.exportPng'), () => ctx.exportPng('compare-distribution.png', hist.toCanvas()))]));
    hist = new HistogramChart(histHost);
    hist.setData({ unit: first.unit, series: ctx.sessions.map((s, i) => {
      const c = channelOf(s, st.channel);
      return { label: `${i + 1}. ${formatDate(s.startedAtMs, ctx.lang)}`, color: theme().series[i], hist: histogram(c.values, { bins: st.bins, min: lo, max: hi }), box: boxStats(c.values) };
    }) });
    ctx.registerExport(t('export.compareDistribution'), () => hist.toCanvas());

    // per-condition statistics
    const rows = [];
    ctx.sessions.forEach((s, i) => {
      const c = channelOf(s, st.channel);
      const conditions = [['all', t('compare.all'), c.values], ...SEGMENT_TYPES.map((type) => [type, t(`segment.${type}`), valuesInSegments(c, s.segments, [type])])];
      for (const [, label, values] of conditions) {
        if (values.length === 0) continue;
        const stats = summarize(Float64Array.from({ length: values.length }, (_, k) => k), values);
        rows.push([h('span', {}, h('i', { class: 'dot', style: { background: theme().series[i] } }), ` ${i + 1} · ${label}`), String(stats.n), fmt(stats.mean), fmt(stats.median), fmt(stats.p05), fmt(stats.p95), fmt(stats.std)]);
      }
    });
    el.append(card(t('compare.conditions'), table(['', 'n', t('stat.mean'), t('stat.median'), 'p05', 'p95', t('stat.std')], rows)));

    // time series aligned at the start of each session
    const host = h('div', { class: 'chart-host stack' });
    el.append(card(t('compare.overlay'), host, null, 'wide'));
    group = new TimeChartGroup(host);
    const extent = [0, Math.max(...ctx.sessions.map((s) => channelOf(s, st.channel).times.at(-1)))];
    group.setPanels([{ id: 'cmp', title: first.name, unit: first.unit, height: 200, series: ctx.sessions.map((s, i) => {
      const c = channelOf(s, st.channel);
      return { label: `${i + 1}`, unit: c.unit, times: c.times, values: c.values, color: theme().series[i] };
    }) }], extent);
    ctx.registerExport(t('export.compareOverlay'), () => group.toCanvas(first.name));
  }

  return { el, refresh, onRange() {}, destroy() { if (hist) hist.destroy(); if (group) group.destroy(); } };
}
