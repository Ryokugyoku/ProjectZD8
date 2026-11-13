// Map table: 2-D binned grid (e.g. RPM x load) as occupancy time or the mean of a third channel.
import { h, clear, fmt } from './analysis-dom.js';
import { HeatmapChart } from './analysis-chart-heat.js';
import { binGrid } from './analysis-binning.js';
import { joinXYZ, sampleWeights } from './analysis-join.js';
import { button, card, channelSelect, empty, select } from './analysis-ui.js';
import { CH, channelOf, usableChannels } from './analysis-model.js';
import { percentileSorted, sortedFinite } from './analysis-stats.js';

export function createMapTableView(ctx) {
  const el = h('div', { class: 'view maptable' });
  const st = { x: null, y: null, z: '', nx: 12, ny: 10, tolerance: 0.5 };
  let chart = null;
  const info = h('p', { class: 'meta' });

  function defaults(s) {
    const ids = usableChannels(s).map((c) => c.id);
    const pick = (...c) => c.find((id) => ids.includes(id)) || ids[0] || null;
    if (!st.x || !s.channels.has(st.x)) st.x = pick(CH.RPM);
    if (!st.y || !s.channels.has(st.y)) st.y = pick(CH.LOAD, CH.THROTTLE, CH.MAP);
    if (st.z && !s.channels.has(st.z)) st.z = '';
  }

  function update() {
    const s = ctx.primary;
    if (!s || !chart) return;
    const x = channelOf(s, st.x), y = channelOf(s, st.y);
    if (!x || !y) { info.textContent = ctx.t('common.noData'); return; }
    const z = st.z ? channelOf(s, st.z) : null;
    const joined = joinXYZ(x, y, z, st.tolerance);
    const weights = sampleWeights(joined.t);
    const bounds = (values) => { const sorted = sortedFinite(values); return [percentileSorted(sorted, 0.005), percentileSorted(sorted, 0.995)]; };
    let [xMin, xMax] = bounds(joined.x), [yMin, yMax] = bounds(joined.y);
    if (!(xMax > xMin)) { xMin -= 1; xMax += 1; }
    if (!(yMax > yMin)) { yMin -= 1; yMax += 1; }
    const grid = binGrid({ xs: joined.x, ys: joined.y, zs: z ? joined.z : null, weights, xMin, xMax, yMin, yMax, nx: st.nx, ny: st.ny });
    const mode = z ? 'mean' : 'occupancy';
    chart.setData(grid, { mode, xLabel: x.name, yLabel: y.name, zLabel: z ? z.name : '', xUnit: x.unit, yUnit: y.unit, zUnit: z ? z.unit : '', occupancyLabel: ctx.t('map.occupancy') });
    info.textContent = ctx.t('map.info', { n: grid.total, total: joined.n, seconds: fmt(weights.reduce((a, b) => a + b, 0), 0) });
  }

  function refresh() {
    clear(el);
    if (chart) { chart.destroy(); chart = null; }
    const s = ctx.primary;
    if (!s) { el.append(empty(ctx.t('common.noSession'))); return; }
    defaults(s);
    const t = ctx.t;
    const channels = usableChannels(s);
    const bins = (name, key, values) => select(name, values.map((v) => ({ value: v, label: String(v) })), st[key], (v) => { st[key] = Number(v); update(); });
    const controls = h('div', { class: 'controls' },
      channelSelect(t('map.x'), channels, st.x, (v) => { st.x = v; update(); }),
      channelSelect(t('map.y'), channels, st.y, (v) => { st.y = v; update(); }),
      channelSelect(t('map.z'), channels, st.z, (v) => { st.z = v; update(); }, { allowNone: true, noneLabel: t('map.occupancyOption') }),
      bins(t('map.nx'), 'nx', [8, 12, 16, 24, 32]), bins(t('map.ny'), 'ny', [6, 10, 14, 20, 28]),
      button(t('common.exportPng'), () => ctx.exportPng(`${s.vehicle.name}-map.png`, chart.toCanvas())));
    const host = h('div', { class: 'chart-host map-host' });
    el.append(card(t('view.maptable'), [controls, info, host], null, 'wide'));
    chart = new HeatmapChart(host);
    update();
    ctx.registerExport(t('export.map'), () => chart.toCanvas());
  }

  return { el, refresh, onRange() {}, destroy() { if (chart) chart.destroy(); } };
}
