// Derived channels: built-ins and a safe expression editor (own parser; no eval).
import { h, clear, fmt } from './analysis-dom.js';
import { TimeChartGroup } from './analysis-chart-time.js';
import { builtinAvailable, BUILTIN_DERIVED, sessionExtent } from './analysis-model.js';
import { STANDARD_ALIASES } from './analysis-expr.js';
import { button, card, checkbox, empty, table } from './analysis-ui.js';
import { seriesColor } from './analysis-theme.js';

export function createDerivedView(ctx) {
  const el = h('div', { class: 'view derived' });
  let group = null;
  let errors = {};
  let draft = { name: '', unit: '', source: '', tolerance: 1 };
  let message = null;

  function toggleBuiltin(session, key, on) {
    session.derivedDefs = session.derivedDefs.filter((d) => !(d.kind === 'builtin' && d.key === key));
    if (on) session.derivedDefs.push({ kind: 'builtin', key });
    errors = ctx.rebuildDerived();
  }

  function addCustom(session) {
    const source = draft.source.trim();
    if (!draft.name.trim() || !source) { message = { kind: 'error', text: ctx.t('derived.needNameAndExpr') }; refresh(); return; }
    const id = `d-x${Date.now().toString(36)}`;
    session.derivedDefs.push({ kind: 'expression', id, name: draft.name.trim(), unit: draft.unit.trim(), source, tolerance: draft.tolerance });
    errors = ctx.rebuildDerived();
    if (errors[id]) {
      message = { kind: 'error', text: describeError(errors[id]) };
      session.derivedDefs = session.derivedDefs.filter((d) => d.id !== id);
      errors = ctx.rebuildDerived();
    } else {
      message = { kind: 'ok', text: ctx.t('derived.added', { name: draft.name.trim() }) };
      draft = { name: '', unit: '', source: '', tolerance: 1 };
    }
    refresh();
  }

  function describeError(error) {
    const key = `derived.error.${error.code}`;
    const text = ctx.t(key, { detail: error.detail ?? '', position: error.position ?? 0 });
    return text === key ? ctx.t('derived.error.generic') : text;
  }

  function refresh() {
    if (group) { group.destroy(); group = null; }
    clear(el);
    const s = ctx.primary;
    if (!s) { el.append(empty(ctx.t('common.noSession'))); return; }
    const t = ctx.t;
    const builtins = BUILTIN_DERIVED.map((b) => {
      const available = builtinAvailable(s, b);
      const on = s.derivedDefs.some((d) => d.kind === 'builtin' && d.key === b.key);
      const box = checkbox(`${t(`derived.${b.key}.name`)} — ${t(`derived.${b.key}.desc`)}`, on, (v) => { toggleBuiltin(s, b.key, v); refresh(); });
      box.querySelector('input').disabled = !available;
      return h('div', { class: 'builtin' }, box, !available ? h('small', { class: 'muted', text: t('derived.needs', { channels: b.requires.join(', ') }) }) : null,
        errors[b.key] ? h('small', { class: 'error', text: describeError(errors[b.key]) }) : null);
    });
    el.append(card(t('derived.builtins'), builtins));

    const nameInput = h('input', { type: 'text', value: draft.name, placeholder: t('derived.name'), oninput: (e) => { draft.name = e.target.value; } });
    const unitInput = h('input', { type: 'text', value: draft.unit, placeholder: t('derived.unit'), class: 'short', oninput: (e) => { draft.unit = e.target.value; } });
    const exprInput = h('textarea', { rows: 3, spellcheck: 'false', placeholder: 'ltft + stft', oninput: (e) => { draft.source = e.target.value; } });
    exprInput.value = draft.source;
    const aliases = Object.entries(STANDARD_ALIASES).map(([k, v]) => h('code', { title: v, text: k }));
    const customs = s.derivedDefs.filter((d) => d.kind === 'expression');
    const editor = [
      h('div', { class: 'controls' }, h('label', { class: 'field' }, h('span', { text: t('derived.name') }), nameInput), h('label', { class: 'field' }, h('span', { text: t('derived.unit') }), unitInput)),
      h('label', { class: 'field wide' }, h('span', { text: t('derived.expression') }), exprInput),
      h('div', { class: 'controls' }, button(t('derived.add'), () => addCustom(s), { primary: true })),
      message ? h('p', { class: message.kind === 'error' ? 'error' : 'ok', text: message.text }) : null,
      h('p', { class: 'hint' }, t('derived.syntax'), ' ', aliases.flatMap((a) => [a, ' '])),
      customs.length ? table([t('derived.name'), t('derived.expression'), ''], customs.map((d) => [d.name, h('code', { text: d.source }),
        button(t('common.remove'), () => { s.derivedDefs = s.derivedDefs.filter((x) => x !== d); errors = ctx.rebuildDerived(); refresh(); })])) : null,
    ];
    el.append(card(t('derived.editor'), editor));

    const derived = [...s.channels.values()].filter((c) => c.derived);
    if (s.gearInfo && s.gearInfo.gears.length) {
      el.append(card(t('derived.gears'), table([t('derived.gear'), t('derived.ratio'), t('derived.share')], s.gearInfo.gears.map((g) => [String(g.gear), fmt(g.ratio, 1), `${fmt((g.count / s.gearInfo.assignment.length) * 100, 0)} %`]))));
    }
    if (derived.length) {
      const host = h('div', { class: 'chart-host stack' });
      el.append(card(t('derived.preview'), host, null, 'wide'));
      group = new TimeChartGroup(host);
      group.setPanels(derived.map((c, i) => ({ id: c.id, title: c.name, unit: c.unit, height: 120, series: [{ label: c.name, unit: c.unit, times: c.times, values: c.values, color: seriesColor(i), points: c.id === 'd-gear', markersOnly: c.id === 'd-gear' }] })), sessionExtent(s));
      ctx.registerExport(t('export.derived'), () => group.toCanvas(t('view.derived')));
    }
  }

  return { el, refresh, onRange() {}, destroy() { if (group) group.destroy(); } };
}
