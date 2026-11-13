// Reusable UI building blocks for the views.
import { h, fmt } from './analysis-dom.js';

/** Titled card with optional action buttons. */
export function card(title, body, actions = null, className = '') {
  return h('section', { class: `card ${className}` },
    h('header', { class: 'card-head' }, h('h3', { text: title }), actions ? h('div', { class: 'card-actions' }, actions) : null),
    h('div', { class: 'card-body' }, body));
}

/** Button. */
export function button(label, onClick, { primary = false, title = '', disabled = false, pressed = null } = {}) {
  const b = h('button', { class: `btn${primary ? ' primary' : ''}`, type: 'button', title: title || label, onclick: onClick, 'aria-pressed': pressed === null ? null : String(pressed) }, label);
  if (disabled) b.disabled = true;
  return b;
}

/** Toggle button that keeps its own state. */
export function toggle(label, initial, onChange) {
  let on = initial;
  const b = button(label, () => { on = !on; b.setAttribute('aria-pressed', String(on)); onChange(on); }, { pressed: on });
  return b;
}

/** Labelled select. options: [{ value, label }]. */
export function select(label, options, value, onChange) {
  const el = h('select', { onchange: (e) => onChange(e.target.value) },
    options.map((o) => h('option', { value: o.value, text: o.label, selected: String(o.value) === String(value) })));
  return h('label', { class: 'field' }, h('span', { text: label }), el);
}

/** Select of channels of a session. `allowNone` adds an empty option labelled `noneLabel`. */
export function channelSelect(label, channels, value, onChange, { allowNone = false, noneLabel = '' } = {}) {
  const options = channels.map((c) => ({ value: c.id, label: c.unit ? `${c.name} [${c.unit}]` : c.name }));
  if (allowNone) options.unshift({ value: '', label: noneLabel });
  return select(label, options, value ?? '', onChange);
}

/** Checkbox. */
export function checkbox(label, checked, onChange) {
  const input = h('input', { type: 'checkbox', onchange: (e) => onChange(e.target.checked) });
  input.checked = checked;
  return h('label', { class: 'check' }, input, h('span', { text: label }));
}

/** Segmented control. items: [{ value, label }]. */
export function segmented(items, value, onChange) {
  const root = h('div', { class: 'segmented', role: 'group' });
  const buttons = items.map((item) => {
    const b = h('button', { type: 'button', class: 'seg', 'aria-pressed': String(item.value === value), text: item.label, onclick: () => {
      for (const other of buttons) other.setAttribute('aria-pressed', 'false');
      b.setAttribute('aria-pressed', 'true');
      onChange(item.value);
    } });
    root.append(b);
    return b;
  });
  return root;
}

/** Table from header labels and row arrays (strings or nodes). */
export function table(headers, rows, className = '') {
  return h('div', { class: 'table-wrap' }, h('table', { class: `tbl ${className}` },
    h('thead', {}, h('tr', {}, headers.map((x) => h('th', { text: x })))),
    h('tbody', {}, rows.map((r) => h('tr', {}, r.map((c, i) => h('td', { class: i === 0 ? 'first' : 'num' }, c)))))));
}

/** Small KPI tile. */
export function kpi(label, value, unit = '', tone = '') {
  return h('div', { class: `kpi ${tone}` }, h('div', { class: 'kpi-label', text: label }), h('div', { class: 'kpi-value' }, h('span', { text: value }), unit ? h('small', { text: ` ${unit}` }) : null));
}

/** Empty-state message. */
export function empty(text) {
  return h('div', { class: 'empty', text });
}

/** Stat row cells for the standard summary. */
export function statCells(s) {
  return [String(s.n), fmt(s.min), fmt(s.max), fmt(s.mean), fmt(s.median), fmt(s.p05), fmt(s.p95), fmt(s.std), fmt(s.slope)];
}
