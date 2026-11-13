// Synthetic datasets for standalone development (?demo=1). Deterministic per seed. No DOM access.

const NAMES = {
  ja: { '01-04': 'エンジン負荷', '01-05': '冷却水温', '01-06': '短期燃料補正', '01-07': '長期燃料補正', '01-0B': '吸気管圧力', '01-0C': 'エンジン回転数', '01-0D': '車速', '01-0F': '吸気温', '01-10': '吸入空気量', '01-11': 'スロットル開度' },
  en: { '01-04': 'Engine load', '01-05': 'Coolant temperature', '01-06': 'Short-term fuel trim', '01-07': 'Long-term fuel trim', '01-0B': 'Intake manifold pressure', '01-0C': 'Engine speed', '01-0D': 'Vehicle speed', '01-0F': 'Intake air temperature', '01-10': 'Mass air flow', '01-11': 'Throttle position' },
  es: { '01-04': 'Carga del motor', '01-05': 'Temperatura del refrigerante', '01-06': 'Ajuste de combustible a corto plazo', '01-07': 'Ajuste de combustible a largo plazo', '01-0B': 'Presión del colector', '01-0C': 'Régimen del motor', '01-0D': 'Velocidad del vehículo', '01-0F': 'Temperatura del aire de admisión', '01-10': 'Flujo de aire', '01-11': 'Posición del acelerador' },
};

const SPECS = [
  { id: '01-0C', unit: 'rpm', min: 0, max: 16383.75, fast: true },
  { id: '01-0D', unit: 'km/h', min: 0, max: 255, fast: true },
  { id: '01-04', unit: '%', min: 0, max: 100, fast: true },
  { id: '01-11', unit: '%', min: 0, max: 100, fast: true },
  { id: '01-10', unit: 'g/s', min: 0, max: 655.35, fast: true },
  { id: '01-0B', unit: 'kPa', min: 0, max: 255, fast: true },
  { id: '01-06', unit: '%', min: -100, max: 99.22, fast: true },
  { id: '01-05', unit: '°C', min: -40, max: 215, fast: false },
  { id: '01-0F', unit: '°C', min: -40, max: 215, fast: false },
  { id: '01-07', unit: '%', min: -100, max: 99.22, fast: false },
];

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const smooth = (x) => x * x * (3 - 2 * x);

/** Speed profile [duration s, target km/h] pairs. */
const PROFILE = [[30, 0], [15, 45], [40, 45], [15, 20], [10, 0], [20, 0], [5, 60], [60, 60], [25, 100], [300, 100], [6, 15], [25, 50], [40, 50], [15, 0], [25, 0], [20, 70], [100, 70], [15, 110], [200, 110], [40, 40], [20, 0], [40, 0], [25, 55], [120, 55], [30, 0], [60, 0]];

/**
 * Builds a dataset in the same shape the native app produces.
 * options: { seed, lang, rate (Hz of fast channels), variant (0 normal, 1 higher speeds, 2 overheating) }
 */
