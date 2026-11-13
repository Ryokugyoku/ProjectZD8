// A small, safe expression language for derived channels. Own tokenizer and parser:
// no eval, no Function, no property access. No DOM access.

/** Short names that resolve to standard channels. */
export const STANDARD_ALIASES = {
  rpm: '01-0C', speed: '01-0D', coolant: '01-05', load: '01-04', stft: '01-06', ltft: '01-07',
  map: '01-0B', throttle: '01-11', maf: '01-10', iat: '01-0F',
};

const MAX_LENGTH = 500;
const MAX_DEPTH = 40;

export class ExpressionError extends Error {
  constructor(code, position, detail) {
    super(code);
    this.code = code;       // i18n key suffix: unexpectedChar, unexpectedToken, unknownFunction, tooLong, tooDeep, badArguments, empty
    this.position = position;
    this.detail = detail;
  }
}

const FUNCTIONS = {
  abs: [1, Math.abs], sqrt: [1, Math.sqrt], ln: [1, Math.log], log10: [1, Math.log10], exp: [1, Math.exp],
  sin: [1, Math.sin], cos: [1, Math.cos], tan: [1, Math.tan], atan: [1, Math.atan],
  floor: [1, Math.floor], ceil: [1, Math.ceil], round: [1, Math.round],
  min: [2, Math.min], max: [2, Math.max], pow: [2, Math.pow], atan2: [2, Math.atan2],
  clamp: [3, (x, lo, hi) => Math.min(Math.max(x, lo), hi)],
  if: [3, (c, a, b) => (c ? a : b)],
};
const CONSTANTS = { pi: Math.PI, e: Math.E };

function tokenize(source) {
  const tokens = [];
  let i = 0;
  while (i < source.length) {
    const c = source[i];
    if (c === ' ' || c === '\t' || c === '\n') { i++; continue; }
    if ((c >= '0' && c <= '9') || (c === '.' && source[i + 1] >= '0' && source[i + 1] <= '9')) {
      let j = i;
      while (j < source.length && ((source[j] >= '0' && source[j] <= '9') || source[j] === '.')) j++;
      if ((source[j] === 'e' || source[j] === 'E') && /[0-9+-]/.test(source[j + 1] || '')) {
        j++;
        if (source[j] === '+' || source[j] === '-') j++;
        while (j < source.length && source[j] >= '0' && source[j] <= '9') j++;
      }
      const value = Number(source.slice(i, j));
      if (!Number.isFinite(value)) throw new ExpressionError('unexpectedChar', i, source.slice(i, j));
      tokens.push({ type: 'num', value, pos: i });
      i = j;
      continue;
    }
    if (/[A-Za-z_]/.test(c)) {
      let j = i;
      while (j < source.length && /[A-Za-z0-9_]/.test(source[j])) j++;
      tokens.push({ type: 'id', value: source.slice(i, j), pos: i });
      i = j;
      continue;
    }
    if (c === '$') {
      let j = i + 1;
      while (j < source.length && /[0-9A-Fa-f-]/.test(source[j])) j++;
      if (j === i + 1) throw new ExpressionError('unexpectedChar', i, c);
      tokens.push({ type: 'pid', value: source.slice(i + 1, j).toUpperCase(), pos: i });
      i = j;
      continue;
    }
    if (c === '[') {
      const j = source.indexOf(']', i + 1);
      if (j < 0) throw new ExpressionError('unexpectedChar', i, c);
      tokens.push({ type: 'name', value: source.slice(i + 1, j).trim(), pos: i });
      i = j + 1;
      continue;
    }
    const two = source.slice(i, i + 2);
    if (['<=', '>=', '==', '!=', '&&', '||'].includes(two)) { tokens.push({ type: 'op', value: two, pos: i }); i += 2; continue; }
    if ('+-*/%^<>!(),'.includes(c)) { tokens.push({ type: 'op', value: c, pos: i }); i++; continue; }
    throw new ExpressionError('unexpectedChar', i, c);
  }
  return tokens;
}

const BINARY = {
  '||': [1, 'left'], '&&': [2, 'left'],
  '==': [3, 'left'], '!=': [3, 'left'], '<': [4, 'left'], '>': [4, 'left'], '<=': [4, 'left'], '>=': [4, 'left'],
  '+': [5, 'left'], '-': [5, 'left'], '*': [6, 'left'], '/': [6, 'left'], '%': [6, 'left'], '^': [8, 'right'],
};

/**
 * Parses an expression. Returns { ast, refs } where refs lists distinct channel references
 * ({ kind: 'alias' | 'pid' | 'name', value }) in order of first use.
 * Throws ExpressionError for anything outside the grammar.
 */
