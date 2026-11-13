// Overview: KPIs, drive timeline with detected segments, events that jump to the moment.
import { h, clear, fmt, formatClock, formatDuration, formatDate } from './analysis-dom.js';
import { TimeChartGroup } from './analysis-chart-time.js';
import { theme, withAlpha } from './analysis-theme.js';
import { SEGMENT_TYPES, segmentTotals } from './analysis-segment.js';
import { card, empty, kpi } from './analysis-ui.js';
import { CH, channelOf, sessionExtent } from './analysis-model.js';
import { summarize } from './analysis-stats.js';

/** Distance in km by integrating speed over consecutive samples at most 3 s apart. */
export function integrateDistance(speed) {
  let km = 0;
  for (let i = 1; i < speed.times.length; i++) {
    const dt = speed.times[i] - speed.times[i - 1];
    if (dt > 0 && dt <= 3) km += ((speed.values[i] + speed.values[i - 1]) / 2 / 3600) * dt;
  }
  return km;
}

export function createOverviewView(ctx) {
  const el = h('div', { class: 'view overview' });
  let group = null;

  function refresh() {
    if (group) { group.destroy(); group = null; }
    clear(el);
    const s = ctx.primary;
    const t = ctx.t;
    if (!s) { el.append(empty(t('common.noSession'))); return; }
    const speed = channelOf(s, CH.SPEED), rpm = channelOf(s, CH.RPM), coolant = channelOf(s, CH.COOLANT), load = channelOf(s, CH.LOAD);
    const distance = s.info.distanceKilometers ?? (speed ? integrateDistance(speed) : null);
    const speedStats = speed ? summarize(speed.times, speed.values) : null;
    const responseRate = s.info.sampleCount > 0 ? (s.info.respondedCount / s.info.sampleCount) * 100 : NaN;
    const gapSeconds = s.gaps.reduce((sum, g) => sum + (g.endSeconds - g.startSeconds), 0);
    const lastService = s.maintenance.filter((m) => m.dateMs <= s.startedAtMs).sort((a, b) => b.dateMs - a.dateMs)[0];
    const tiles = [
      kpi(t('overview.duration'), formatDuration(s.durationSeconds)),
      kpi(t('overview.distance'), distance === null ? '—' : fmt(distance, 1), 'km'),
      kpi(t('overview.maxSpeed'), speedStats ? fmt(speedStats.max, 0) : '—', 'km/h'),
      kpi(t('overview.avgSpeed'), speed ? fmt(movingAverage(speed), 0) : '—', 'km/h'),
      kpi(t('overview.maxRpm'), rpm ? fmt(rpm.max, 0) : '—', 'rpm', rpm && rpm.max > 6500 ? 'warn' : ''),
      kpi(t('overview.coolantMax'), coolant ? fmt(coolant.max, 0) : '—', '°C', coolant && coolant.max > 105 ? 'warn' : ''),
      kpi(t('overview.avgLoad'), load ? fmt(summarize(load.times, load.values).mean, 0) : '—', '%'),
      kpi(t('overview.responseRate'), fmt(responseRate, 1), '%', responseRate < 90 ? 'warn' : ''),
      kpi(t('overview.channels'), String(s.order.filter((id) => !s.channels.get(id).derived && s.channels.get(id).times.length).length)),
      kpi(t('overview.gaps'), `${s.gaps.length}`, s.gaps.length ? `(${formatDuration(gapSeconds)})` : '', s.gaps.length ? 'warn' : ''),
    ];
    el.append(h('div', { class: 'kpis' }, tiles));
    el.append(h('p', { class: 'meta' },
      `${s.vehicle.name} · ${formatDate(s.startedAtMs, ctx.lang)} · ${s.info.adapterName}${s.info.isDemo ? ' · ' + t('common.demo') : ''}`,
      lastService ? h('span', {}, ` · ${t('overview.lastService', { title: lastService.title, days: Math.round((s.startedAtMs - lastService.dateMs) / 86400000) })}`) : null));

    // timeline
    const host = h('div', { class: 'chart-host timeline' });
    const totals = segmentTotals(s.segments);
    const sum = SEGMENT_TYPES.reduce((a, k) => a + totals[k], 0) || 1;
    const legend = h('div', { class: 'seg-legend' }, SEGMENT_TYPES.map((k) => h('span', { class: 'seg-chip' },
      h('i', { style: { background: theme().segment[k] } }), `${t(`segment.${k}`)} ${formatDuration(totals[k])} (${fmt((totals[k] / sum) * 100, 0)}%)`)));
    const bar = h('div', { class: 'seg-bar' }, SEGMENT_TYPES.map((k) => h('div', { style: { width: `${(totals[k] / sum) * 100}%`, background: theme().segment[k] }, title: t(`segment.${k}`) })));
    el.append(card(t('overview.timeline'), [host, bar, legend], null, 'wide'));
    group = new TimeChartGroup(host);
    const bands = s.segments.map((seg) => ({ x0: seg.t0, x1: seg.t1, color: withAlpha(theme().segment[seg.type], 0.2) }));
    const markers = s.events.map((e) => ({ x: e.t, color: e.severity === 'warn' ? theme().warn : theme().muted }));
    const panels = [];
    if (speed) panels.push({ id: 'speed', title: speed.name, series: [{ label: speed.name, unit: speed.unit, times: speed.times, values: speed.values, color: theme().accent }], bands, markers, height: 120 });
    if (rpm) panels.push({ id: 'rpm', title: rpm.name, series: [{ label: rpm.name, unit: rpm.unit, times: rpm.times, values: rpm.values, color: theme().series[1] }], bands, height: 100 });
    group.setPanels(panels, sessionExtent(s));
    ctx.registerExport(t('export.timeline'), () => group.toCanvas(`${s.vehicle.name} ${t('overview.timeline')}`));

    // events
    const list = h('ul', { class: 'events' }, s.events.length === 0 ? [h('li', { class: 'muted', text: t('overview.noEvents') })] : s.events.map((e) => {
      const unit = e.type === 'hardAcceleration' || e.type === 'hardBraking' ? 'm/s²' : e.type === 'highCoolant' ? '°C' : e.type === 'rpmPeak' ? 'rpm' : '%';
      return h('li', {}, h('button', { class: `event ${e.severity}`, type: 'button', onclick: () => ctx.jumpTo(Math.max(0, e.t - 15), e.tEnd + 15) },
        h('span', { class: 'event-type', text: t(`event.${e.type}`) }),
        h('span', { class: 'event-time', text: formatClock(e.t) }),
        h('span', { class: 'event-value', text: `${fmt(e.value, 1)} ${unit}` })));
    }));
    el.append(card(t('overview.events'), list));
    const maint = s.maintenance.length === 0 ? [h('li', { class: 'muted', text: t('overview.noMaintenance') })]
      : s.maintenance.slice().reverse().map((m) => h('li', {}, h('span', { class: 'event-type', text: m.title }), h('span', { class: 'event-time', text: formatDate(m.dateMs, ctx.lang) }),
        h('span', { class: 'event-value', text: m.odometerKilometers === null ? '' : `${fmt(m.odometerKilometers, 0)} km` })));
    el.append(card(t('overview.maintenance'), h('ul', { class: 'events plain' }, maint)));
  }

  return { el, refresh, onRange() {}, destroy() { if (group) group.destroy(); } };
}

function movingAverage(speed) {
  let sum = 0, n = 0;
  for (let i = 0; i < speed.values.length; i++) if (speed.values[i] > 1) { sum += speed.values[i]; n++; }
  return n ? sum / n : NaN;
}
