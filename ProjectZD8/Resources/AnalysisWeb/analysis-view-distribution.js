// Distribution: histogram + box plot per channel, optionally split by segment type.
import { h, clear, fmt } from './analysis-dom.js';
import { HistogramChart } from './analysis-chart-bars.js';
import { theme } from './analysis-theme.js';
import { boxStats, histogram } from './analysis-stats.js';
import { SEGMENT_TYPES } from './analysis-segment.js';
import { button, card, checkbox, empty, select } from './analysis-ui.js';
import { CH, sliceChannel, usableChannels, valuesInSegments } from './analysis-model.js';

export function createDistributionView(ctx) {
  const el = h('div', { class: 'view distribution' });
  const st = { selected: null, bins: 30, split: false, useBrush: false };
  let charts = [];

  function refresh() {
    for (const c of charts) c.destroy();
    charts = [];
    clear(el);
    const s = ctx.primary;
    if (!s) { el.append(empty(ctx.t('common.noSession'))); return; }
    const t = ctx.t;
    const all = usableChannels(s);
    if (!st.selected || st.selected.some((id) => !s.channels.has(id))) st.selected = [CH.RPM, CH.SPEED, CH.LOAD].filter((id) => all.some((c) => c.id === id)).slice(0, 2);
    const controls = h('div', { class: 'controls' },
      select(t('dist.bins'), [15, 30, 60, 100].map((v) => ({ value: v, label: String(v) })), st.bins, (v) => { st.bins = Number(v); refresh(); }),
      checkbox(t('dist.split'), st.split, (on) => { st.split = on; refresh(); }),
      checkbox(t('dist.brushOnly'), st.useBrush, (on) => { st.useBrush = on; refresh(); }));
    const chips = h('div', { class: 'chips' }, all.map((c) => checkbox(c.name, st.selected.includes(c.id), (on) => {
      st.selected = on ? [...st.selected, c.id] : st.selected.filter((id) => id !== c.id);
      refresh();
    })));
    el.append(card(t('view.distribution'), [controls, chips], null, 'wide'));
    const range = st.useBrush && ctx.range ? ctx.range : null;
    for (const id of st.selected) {
      const channel = s.channels.get(id);
      if (!channel) continue;
      const base = range ? sliceChannel(channel, range[0], range[1]) : channel;
      const host = h('div', { class: 'chart-host dist-host' });
      const series = [];
      if (st.split) {
        const lo = finiteMin(base.values), hi = finiteMax(base.values);
        SEGMENT_TYPES.forEach((type, i) => {
          const values = valuesInSegments({ times: base.times, values: base.values }, s.segments, [type]);
          if (values.length < 5) return;
          series.push({ label: t(`segment.${type}`), color: theme().segment[type], hist: histogram(values, { bins: st.bins, min: lo, max: hi }), box: boxStats(values) });
        });
      } else {
        series.push({ label: channel.name, color: theme().accent, hist: histogram(base.values, { bins: st.bins }), box: boxStats(base.values) });
      }
      const b = boxStats(base.values);
      const summary = h('p', { class: 'meta', text: t('dist.summary', { n: b.n, median: fmt(b.median), q1: fmt(b.q1), q3: fmt(b.q3), out: b.outliers }) });
      const chart = new HistogramChart(host);
      chart.setData({ series, unit: channel.unit });
      charts.push(chart);
      const legend = series.length > 1 ? h('div', { class: 'seg-legend' }, series.map((x) => h('span', { class: 'seg-chip' }, h('i', { style: { background: x.color } }), x.label))) : null;
      el.append(card(`${channel.name}${channel.unit ? ' [' + channel.unit + ']' : ''}`, [host, legend, summary],
        [button(t('common.exportPng'), () => ctx.exportPng(`${s.vehicle.name}-${id}-distribution.png`, chart.toCanvas()))]));
      ctx.registerExport(`${t('export.distribution')} ${channel.name}`, () => chart.toCanvas());
    }
  }

  return { el, refresh, onRange() { if (st.useBrush) refresh(); }, destroy() { for (const c of charts) c.destroy(); } };
}

function finiteMin(values) { let m = Infinity; for (const v of values) if (v < m) m = v; return m; }
function finiteMax(values) { let m = -Infinity; for (const v of values) if (v > m) m = v; return m; }
