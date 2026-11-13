// Data quality: response rate per channel, sampling-interval histogram, gaps.
import { h, clear, fmt, formatClock, formatDuration } from './analysis-dom.js';
import { HistogramChart } from './analysis-chart-bars.js';
import { theme } from './analysis-theme.js';
import { histogram, medianInterval, percentileSorted } from './analysis-stats.js';
import { button, card, channelSelect, empty, table } from './analysis-ui.js';
import { usableChannels } from './analysis-model.js';

export function createQualityView(ctx) {
  const el = h('div', { class: 'view quality' });
  const st = { channel: null };
  let chart = null;

  function intervals(channel) {
    const out = [];
    for (let i = 1; i < channel.times.length; i++) out.push(channel.times[i] - channel.times[i - 1]);
    return out;
  }

  function refresh() {
    if (chart) { chart.destroy(); chart = null; }
    clear(el);
    const s = ctx.primary;
    const t = ctx.t;
    if (!s) { el.append(empty(t('common.noSession'))); return; }
    const measured = [...s.channels.values()].filter((c) => !c.derived && c.quality);
    const rows = measured.map((c) => {
      const q = c.quality;
      const rate = q.requested ? (q.responded / q.requested) * 100 : NaN;
      const bar = h('div', { class: 'rate' }, h('div', { class: `rate-fill${rate < 90 ? ' warn' : ''}`, style: { width: `${Number.isFinite(rate) ? rate : 0}%` } }), h('span', { text: `${fmt(rate, 1)}%` }));
      const hz = c.times.length > 1 ? 1 / medianInterval(c.times) : NaN;
      return [`${c.name}`, bar, String(q.requested), String(q.responded), String(q.noData), String(q.timedOut), String(q.failed), String(q.outOfRange + q.undecodable), `${fmt(hz, 1)} Hz`, c.isFast ? t('quality.fast') : t('quality.slow')];
    });
    el.append(card(t('quality.response'), table(['', t('quality.rate'), t('quality.requested'), t('quality.responded'), 'NO DATA', t('quality.timeout'), t('quality.failed'), t('quality.invalid'), t('quality.rateHz'), t('quality.group')], rows), null, 'wide'));

    const usable = usableChannels(s).filter((c) => c.times.length > 2);
    if (!st.channel || !s.channels.has(st.channel)) st.channel = usable[0] ? usable[0].id : null;
    if (st.channel) {
      const channel = s.channels.get(st.channel);
      const dts = intervals(channel).sort((a, b) => a - b);
      const cap = percentileSorted(dts, 0.99) || 1;
      const host = h('div', { class: 'chart-host dist-host' });
      const median = percentileSorted(dts, 0.5);
      el.append(card(t('quality.interval'), [
        h('div', { class: 'controls' }, channelSelect(t('quality.channel'), usable, st.channel, (v) => { st.channel = v; refresh(); }),
          button(t('common.exportPng'), () => ctx.exportPng('interval-histogram.png', chart.toCanvas()))),
        h('p', { class: 'meta', text: t('quality.intervalInfo', { median: fmt(median * 1000, 0), p99: fmt(cap * 1000, 0), max: fmt(dts[dts.length - 1] * 1000, 0) }) }),
        host]));
      chart = new HistogramChart(host);
      chart.setData({ unit: 's', series: [{ label: channel.name, color: theme().accent, hist: histogram(dts.filter((d) => d <= cap), { bins: 40 }), box: null }] });
      ctx.registerExport(t('export.interval'), () => chart.toCanvas());
    }
    const gapRows = s.gaps.map((g) => [formatClock(g.startSeconds), formatClock(g.endSeconds), formatDuration(g.endSeconds - g.startSeconds),
      button(t('quality.show'), () => ctx.jumpTo(Math.max(0, g.startSeconds - 10), g.endSeconds + 10))]);
    el.append(card(t('quality.gaps'), gapRows.length ? table([t('quality.from'), t('quality.to'), t('quality.length'), ''], gapRows) : h('p', { class: 'muted', text: t('quality.noGaps') })));
  }

  return { el, refresh, onRange() {}, destroy() { if (chart) chart.destroy(); } };
}