export function parseExpression(source) {
  if (typeof source !== 'string' || source.trim() === '') throw new ExpressionError('empty', 0);
  if (source.length > MAX_LENGTH) throw new ExpressionError('tooLong', MAX_LENGTH);
  const tokens = tokenize(source);
  let index = 0;
  const refs = [];
  const peek = () => tokens[index];
  const take = () => tokens[index++];
  const expectOp = (value) => {
    const t = take();
    if (!t || t.type !== 'op' || t.value !== value) throw new ExpressionError('unexpectedToken', t ? t.pos : source.length, value);
  };
  const addRef = (kind, value) => {
    if (!refs.some((r) => r.kind === kind && r.value === value)) refs.push({ kind, value });
    return { type: 'ref', kind, value };
  };

  function parseUnary(depth) {
    if (depth > MAX_DEPTH) throw new ExpressionError('tooDeep', peek() ? peek().pos : 0);
    const t = peek();
    if (t && t.type === 'op' && (t.value === '-' || t.value === '+' || t.value === '!')) {
      take();
      const operand = parseBinary(7, depth + 1);
      return t.value === '+' ? operand : { type: 'unary', op: t.value, operand };
    }
    return parsePrimary(depth);
  }

  function parseBinary(minPrec, depth) {
    if (depth > MAX_DEPTH) throw new ExpressionError('tooDeep', peek() ? peek().pos : 0);
    let left = parseUnary(depth);
    for (;;) {
      const t = peek();
      if (!t || t.type !== 'op' || !(t.value in BINARY)) break;
      const [prec, assoc] = BINARY[t.value];
      if (prec < minPrec) break;
      take();
      const right = parseBinary(assoc === 'left' ? prec + 1 : prec, depth + 1);
      left = { type: 'binary', op: t.value, left, right };
    }
    return left;
  }

  function parsePrimary(depth) {
    const t = take();
    if (!t) throw new ExpressionError('unexpectedToken', source.length, 'end');
    if (t.type === 'num') return { type: 'num', value: t.value };
    if (t.type === 'pid') return addRef('pid', t.value);
    if (t.type === 'name') return addRef('name', t.value);
    if (t.type === 'id') {
      const next = peek();
      if (next && next.type === 'op' && next.value === '(') {
        if (!Object.prototype.hasOwnProperty.call(FUNCTIONS, t.value)) throw new ExpressionError('unknownFunction', t.pos, t.value);
        take();
        const args = [];
        if (!(peek() && peek().type === 'op' && peek().value === ')')) {
          for (;;) {
            args.push(parseBinary(1, depth + 1));
            if (peek() && peek().type === 'op' && peek().value === ',') { take(); continue; }
            break;
          }
        }
        expectOp(')');
        if (args.length !== FUNCTIONS[t.value][0]) throw new ExpressionError('badArguments', t.pos, t.value);
        return { type: 'call', name: t.value, args };
      }
      const lower = t.value.toLowerCase();
      if (Object.prototype.hasOwnProperty.call(CONSTANTS, lower)) return { type: 'num', value: CONSTANTS[lower] };
      return addRef('alias', lower);
    }
    if (t.type === 'op' && t.value === '(') {
      const inner = parseBinary(1, depth + 1);
      expectOp(')');
      return inner;
    }
    throw new ExpressionError('unexpectedToken', t.pos, t.value);
  }

  const ast = parseBinary(1, 0);
  if (index < tokens.length) throw new ExpressionError('unexpectedToken', tokens[index].pos, tokens[index].value);
  return { ast, refs };
}

/** Key identifying a reference inside the `columns` map passed to evaluateExpression. */
export function refKey(ref) {
  return `${ref.kind}:${ref.value}`;
}

/**
 * Evaluates the AST for every index 0..n-1. `columns` maps refKey(ref) to a Float64Array of length n
 * (NaN = missing). Missing inputs and undefined results (divide by zero, sqrt of a negative, ...)
 * give NaN, so a gap in any input is a gap in the output.
 */
export function evaluateExpression(ast, columns, n) {
  const run = compileNode(ast, columns);
  const out = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const v = run(i);
    out[i] = Number.isFinite(v) ? v : NaN;
  }
  return out;
}

function compileNode(node, columns) {
  switch (node.type) {
    case 'num': return () => node.value;
    case 'ref': {
      const column = columns[refKey(node)];
      if (!column) throw new ExpressionError('unknownReference', 0, node.value);
      return (i) => column[i];
    }
    case 'unary': {
      const operand = compileNode(node.operand, columns);
      return node.op === '-' ? (i) => -operand(i) : (i) => { const v = operand(i); return Number.isNaN(v) ? NaN : (v ? 0 : 1); };
    }
    case 'call': {
      const fn = FUNCTIONS[node.name][1];
      const args = node.args.map((a) => compileNode(a, columns));
      if (node.name === 'if') return (i) => { const c = args[0](i); return Number.isNaN(c) ? NaN : (c ? args[1](i) : args[2](i)); };
      return (i) => fn(...args.map((a) => a(i)));
    }
    case 'binary': {
      const l = compileNode(node.left, columns);
      const r = compileNode(node.right, columns);
      switch (node.op) {
        case '+': return (i) => l(i) + r(i);
        case '-': return (i) => l(i) - r(i);
        case '*': return (i) => l(i) * r(i);
        case '/': return (i) => { const d = r(i); return d === 0 ? NaN : l(i) / d; };
        case '%': return (i) => { const d = r(i); return d === 0 ? NaN : l(i) % d; };
        case '^': return (i) => Math.pow(l(i), r(i));
        case '<': return (i) => (l(i) < r(i) ? 1 : 0);
        case '>': return (i) => (l(i) > r(i) ? 1 : 0);
        case '<=': return (i) => (l(i) <= r(i) ? 1 : 0);
        case '>=': return (i) => (l(i) >= r(i) ? 1 : 0);
        case '==': return (i) => (l(i) === r(i) ? 1 : 0);
        case '!=': return (i) => (l(i) !== r(i) ? 1 : 0);
        case '&&': return (i) => (l(i) && r(i) ? 1 : 0);
        case '||': return (i) => (l(i) || r(i) ? 1 : 0);
        default: throw new ExpressionError('unexpectedToken', 0, node.op);
      }
    }
    default: throw new ExpressionError('unexpectedToken', 0, node.type);
  }
}
