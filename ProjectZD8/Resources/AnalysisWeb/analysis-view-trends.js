// Vehicle trends: long-term per-session aggregates with maintenance markers.
import { h, clear, fmt, formatDate } from './analysis-dom.js';
import { TimeChartGroup } from './analysis-chart-time.js';
import { theme } from './analysis-theme.js';
import { button, card, checkbox, empty, segmented, select } from './analysis-ui.js';
import { niceTicks } from './analysis-stats.js';

const DAY = 86400;

export function createTrendsView(ctx) {
  const el = h('div', { class: 'view trends' });
  const st = { channel: null, condition: 'warmIdle', includeDemo: false, requested: false, axis: 'date' };
  let group = null;

  function refresh() {
    if (group) { group.destroy(); group = null; }
    clear(el);
    const t = ctx.t;
    const trend = ctx.trend;
    if (!trend) {
      if (!st.requested) { st.requested = true; ctx.host.requestTrend(st.includeDemo); if (ctx.trend) return; }
      el.append(card(t('view.trends'), h('p', { class: 'hint', text: t('trends.loading') })));
      return;
    }
    if (!st.channel || !trend.channels.some((c) => c.id === st.channel)) st.channel = trend.channels[0] ? trend.channels[0].id : null;
    const controls = h('div', { class: 'controls' },
      select(t('trends.channel'), trend.channels.map((c) => ({ value: c.id, label: `${c.name} [${c.unit}]` })), st.channel, (v) => { st.channel = v; refresh(); }),
      segmented([{ value: 'all', label: t('trends.all') }, { value: 'warmIdle', label: t('trends.warmIdle') }, { value: 'steadyCruise', label: t('trends.steadyCruise') }], st.condition, (v) => { st.condition = v; refresh(); }),
      segmented([{ value: 'date', label: t('trends.byDate') }, { value: 'odometer', label: t('trends.byOdometer') }], st.axis, (v) => { st.axis = v; refresh(); }),
      checkbox(t('trends.includeDemo'), st.includeDemo, (on) => { st.includeDemo = on; ctx.host.requestTrend(on); }),
      button(t('common.exportPng'), () => ctx.exportPng(`${trend.vehicle.name}-trend.png`, group.toCanvas(trend.vehicle.name))));
    const notes = [];
    if (trend.skippedCloudOnlySessions) notes.push(t('trends.skipped', { n: trend.skippedCloudOnlySessions }));
    if (trend.excludedDemoSessions) notes.push(t('trends.excludedDemo', { n: trend.excludedDemoSessions }));
    const host = h('div', { class: 'chart-host trend-host' });
    el.append(card(`${t('view.trends')} — ${trend.vehicle.name}`, [controls, notes.length ? h('p', { class: 'meta', text: notes.join(' · ') }) : null, host], null, 'wide'));
    if (!st.channel) { host.append(empty(t('trends.noData'))); return; }

    const rows = trend.sessions.map((s) => ({ s, stat: s.stats.find((x) => x.channelId === st.channel && x.condition === st.condition) })).filter((r) => r.stat);
    if (rows.length === 0) { host.append(empty(t('trends.noData'))); return; }
    const channel = trend.channels.find((c) => c.id === st.channel);
    const byOdometer = st.axis === 'odometer' && rows.every((r) => r.s.odometerStartKilometers !== null && r.s.odometerStartKilometers !== undefined);
    const x = byOdometer ? rows.map((r) => r.s.odometerStartKilometers) : rows.map((r) => Date.parse(r.s.startedAt) / 1000);
    const origin = x[0];
    const toX = byOdometer ? (v) => v : (v) => v;
    const times = Float64Array.from(x.map(toX));
    const median = Float64Array.from(rows.map((r) => r.stat.median));
    const lo = Float64Array.from(rows.map((r) => r.stat.p05));
    const hi = Float64Array.from(rows.map((r) => r.stat.p95));
    // maintenance markers: by date, or placed at the odometer reading when charting by distance
    const markers = trend.maintenance.map((m) => ({
      x: byOdometer ? m.odometerKilometers : Date.parse(m.date) / 1000, label: m.title, color: theme().warn,
    })).filter((m) => Number.isFinite(m.x));
    const span = Math.max(times[times.length - 1] - times[0], byOdometer ? 100 : 30 * DAY);
    group = new TimeChartGroup(host, {
      minSpan: byOdometer ? 50 : DAY,
      xFormat: byOdometer ? (v) => `${Math.round(v)} km` : (v, precise) => (precise ? formatDate(v * 1000, ctx.lang) : new Date(v * 1000).toLocaleDateString(ctx.lang, { month: 'short', year: '2-digit' })),
      ticks: byOdometer ? (a, b, n) => niceTicks(a, b, n) : dateTicks,
    });
    group.setPanels([{ id: 'trend', title: `${channel.name} — ${t(`trends.${st.condition}`)}`, unit: channel.unit, height: 280, markers,
      series: [{ label: channel.name, unit: channel.unit, times, values: median, band: { lo, hi }, points: true, color: theme().accent, gapSeconds: Infinity,
        lineWidth: 1.6 }] }], [times[0] - span * 0.04, times[times.length - 1] + span * 0.04]);
    ctx.registerExport(t('export.trend'), () => group.toCanvas(trend.vehicle.name));
    void origin;
  }

  return { el, refresh, onRange() {}, destroy() { if (group) group.destroy(); } };
}

/** Date ticks at month or week granularity depending on the span (values are epoch seconds). */
function dateTicks(a, b, count) {
  const span = b - a;
  const step = span > 200 * DAY ? 30 * DAY : span > 60 * DAY ? 14 * DAY : span > 20 * DAY ? 7 * DAY : DAY;
  const ticks = [];
  for (let v = Math.ceil(a / step) * step; v <= b; v += step) ticks.push(v);
  return ticks.length > count * 2 ? ticks.filter((_, i) => i % 2 === 0) : ticks;
}
