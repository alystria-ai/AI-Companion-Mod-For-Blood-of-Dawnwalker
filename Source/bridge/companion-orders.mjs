/** Bounded orders only. This module never evaluates text or calls game APIs. */
export const ORDER_GRAMMAR = 'Separate steps with "then". Commands: follow me / regroup; hold position; attack my target; frontline / rearguard / flank left / flank right / prefer ranged; be passive / defensive / aggressive; protect me; wait 1–120 seconds. Conditions: when combat starts, when the target is clear, or when your health is below 1–99 percent. Conditions wait up to 60 game seconds. Characters choose their own abilities. Unknown commands are rejected.';
const MAX_NODES = 24, MAX_TRANSITIONS = 96, MAX_WIRE = 12288;
const ID = /^[A-Za-z][A-Za-z0-9_-]{0,47}$/;
const TERMINALS = new Set(['done', 'failed']);
const VALUES = {
  follow: ['player'], hold: ['position'], attack: ['current_target'],
  role: ['frontline', 'rearguard', 'flank_left', 'flank_right', 'ranged'],
  stance: ['passive', 'defensive', 'aggressive'],
  priority: ['player_target','protect','nearest','weakest'],
};
const fail = message => { throw new Error(`Companion order: ${message}`); };
const integer = (n, lo, hi) => Number.isSafeInteger(n) && n >= lo && n <= hi;
function validValue(op, value, timeoutMs) {
  if (typeof value !== 'string') return false;
  if (Object.hasOwn(VALUES, op)) return VALUES[op].includes(value);
  if (op === 'wait') return /^[1-9]\d{0,5}$/.test(value) && integer(Number(value), 1, 120000) && Number(value) <= timeoutMs;
  if (op === 'condition') return value === 'combat' || value === 'target_clear' || /^health_below:0\.\d{1,3}$/.test(value) && Number(value.split(':')[1]) > 0;
  return false;
}

/** Returns a detached, canonical graph. Every branch must have an explicit edge. */
export function validateGraph(input) {
  if (!input || input.version !== 1 || !ID.test(input.id ?? '') || TERMINALS.has(input.id)) fail('invalid graph version or id');
  if (!integer(input.maxTransitions, 1, MAX_TRANSITIONS)) fail('maxTransitions must explicitly bound execution to 1–96 steps');
  if (!Array.isArray(input.nodes) || input.nodes.length < 1 || input.nodes.length > MAX_NODES) fail('provide 1–24 nodes');
  const nodes = [], byId = new Map();
  for (const n of input.nodes) {
    if (!n || !ID.test(n.id ?? '') || TERMINALS.has(n.id) || byId.has(n.id)) fail('node ids must be unique bounded identifiers');
    if (!integer(n.timeoutMs, 1, 120000) || !validValue(n.op, n.value, n.timeoutMs)) fail(`unsupported operation/value or timeout at ${n.id}`);
    if (typeof n.success !== 'string' || typeof n.failure !== 'string') fail(`both success and failure edges are required at ${n.id}`);
    const node = {id:n.id, op:n.op, value:n.value, timeoutMs:n.timeoutMs, success:n.success, failure:n.failure};
    byId.set(node.id, node); nodes.push(node);
  }
  if (!byId.has(input.start)) fail('start must identify an existing node');
  for (const n of nodes) for (const edge of [n.success, n.failure]) if (!TERMINALS.has(edge) && !byId.has(edge)) fail(`missing edge ${edge} at ${n.id}`);
  const reachable = new Set(), visit = id => {
    if (TERMINALS.has(id) || reachable.has(id)) return;
    reachable.add(id); const n = byId.get(id); visit(n.success); visit(n.failure);
  };
  visit(input.start);
  if (reachable.size !== nodes.length) fail('unreachable nodes are not allowed');
  const exits = new Set(TERMINALS);
  for (let round = 0; round < nodes.length; round++) for (const n of nodes) if (exits.has(n.success) || exits.has(n.failure)) exits.add(n.id);
  if (nodes.some(n => !exits.has(n.id))) fail('every node needs a path to a terminal; closed loops are forbidden');
  return {version:1, id:input.id, start:input.start, maxTransitions:input.maxTransitions, nodes};
}

/** ASCII TSV; identifiers and values cannot contain tabs/newlines/escapes. */
export function encodeGraph(input) {
  const g = validateGraph(input);
  return [`ORDER\t1\t${g.id}\t${g.start}\t${g.maxTransitions}`, ...g.nodes.map(n => ['NODE', n.id, n.op, n.value, n.timeoutMs, n.success, n.failure].join('\t'))].join('\n') + '\n';
}