export function buildDemoDataset({ seed = 1, lang = 'en', rate = 10, variant = 0 } = {}) {
  const rand = mulberry32(seed * 7919 + variant * 104729);
  const gauss = () => Math.sqrt(-2 * Math.log(rand() || 1e-9)) * Math.cos(2 * Math.PI * rand());
  const dt = 1 / rate;
  const speedScale = variant === 1 ? 1.06 : 1;
  let total = 0;
  const knots = [];
  let previous = 0;
  for (const [duration, target] of PROFILE) { knots.push({ t0: total, t1: total + duration, from: previous, to: target * speedScale }); previous = target * speedScale; total += duration; }
  const duration = Math.min(total, 1500);
  const speedAt = (t) => {
    const k = knots.find((x) => t >= x.t0 && t < x.t1) || knots[knots.length - 1];
    const f = smooth(Math.min(Math.max((t - k.t0) / (k.t1 - k.t0), 0), 1));
    const wobble = k.to > 30 ? Math.sin(t / 7 + seed) * 1.2 + Math.sin(t / 2.3) * 0.5 : 0;
    return Math.max(0, k.from + (k.to - k.from) * f + wobble);
  };
  const ratios = [125, 70, 47, 36, 29, 24];
  const shiftSpeeds = [0, 14, 28, 44, 62, 84];
  const gearFor = (v) => { let g = 0; for (let i = 0; i < shiftSpeeds.length; i++) if (v >= shiftSpeeds[i]) g = i; return g; };
  const gaps = [{ startSeconds: 880, endSeconds: 891 }];
  const inGap = (t) => gaps.some((g) => t >= g.startSeconds && t < g.endSeconds);
  const coolantAt = (t) => {
    let c = 24 + 66 * (1 - Math.exp(-t / 260));
    if (variant === 2 && t > 1000 && t < 1080) c += 18 * Math.sin(((t - 1000) / 80) * Math.PI);
    return c;
  };
  const series = Object.fromEntries(SPECS.map((s) => [s.id, { times: [], values: [], q: { requested: 0, responded: 0, noData: 0, timedOut: 0, failed: 0, decoded: 0, undecodable: 0, outOfRange: 0 } }]));
  const record = (id, t, value) => {
    const s = series[id];
    s.q.requested++;
    const r = rand();
    if (inGap(t) || r < 0.012) { s.q.timedOut++; return; }
    if (r < 0.018) { s.q.noData++; return; }
    if (r < 0.02) { s.q.failed++; return; }
    s.q.responded++; s.q.decoded++;
    s.times.push(Math.round(t * 1000) / 1000);
    s.values.push(value);
  };
  for (let t = 0; t < duration; t += dt) {
    const exact = speedAt(t);
    const speed = Math.round(exact);
    const accel = (speedAt(t + 0.5) - speedAt(t - 0.5)) / 1;
    const idle = 800 + Math.max(0, 450 * Math.exp(-t / 90));
    const gear = gearFor(speed);
    const rpm = speed < 2 ? idle + gauss() * 12 : Math.max(idle, speed * ratios[gear] + gauss() * 15 + Math.max(accel, 0) * 4);
    const load = Math.min(95, Math.max(speed < 2 ? 18 + gauss() * 1.2 : accel < -1.5 ? 6 + gauss() : 16 + 0.18 * speed + 9 * Math.max(accel, 0) + gauss() * 1.8, 4));
    const throttle = Math.min(100, Math.max(load * 0.55 + gauss() * 1.2, 0));
    const stftBase = (t > 700 && t < 706) ? 24 + gauss() : gauss() * 3.4;
    const q4 = (x) => Math.round(x * 4) / 4;
    record('01-0C', t, q4(Math.min(rpm, 7200)));
    record('01-0D', t, speed);
    record('01-04', t, Math.round((load * 255) / 100) * 100 / 255);
    record('01-11', t, Math.round((throttle * 255) / 100) * 100 / 255);
    record('01-10', t, Math.round(((rpm / 1000) * (load / 100) * 38 + 2) * 100) / 100);
    record('01-0B', t, Math.round(28 + load * 0.75));
    record('01-06', t, Math.round(((stftBase + 100) * 128) / 100) * 100 / 128 - 100);
  }
  for (let t = 0; t < duration; t += 1) {
    record('01-05', t, Math.round(coolantAt(t) + gauss() * 0.3));
    record('01-0F', t, Math.round(29 + 0.02 * t / 10 + gauss() * 0.4));
    record('01-07', t, Math.round(((-2 + t / 600 + gauss() * 0.15 + 100) * 128) / 100) * 100 / 128 - 100);
  }
  const channels = SPECS.map((spec, i) => ({
    id: spec.id, serviceHex: spec.id.slice(0, 2), pidHex: spec.id.slice(3), name: (NAMES[lang] || NAMES.en)[spec.id], unit: spec.unit,
    declaredMinimum: spec.min, declaredMaximum: spec.max, isFast: spec.fast, definitionRevision: 1, isDecodable: true,
    times: series[spec.id].times, values: series[spec.id].values.map((v) => Math.round(v * 1e4) / 1e4), quality: series[spec.id].q,
  }));
  const started = Date.UTC(2026, 9, 3 + variant * 9 + seed, 8, 15, 0);
  const sampleCount = channels.reduce((s, c) => s + c.quality.requested, 0);
  const respondedCount = channels.reduce((s, c) => s + c.quality.responded, 0);
  const odo = 48210 + variant * 20 + seed;
  let km = 0;
  for (let i = 1; i < series['01-0D'].times.length; i++) km += (series['01-0D'].values[i] / 3600) * (series['01-0D'].times[i] - series['01-0D'].times[i - 1]);
  return {
    schemaVersion: 1,
    session: {
      id: `00000000-0000-4000-8000-0000000000${String(10 + seed + variant).padStart(2, '0')}`, vehicleId: '00000000-0000-4000-8000-0000000000aa',
      startedAt: new Date(started).toISOString(), durationSeconds: duration, isRecording: false, isDemo: true, adapterName: 'ELM327 (simulated)', platform: 'mac',
      appVersion: '1.0', endReason: 'userStopped', sampleCount, respondedCount,
      odometerStartKilometers: odo, odometerEndKilometers: Math.round((odo + km) * 10) / 10, distanceKilometers: Math.round(km * 10) / 10,
    },
    vehicle: { id: '00000000-0000-4000-8000-0000000000aa', name: 'Demo ZD8', manufacturer: 'Subaru', engineModel: 'FA24', modelYear: 2023, powertrain: 'combustion' },
    channels,
    gaps,
    maintenance: [
      { id: 'm1', date: new Date(started - 41 * 86400000).toISOString(), title: lang === 'ja' ? 'エンジンオイル交換' : lang === 'es' ? 'Cambio de aceite' : 'Engine oil change', kind: 'light', odometerKilometers: odo - 900 },
    ],
  };
}

