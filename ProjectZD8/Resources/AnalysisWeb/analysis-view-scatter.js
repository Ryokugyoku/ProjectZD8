// XY scatter: any two channels joined by nearest time, colour by a third, density mode, regression with r^2.
import { h, clear, fmt } from './analysis-dom.js';
import { ScatterChart } from './analysis-chart-scatter.js';
import { button, card, channelSelect, checkbox, empty, select, toggle } from './analysis-ui.js';
import { CH, channelOf, usableChannels } from './analysis-model.js';
import { joinXYZ } from './analysis-join.js';
import { linearRegression } from './analysis-stats.js';

export function createScatterView(ctx) {
  const el = h('div', { class: 'view scatter' });
  const st = { x: null, y: null, z: '', tolerance: 0.5, density: false, regression: true, useBrush: false, gear: false };
  let chart = null;
  const info = h('p', { class: 'meta' });

  function defaults(s) {
    const ids = usableChannels(s).map((c) => c.id);
    const pick = (...c) => c.find((id) => ids.includes(id)) || ids[0] || null;
    if (!st.x || !s.channels.has(st.x)) st.x = pick(CH.RPM);
    if (!st.y || !s.channels.has(st.y)) st.y = pick(CH.LOAD, CH.THROTTLE, CH.SPEED);
    if (st.z && !s.channels.has(st.z)) st.z = '';
  }

  function update() {
    const s = ctx.primary;
    if (!s || !chart) return;
    const x = channelOf(s, st.x), y = channelOf(s, st.y);
    if (!x || !y) { chart.setData({ n: 0, x: new Float64Array(0), y: new Float64Array(0), z: new Float64Array(0) }, {}); info.textContent = ctx.t('common.noData'); return; }
    const gearChannel = st.gear ? channelOf(s, 'd-gear') : null;
    const z = gearChannel || (st.z ? channelOf(s, st.z) : null);
    const range = st.useBrush && ctx.range ? ctx.range : [-Infinity, Infinity];
    const joined = joinXYZ(x, y, z, st.tolerance, range[0], range[1]);
    const reg = st.regression ? linearRegression(joined.x, joined.y) : null;
    chart.setData(joined, {
      xLabel: x.name, yLabel: y.name, zLabel: gearChannel ? gearChannel.name : z ? z.name : '', xUnit: x.unit, yUnit: y.unit, zUnit: z ? z.unit : '',
      density: st.density, regression: reg, categorical: Boolean(gearChannel),
    });
    info.textContent = reg && Number.isFinite(reg.slope)
      ? ctx.t('scatter.info', { n: joined.n, slope: fmt(reg.slope), intercept: fmt(reg.intercept), r2: fmt(reg.r2, 3) })
      : ctx.t('scatter.infoN', { n: joined.n });
  }

  function refresh() {
    clear(el);
    if (chart) { chart.destroy(); chart = null; }
    const s = ctx.primary;
    if (!s) { el.append(empty(ctx.t('common.noSession'))); return; }
    defaults(s);
    const t = ctx.t;
    const channels = usableChannels(s);
    const controls = h('div', { class: 'controls' },
      channelSelect(t('scatter.x'), channels, st.x, (v) => { st.x = v; update(); }),
      channelSelect(t('scatter.y'), channels, st.y, (v) => { st.y = v; update(); }),
      channelSelect(t('scatter.color'), channels, st.z, (v) => { st.z = v; update(); }, { allowNone: true, noneLabel: t('common.none') }),
      select(t('scatter.tolerance'), [0.1, 0.25, 0.5, 1, 2].map((v) => ({ value: v, label: `${v} s` })), st.tolerance, (v) => { st.tolerance = Number(v); update(); }),
      toggle(t('scatter.density'), st.density, (on) => { st.density = on; update(); }),
      toggle(t('scatter.regression'), st.regression, (on) => { st.regression = on; update(); }),
      checkbox(t('scatter.brushOnly'), st.useBrush, (on) => { st.useBrush = on; update(); }),
      s.channels.has('d-gear') ? checkbox(t('scatter.colorGear'), st.gear, (on) => { st.gear = on; update(); }) : null,
      button(t('scatter.reset'), () => chart.reset()),
      button(t('common.exportPng'), () => ctx.exportPng(`${s.vehicle.name}-scatter.png`, chart.toCanvas())));
    const host = h('div', { class: 'chart-host scatter-host' });
    el.append(card(t('view.scatter'), [controls, info, host], null, 'wide'));
    chart = new ScatterChart(host);
    update();
    ctx.registerExport(t('export.scatter'), () => chart.toCanvas());
  }

  return { el, refresh, onRange() { if (st.useBrush) update(); }, destroy() { if (chart) chart.destroy(); } };
}
