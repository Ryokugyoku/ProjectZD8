// Export: CSV of selected channels / range and PNG of any chart that has been drawn.
import { h, clear } from './analysis-dom.js';
import { buildCsv } from './analysis-csv.js';
import { button, card, checkbox, empty, segmented } from './analysis-ui.js';
import { usableChannels } from './analysis-model.js';

export function createExportView(ctx) {
  const el = h('div', { class: 'view export' });
  const st = { selected: null, scope: 'all' };

  function refresh() {
    clear(el);
    const s = ctx.primary;
    const t = ctx.t;
    if (!s) { el.append(empty(t('common.noSession'))); return; }
    const all = usableChannels(s);
    if (!st.selected) st.selected = all.filter((c) => !c.derived).map((c) => c.id);
    st.selected = st.selected.filter((id) => s.channels.has(id));
    const range = ctx.range;
    const rangeText = range ? t('export.rangeBrush', { from: range[0].toFixed(1), to: range[1].toFixed(1) }) : t('export.rangeNone');
    const list = h('div', { class: 'chips' }, all.map((c) => checkbox(`${c.name}${c.unit ? ' [' + c.unit + ']' : ''}`, st.selected.includes(c.id), (on) => {
      st.selected = on ? [...st.selected, c.id] : st.selected.filter((id) => id !== c.id);
    })));
    const scope = segmented([{ value: 'all', label: t('export.scopeAll') }, { value: 'brush', label: t('export.scopeBrush') }], st.scope, (v) => { st.scope = v; });
    const doCsv = () => {
      const channels = st.selected.map((id) => s.channels.get(id)).filter(Boolean);
      const [t0, t1] = st.scope === 'brush' && ctx.range ? ctx.range : [-Infinity, Infinity];
      const text = buildCsv(channels, t0, t1);
      const stamp = new Date(s.startedAtMs).toISOString().slice(0, 16).replace(/[:T]/g, '-');
      ctx.exportCsv(`${s.vehicle.name}-${stamp}.csv`, text);
    };
    el.append(card(t('export.csv'), [
      h('p', { class: 'hint', text: t('export.csvHint') }), list,
      h('div', { class: 'controls' }, scope, h('span', { class: 'muted', text: rangeText }),
        h('div', { class: 'btn-row' }, button(t('export.all'), () => { st.selected = all.map((c) => c.id); refresh(); }), button(t('export.none'), () => { st.selected = []; refresh(); }))),
      h('div', { class: 'controls' }, button(t('export.downloadCsv'), doCsv, { primary: true, disabled: st.selected.length === 0 }))], null, 'wide'));
    const items = [...ctx.exportables.entries()];
    el.append(card(t('export.png'), items.length
      ? h('ul', { class: 'events plain' }, items.map(([label, get]) => h('li', {}, h('span', { class: 'event-type', text: label }), button(t('export.savePng'), () => ctx.exportPng(`${s.vehicle.name}-${label}.png`, get())))))
      : h('p', { class: 'muted', text: t('export.noCharts') })));
  }

  return { el, refresh, onRange() { refresh(); }, destroy() {} };
}