/** Long-term trend dataset (per-session aggregates under operating conditions). */
export function buildDemoTrend({ lang = 'en' } = {}) {
  const rand = mulberry32(99);
  const gauss = () => Math.sqrt(-2 * Math.log(rand() || 1e-9)) * Math.cos(2 * Math.PI * rand());
  const names = NAMES[lang] || NAMES.en;
  const channelIds = ['01-0C', '01-05', '01-07', '01-06', '01-04', '01-10'];
  const units = { '01-0C': 'rpm', '01-05': '°C', '01-07': '%', '01-06': '%', '01-04': '%', '01-10': 'g/s' };
  const start = Date.UTC(2025, 8, 1);
  const maintenance = [
    { id: 'm1', date: new Date(start + 70 * 86400000).toISOString(), title: lang === 'ja' ? 'エンジンオイル交換' : lang === 'es' ? 'Cambio de aceite' : 'Engine oil change', kind: 'light', odometerKilometers: 41200 },
    { id: 'm2', date: new Date(start + 250 * 86400000).toISOString(), title: lang === 'ja' ? 'スパークプラグ交換' : lang === 'es' ? 'Cambio de bujías' : 'Spark plugs replaced', kind: 'heavy', odometerKilometers: 46800 },
    { id: 'm3', date: new Date(start + 390 * 86400000).toISOString(), title: lang === 'ja' ? 'エンジンオイル交換' : lang === 'es' ? 'Cambio de aceite' : 'Engine oil change', kind: 'light', odometerKilometers: 51600 },
  ];
  const sessions = [];
  let odo = 40000;
  for (let i = 0; i < 18; i++) {
    const day = i * 24 + Math.round(rand() * 6);
    const startedAt = start + day * 86400000;
    const sinceSpark = day > 250 ? day - 250 : -1;
    const ltftDrift = day < 250 ? (day / 250) * 4.2 : Math.max(0.2, 4.2 - sinceSpark / 30);
    const stats = [];
    const add = (id, condition, count, median, spread) => stats.push({ channelId: id, condition, count, median: Math.round(median * 100) / 100, p05: Math.round((median - spread) * 100) / 100, p95: Math.round((median + spread) * 100) / 100 });
    for (const condition of ['all', 'warmIdle', 'steadyCruise']) {
      const idle = condition === 'warmIdle', cruise = condition === 'steadyCruise';
      add('01-0C', condition, 2000 + i * 40, (idle ? 820 + Math.max(0, ltftDrift * 6) : cruise ? 2350 : 1750) + gauss() * 8, idle ? 35 : cruise ? 120 : 800);
      add('01-05', condition, 300, (idle ? 89 : 87) + gauss() * 0.6, idle ? 1.5 : 4);
      add('01-07', condition, 300, (idle ? 0.8 : 0.3) + ltftDrift * (idle ? 1 : 0.6) + gauss() * 0.25, 1.1);
      add('01-06', condition, 2000, gauss() * 0.4, 4.5);
      add('01-04', condition, 2000, (idle ? 19.5 : cruise ? 31 : 27) + gauss() * 0.7, idle ? 1.5 : 7);
      add('01-10', condition, 2000, (idle ? 3.0 : cruise ? 9.2 : 7) * (1 - 0.01 * ltftDrift) + gauss() * 0.08, idle ? 0.3 : 3);
    }
    const distance = 18 + Math.round(rand() * 120);
    sessions.push({ id: `00000000-0000-4000-8000-0000000001${String(i).padStart(2, '0')}`, startedAt: new Date(startedAt).toISOString(), durationSeconds: 900 + Math.round(rand() * 3000), distanceKilometers: distance, odometerStartKilometers: odo, isDemo: i < 3, sampleCount: 20000 + i * 900, stats });
    odo += distance + 240;
  }
  return {
    schemaVersion: 1,
    vehicle: { id: '00000000-0000-4000-8000-0000000000aa', name: 'Demo ZD8', manufacturer: 'Subaru', engineModel: 'FA24', modelYear: 2023, powertrain: 'combustion' },
    channels: channelIds.map((id) => ({ id, name: names[id], unit: units[id] })),
    sessions, maintenance, skippedCloudOnlySessions: 2, excludedDemoSessions: 0,
  };
}