export function decodeGraph(text) {
  if (typeof text !== 'string' || text.length > MAX_WIRE || /[^\x09\x0a\x0d\x20-\x7e]/.test(text)) fail('invalid or oversized wire data');
  const lines = text.replace(/\r\n/g, '\n').replace(/\n$/, '').split('\n');
  const h = lines.shift().split('\t');
  if (h.length !== 5 || h[0] !== 'ORDER' || h[1] !== '1' || !/^[1-9]\d?$/.test(h[4])) fail('invalid wire header');
  const nodes = lines.map(line => {
    const p = line.split('\t');
    if (p.length !== 7 || p[0] !== 'NODE' || !/^[1-9]\d{0,5}$/.test(p[4])) fail('invalid wire node');
    return {id:p[1], op:p[2], value:p[3], timeoutMs:Number(p[4]), success:p[5], failure:p[6]};
  });
  return validateGraph({version:1, id:h[2], start:h[3], maxTransitions:Number(h[4]), nodes});
}

function condition(text) {
  if (/^(?:combat starts|in combat)$/.test(text)) return 'combat';
  if (/^(?:the )?target is clear$/.test(text)) return 'target_clear';
  const health = text.match(/^(?:your |companion )health is below ([1-9]\d?) (?:percent|%)$/);
  if (health) return `health_below:${Number(health[1]) / 100}`;
  fail(`unsupported condition "${text}". ${ORDER_GRAMMAR}`);
}
function command(text) {
  const commands = [
    [/^(?:follow(?: me)?|regroup(?: with me)?)$/, 'follow', 'player'],
    [/^(?:hold(?: position)?|stop walking|stay here)$/, 'hold', 'position'],
    [/^attack (?:my|the current) target$/, 'attack', 'current_target'],
    [/^(?:be |take the |act as )?(?:a )?(?:frontline|front line)(?: fighter| role)?$/, 'role', 'frontline'],
    [/^(?:be |take the |act as )?(?:a )?(?:rearguard|rear guard)(?: fighter| role)?$/, 'role', 'rearguard'],
    [/^flank left$/, 'role', 'flank_left'], [/^flank right$/, 'role', 'flank_right'],
    [/^(?:prefer ranged|ranged preference|keep your distance)$/, 'role', 'ranged'],
    [/^protect (?:me|the player)$/, 'priority', 'protect'],
  ];
  for (const [pattern, op, value] of commands) if (pattern.test(text)) return {op, value, timeoutMs:15000};
  const stance = text.match(/^(?:be |fight |become )?(passive|defensive|aggressive)$/);
  if (stance) return {op:'stance', value:stance[1], timeoutMs:15000};
  const wait = text.match(/^wait ([1-9]\d{0,2})(?: seconds?|s)$/);
  if (wait && Number(wait[1]) <= 120) return {op:'wait', value:String(Number(wait[1]) * 1000), timeoutMs:Math.min(120000, Number(wait[1]) * 1000 + 1000)};
  fail(`unsupported command "${text}". ${ORDER_GRAMMAR}`);
}

/** Deterministic small grammar, not a general natural-language planner. */
export function compileOrder(text, {id = 'order'} = {}) {
  if (typeof text !== 'string' || text.length < 1 || text.length > 2048 || /[\x00-\x1f\x7f]/.test(text)) fail('use a plain order of at most 2048 characters');
  const normalized = text.trim().toLowerCase().replace(/[.!]$/, '').replace(/\s+/g, ' ');
  const clauses = normalized.split(/\s*,?\s+then\s+/);
  const steps = [];
  for (const clause of clauses) {
    let action = clause, gate;
    const before = clause.match(/^when (.+?),\s*(.+)$/);
    const after = clause.match(/^(.+?) when (.+)$/);
    if (before) {gate = condition(before[1]); action = before[2];}
    else if (after) {action = after[1]; gate = condition(after[2]);}
    if (gate) steps.push({op:'condition', value:gate, timeoutMs:60000});
    steps.push(command(action));
  }
  if (steps.length > MAX_NODES) fail('order exceeds 24 steps including conditions');
  return validateGraph({version:1, id, start:'n1', maxTransitions:steps.length, nodes:steps.map((step, i) => ({id:`n${i+1}`, ...step, success:i === steps.length - 1 ? 'done' : `n${i+2}`, failure:'failed'}))});
}
