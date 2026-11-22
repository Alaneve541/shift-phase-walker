import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('./index.html', import.meta.url), 'utf8');
const source = html.match(/<script>([\s\S]*?)<\/script>/)[1];

function boot() {
  const events = new Map(), elements = new Map(), store = new Map();
  const ctx = new Proxy({}, { get: (obj, key) => {
    if (key in obj) return obj[key];
    if (key === 'measureText') return text => ({ width: text.length * 8 });
    if (key === 'createLinearGradient' || key === 'createRadialGradient') return () => ({ addColorStop() {} });
    return () => {};
  }});
  function element() {
    const classes = new Set(), listeners = new Map(), children = [];
    const e = { style: {}, dataset: {}, children, textContent: '', innerHTML: '',
      classList: { add: c => classes.add(c), remove: c => classes.delete(c), contains: c => classes.has(c),
        toggle(c, on) { on ??= !classes.has(c); on ? classes.add(c) : classes.delete(c); } },
      getContext: () => ctx, appendChild: c => children.push(c), blur() {},
      addEventListener: (type, fn) => listeners.set(type, fn),
      click() { listeners.get('click')?.({ currentTarget: e, preventDefault() {} }); },
      querySelector: () => element(), querySelectorAll: () => [element(), element(), element()]
    };
    return e;
  }
  const doc = {
    body: element(), hidden: false, createElement: element,
    getElementById(id) { if (!elements.has(id)) elements.set(id, element()); return elements.get(id); },
    querySelectorAll: () => [], addEventListener() {}
  };
  const sandbox = {
    document: doc, performance, console,
    localStorage: { getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, String(v)) },
    matchMedia: () => ({ matches: false }),
    addEventListener(type, fn) { if (!events.has(type)) events.set(type, []); events.get(type).push(fn); },
    dispatchEvent(e) { for (const fn of events.get(e.type) || []) fn(e); },
    KeyboardEvent: class { constructor(type, data) { this.type = type; Object.assign(this, data); } preventDefault() {} },
    requestAnimationFrame() {}, setTimeout() { return 1; }, clearTimeout() {},
    setInterval() { return 1; }, clearInterval() {}
  };
  sandbox.window = sandbox;
  vm.runInNewContext(source, sandbox, { timeout: 5000 });
  return { S: sandbox.__shift, doc, store };
}

function runTo(S, x) {
  S.key('ArrowRight', true);
  for (let i = 0; i < 350 && S.P.x < x && !S.G.dead && !S.G.won; i++) S.step();
  S.key('ArrowRight', false);
  S.step(12);
}

function leaveEcho(S) {
  S.start(8); S.step(3); runTo(S, 211); S.shift(); S.step(4);
}

function moveTo(S, x) {
  for (let i = 0; i < 360; i++) {
    const speed = clamp((x - S.P.x) * 6, -265, 265);
    S.key('ArrowRight', speed > S.P.vx + 15);
    S.key('ArrowLeft', speed < S.P.vx - 15);
    S.step();
    if ((Math.abs(S.P.x - x) < 3 && Math.abs(S.P.vx) < 20) || S.G.won) break;
  }
  S.key('ArrowRight', false); S.key('ArrowLeft', false); S.step(8);
}

function hopTo(S, x) {
  S.key('Space', true);
  for (let frame = 0; frame < 160; frame++) {
    if (frame === 20) S.key('Space', false);
    const speed = clamp((x - S.P.x) * 6, -265, 265);
    S.key('ArrowRight', speed > S.P.vx + 15);
    S.key('ArrowLeft', speed < S.P.vx - 15);
    S.step();
    if (frame > 23 && S.P.grounded && Math.abs(S.P.x - x) < 4 && Math.abs(S.P.vx) < 20) break;
  }
  S.key('Space', false); S.key('ArrowRight', false); S.key('ArrowLeft', false); S.step(8);
}

function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }

function shiftTo(S, target) {
  if (S.world !== target) { S.shift(); S.step(4); }
  assert.equal(S.world, target);
}
function twoDoors(S, pauseFrames = 45) {
  moveTo(S, 295); S.step(pauseFrames);
  moveTo(S, 475); S.step(pauseFrames);
  moveTo(S, 550); shiftTo(S, 1);
  moveTo(S, 1005);
  assert.ok(S.P.x > 936 && S.G.shifts === 1, 'one replay opens two timed doors');
}
function upstairsPair(S, upper, lower, echoWorld, gateIndex) {
  shiftTo(S, echoWorld);
  moveTo(S, upper - 108);
  hopTo(S, upper);
  assert.ok(S.P.grounded && Math.abs(S.P.y + S.P.h - 396) < 0.1, 'reach the raised recording plate');
  S.step(135);
  shiftTo(S, 1 - echoWorld);
  moveTo(S, lower);
  assert.ok(S.info().relays[gateIndex].plates.every(p => p.active), 'both raised and floor plates light together');
  assert.equal(S.info().relays[gateIndex].open, true, 'height-separated pair opens its gate');
}
function jumpBackPair(S, upper, lower, echoWorld, gateIndex) {
  shiftTo(S, echoWorld);
  moveTo(S, upper - 108);
  hopTo(S, upper);
  assert.ok(S.P.grounded && Math.abs(S.P.y + S.P.h - 396) < 0.1, 'record a landing on the raised plate');
  S.step(60);
  shiftTo(S, 1 - echoWorld);
  assert.ok(S.info().echoes[0] && S.info().echoes[0].track.some(p => !p.grounded), 'replay keeps the airborne jump');
  moveTo(S, lower);
  S.step(75);
  assert.equal(S.info().relays[gateIndex].open, true, 'returning left lets the recorded landing open the door');
}
function threeDoors(S, pauseFrames = 20) {
  for (const x of [259, 295, 367]) { moveTo(S, x); S.step(pauseFrames); }
  moveTo(S, 415); shiftTo(S, 1);
  moveTo(S, 1015);
  assert.ok(S.P.x > 900 && S.G.shifts === 1, 'one replay opens three consecutive doors');
}
function hopShiftTo(S, x) {
  S.key('Space', true);
  for (let frame = 0; frame < 160; frame++) {
    if (frame === 8) { assert.equal(S.P.grounded, false); shiftTo(S, 1); }
    if (frame === 20) S.key('Space', false);
    const speed = clamp((x - S.P.x) * 6, -265, 265);
    S.key('ArrowRight', speed > S.P.vx + 15);
    S.key('ArrowLeft', speed < S.P.vx - 15);
    S.step();
    if (frame > 23 && S.P.grounded && Math.abs(S.P.x - x) < 4 && Math.abs(S.P.vx) < 20) break;
  }
  S.key('Space', false); S.key('ArrowRight', false); S.key('ArrowLeft', false); S.step(8);
  assert.ok(S.world === 1 && S.P.grounded && Math.abs(S.P.y + S.P.h - 324) < 0.1, 'air SHIFT lands on the blue stepping stone');
}
function finishJourney(S) {
  moveTo(S, S.info().portal.x - 11);
  S.step(80);
  assert.equal(S.state, 'win');
  assert.equal(S.G.deaths, 0);
  assert.equal(S.G.shards, S.G.shardTotal);
}

test('nine rectangular maps, one spawn and one exit each', () => {
  const { S } = boot();
  assert.equal(S.LEVELS.length, 9);
  for (const l of S.LEVELS) {
    assert.equal(l.map.length, 15);
    assert.equal(new Set(l.map.map(r => r.length)).size, 1, l.name);
    assert.equal((l.map.join('').match(/S/g) || []).length, 1);
    assert.equal((l.map.join('').match(/[EPQ]/g) || []).length, 1);
  }
});

test('all nine spawn points are safe without input', () => {
  const { S } = boot();
  for (let i = 0; i < S.LEVELS.length; i++) {
    S.start(i); S.step(180);
    assert.equal(S.G.deaths, 0, S.LEVELS[i].name);
  }
});

test('first level can be cleared with movement, jump and shift', () => {
  const { S } = boot();
  S.start(0); S.key('ArrowRight', true);
  let shifted = false, jumping = false;
  for (let i = 0; i < 600 && !S.G.won; i++) {
    if (!shifted && S.P.x > 330) { S.shift(); shifted = true; }
    const jump = (S.P.x > 368 && S.P.x < 460) || (S.P.x > 690 && S.P.x < 780);
    if (jump !== jumping) { S.key('Space', jump); jumping = jump; }
    S.step();
  }
  assert.equal(S.G.won, true);
  assert.equal(S.G.deaths, 0);
  assert.equal(S.G.shards, 2);
});

test('hold this for me opens both locks with two shifts and pure input', () => {
  const { S } = boot();
  leaveEcho(S);
  assert.equal(S.info().echoes[0].w, 0);
  runTo(S, 427); assert.equal(S.info().relays[0].open, true);
  runTo(S, 787); S.shift(); S.step(4);
  assert.equal(S.info().echoes[0].w, 1);
  runTo(S, 1003); assert.equal(S.info().relays[1].open, true);
  runTo(S, 1330); S.step(80);
  assert.equal(S.state, 'win');
  assert.equal(S.G.shifts, 2);
  assert.equal(S.G.deaths, 0);
});

test('expired echoes cannot unlock a gate and closed gates block movement', () => {
  const { S } = boot(); leaveEcho(S); S.step(200); runTo(S, 427);
  assert.equal(S.info().echoes.length, 0);
  assert.equal(S.info().relays[0].open, false);
  runTo(S, 700);
  assert.ok(S.P.x + S.P.w <= 16 * 36);
});

test('an echo in the wrong world cannot activate a plate', () => {
  const { S } = boot(); S.start(8); S.step(3); S.shift(); S.step(30);
  runTo(S, 211); S.shift(); S.step(4); runTo(S, 427);
  assert.equal(S.info().relays[0].open, false);
  assert.equal(S.info().relays[0].plates[0].active, false);
});

test('a floating echo cannot press a floor plate', () => {
  const { S } = boot(); S.start(8); S.step(3); runTo(S, 211);
  S.key('Space', true); S.step(10); S.shift(); S.step(4);
  assert.equal(S.info().echoes[0].grounded, false);
  assert.equal(S.info().relays[0].plates[0].active, false);
});

test('pause freezes echo lifetime and releases held inputs', () => {
  const { S, doc } = boot(); leaveEcho(S);
  const before = S.info(); S.key('ArrowRight', true);
  doc.getElementById('pauseBtn').click(); S.step(300);
  assert.equal(S.info().echoes[0].life, before.echoes[0].life);
  assert.equal(S.G.time, before.time);
  assert.equal(S.IN.right, false);
  doc.getElementById('resumeBtn').click(); S.step();
  assert.ok(S.info().echoes[0].life < before.echoes[0].life);
});

test('restart resets locks, echoes, hit-stop and queued input', () => {
  const { S, doc } = boot(); leaveEcho(S); runTo(S, 427);
  S.key('ArrowRight', true); S.key('ShiftLeft', true);
  S.G.hitStop = 0.1; doc.getElementById('restartBtn').click();
  assert.equal(S.G.hitStop, 0);
  assert.equal(S.info().echoes.length, 0);
  assert.ok(S.info().relays.every(g => !g.open));
  S.step(10); assert.equal(S.G.world, 0); assert.equal(S.P.x, 79);
});

test('death removes echoes and respawns in the saved world', () => {
  const { S } = boot(); leaveEcho(S); S.P.y = 620; S.step();
  assert.equal(S.G.dead, true); assert.equal(S.info().echoes.length, 0);
  S.step(65); assert.equal(S.G.dead, false);
  assert.equal(S.world, S.info().respawn.world); assert.equal(S.world, 0);
});

test('shift into solid matter is denied', () => {
  const { S } = boot(); S.start(3); S.step(3); S.shift(); S.step(30);
  S.P.x = 8 * 36 + 5; S.P.y = 10 * 36; S.shift();
  assert.equal(S.world, 1); assert.equal(S.G.shifts, 1);
});

test('assist mode relaxes spike hitboxes and reduces drone speed', () => {
  const { S } = boot();
  S.start(2); S.P.x = 225; S.P.y = 424; S.step(); assert.equal(S.G.dead, true);
  S.start(2); S.G.assist = true; S.P.x = 225; S.P.y = 424; S.step(); assert.equal(S.G.dead, false);
  S.G.assist = false; S.start(4); const x = S.info().drones[0].x; S.step(10);
  const normal = S.info().drones[0].x - x;
  S.G.assist = true; S.start(4); S.step(10);
  assert.ok(Math.abs((S.info().drones[0].x - x) / normal - 0.6) < 1e-8);
});

test('win time matches saved time and the finish animation does not add time', () => {
  const { S, store } = boot(); S.start(0); S.step(60);
  const portal = S.info().portal; S.P.x = portal.x - 11; S.P.y = portal.y - 13; S.step();
  const t = S.G.time; S.step(100);
  assert.equal(S.G.time, t); assert.equal(S.state, 'win');
  assert.equal(JSON.parse(store.get('shift_save_v1')).best[0].time, t);
});

test('double jump unlocks at level five, not in the first four levels', () => {
  const { S } = boot();
  for (let level = 0; level < 9; level++) {
    S.start(level); S.key('Space', true); S.step();
    assert.equal(S.P.airJumpReady, true, 'immediate spawn jump is a ground jump');
    S.key('Space', false); S.step(3); S.key('Space', true); S.step();
    assert.equal(S.P.vy < -450, level >= 4, S.LEVELS[level].name);
    assert.equal(S.P.airJumpReady, level < 4);
  }
});

test('third jump is denied, landing restores the second jump', () => {
  const { S } = boot(); S.start(4); S.key('Space', true); S.step(8);
  S.key('Space', false); S.key('Space', true); S.step(8);
  assert.equal(S.P.airJumpReady, false);
  S.key('Space', false); S.key('Space', true); S.step();
  assert.ok(S.P.vy > -200);
  S.key('Space', false); S.step(120);
  assert.equal(S.P.grounded, true); assert.equal(S.P.airJumpReady, true);
  S.key('Space', true); S.step(6); S.key('Space', false); S.key('Space', true); S.step();
  assert.ok(S.P.vy < -450); assert.equal(S.P.airJumpReady, false);
});

test('holding jump or another jump key cannot consume the second jump', () => {
  const { S } = boot(); S.start(4); S.key('Space', true); S.step(8);
  S.key('KeyW', true); S.step();
  assert.equal(S.P.airJumpReady, true);
  S.key('Space', false);
  assert.equal(S.IN.jumpHeld, true); assert.ok(S.P.vy < -200);
  S.step(120);
  assert.equal(S.P.grounded, true); assert.equal(S.P.airJumpReady, true);
  S.key('KeyW', false); S.key('KeyW', true); S.step(8);
  S.key('KeyW', false); S.key('ArrowUp', true); S.step();
  assert.equal(S.P.airJumpReady, false); assert.ok(S.P.vy < -450);
});

test('falling players can use their reserved air jump', () => {
  const { S } = boot(); S.start(4);
  S.P.y = 290; S.P.grounded = false; S.P.coyote = 0; S.P.vy = 300;
  S.key('Space', true); S.step();
  assert.ok(S.P.vy < -450); assert.equal(S.P.airJumpReady, false);
});

test('coyote-time jump preserves the air jump', () => {
  const { S } = boot(); S.start(4);
  S.P.y = 360; S.P.grounded = false; S.P.coyote = 0.08;
  S.key('Space', true); S.step();
  assert.ok(S.P.vy < -500); assert.equal(S.P.airJumpReady, true);
  S.key('Space', false); S.key('Space', true); S.step();
  assert.ok(S.P.vy < -450); assert.equal(S.P.airJumpReady, false);
});

test('shifting worlds does not refresh the air jump', () => {
  const { S } = boot(); S.start(4); S.key('Space', true); S.step(10);
  S.key('Space', false); S.key('Space', true); S.step(); S.shift(); S.step(5);
  assert.equal(S.world, 1); assert.equal(S.P.airJumpReady, false);
  S.key('Space', false); S.key('Space', true); S.step();
  assert.ok(S.P.vy > -200);
});

test('ceiling contact does not restore an air jump', () => {
  const { S } = boot(); S.start(4); S.P.x = 320;
  S.key('Space', true); S.step(3); S.key('Space', false); S.key('Space', true);
  let hitCeiling = false;
  for (let i = 0; i < 12; i++) {
    S.step();
    if (!S.P.grounded && S.P.vy === 0) { hitCeiling = true; break; }
  }
  assert.equal(hitCeiling, true); assert.equal(S.P.airJumpReady, false);
});

test('pause ignores jump presses; restart and respawn reset the jump reserve', () => {
  const { S, doc } = boot(); S.start(4); S.key('Space', true); S.step(10);
  S.key('Space', false); S.key('Space', true); S.step();
  doc.getElementById('pauseBtn').click(); const vy = S.P.vy;
  S.key('Space', true); S.step(60);
  assert.equal(S.P.vy, vy); assert.equal(S.IN.jumpHeld, false);
  doc.getElementById('resumeBtn').click(); S.step();
  assert.equal(S.P.airJumpReady, false);
  doc.getElementById('restartBtn').click();
  assert.equal(S.P.airJumpReady, true); assert.equal(S.IN.jumpHeld, false);
  S.key('Space', true); S.step(10); S.key('Space', false); S.key('Space', true); S.step();
  S.P.y = 620; S.step(); assert.equal(S.G.dead, true); S.step(65);
  assert.equal(S.G.dead, false); assert.equal(S.P.airJumpReady, true);
});

test('level five single jump cannot reach the first platform but double jump reaches all four', () => {
  const { S } = boot(); S.start(4); S.key('Space', true);
  let maxRise = 0;
  for (let i = 0; i < 60; i++) { S.step(); maxRise = Math.max(maxRise, 468 - S.P.y - S.P.h); }
  assert.ok(maxRise < 108);
  S.start(4);
  const moveTo = x => {
    const dir = S.P.x < x ? 1 : -1, key = dir > 0 ? 'ArrowRight' : 'ArrowLeft';
    S.key(key, true);
    for (let i = 0; i < 250 && (x - S.P.x) * dir > 0 && !S.G.dead && !S.G.won; i++) S.step();
    S.key(key, false); S.step(12);
  };
  const hop = (first, second, platformRow) => {
    S.key('ArrowRight', true); S.key('Space', true); S.step(first);
    S.key('Space', false); S.key('Space', true); S.step(second);
    S.key('ArrowRight', false);
    for (let i = 0; i < 120 && !S.P.grounded && !S.G.dead; i++) S.step();
    S.key('Space', false); S.step(12);
    assert.equal(S.P.grounded, true);
    assert.ok(Math.abs(S.P.y + S.P.h - platformRow * 36) < 0.02);
    assert.equal(S.P.airJumpReady, true);
  };
  moveTo(196); hop(16, 11, 10);
  moveTo(372); hop(23, 29, 8);
  moveTo(647); hop(23, 26, 10);
  moveTo(937); hop(23, 15, 8);
  moveTo(1123); moveTo(1370); S.step(80);
  assert.equal(S.G.shards, 4); assert.equal(S.G.deaths, 0); assert.equal(S.state, 'win');
});

const laterRoutes = {
  5: [[259,0,1],[439,1,0],[619,0,0],[691,0,0],[799,1,1],[979,0,0],[1190,1,0],[1411,1,0]],
  6: [[259,0,0],[439,1,1],[709,0,1],[925,1,1],[1087,0,1],[1267,0,1],[1483,1,1,30],[1711,0,0],[1789,0,0]],
  7: [[223,1,1],[475,0,1,30],[655,0,1],[799,1,0],[943,0,0],[1051,0,0],[1303,1,0],[1519,0,1,0],[1735,0,0],[1879,0,0]]
};
for (const level of [5, 6, 7]) {
  test(`level ${level + 1} high platforms, checkpoint and all shards are reachable with keyboard input`, () => {
    const { S } = boot(); S.start(level); S.step(3);
    for (const [x, world, double, shiftFrame = 10] of laterRoutes[level]) {
      S.key('Space', true);
      for (let frame = 0; frame < 160; frame++) {
        if (frame === 20) S.key('Space', false);
        if (frame === 22 && double) S.key('Space', true);
        if (frame === shiftFrame && S.world !== world) S.shift();
        const targetSpeed = Math.max(-265, Math.min(265, (x - S.P.x) * 6));
        S.key('ArrowRight', targetSpeed > S.P.vx + 15);
        S.key('ArrowLeft', targetSpeed < S.P.vx - 15);
        S.step();
        assert.equal(S.G.dead, false);
        if (S.G.won) break;
        if (frame > 23 && S.P.grounded && Math.abs(S.P.x - x) < 5 && Math.abs(S.P.vx) < 20) break;
      }
      S.key('Space', false);
    }
    S.key('ArrowRight', false); S.key('ArrowLeft', false); S.step(80);
    assert.equal(S.state, 'win'); assert.equal(S.G.deaths, 0);
    assert.equal(S.G.shards, S.G.shardTotal);
    assert.ok(S.G.respawn.x > 600, 'checkpoint activated');
  });
}

test('double jump cannot bypass the final level pressure-plate gates', () => {
  const { S } = boot();
  for (const timing of [10, 18, 23, 28, 35]) {
    S.start(8); runTo(S, 468); S.key('ArrowRight', true); S.key('Space', true); S.step(timing);
    S.key('Space', false); S.key('Space', true); S.step(100);
    assert.equal(S.info().relays[0].open, false);
    assert.ok(S.P.x + S.P.w <= 16 * 36);
  }
});

test('ten journey chapters have rectangular maps, spawn, exit, three shards and replay rules', () => {
  const { S } = boot();
  assert.equal(S.JOURNEY.length, 10);
  for (const l of S.JOURNEY) {
    assert.equal(l.echo_mode, 'replay', l.name);
    assert.equal(l.double_jump, false, l.name);
    assert.equal(l.map.length, 15, l.name);
    assert.equal(new Set(l.map.map(r => r.length)).size, 1, l.name);
    assert.equal((l.map.join('').match(/S/g) || []).length, 1, l.name);
    assert.equal((l.map.join('').match(/[EPQ]/g) || []).length, 1, l.name);
    assert.equal((l.map.join('').match(/\*/g) || []).length, 3, l.name);
    assert.ok(l.stages.length >= 1, l.name);
    assert.ok(l.relays.length >= 1, l.name);
  }
});

test('all ten journey spawn points are safe and keep single jump', () => {
  const { S } = boot();
  for (let i = 0; i < S.JOURNEY.length; i++) {
    S.startJourney(i); S.step(120);
    assert.equal(S.G.deaths, 0, S.JOURNEY[i].name);
    assert.equal(S.info().doubleJump, false, S.JOURNEY[i].name);
  }
});

test('journey moving echo replays and opens a timed door', () => {
  const { S } = boot();
  S.startJourney(0); S.step(3);
  moveTo(S, 295);
  S.step(60);
  moveTo(S, 440);
  S.shift(); S.step(4);
  assert.equal(S.world, 1);
  const first = S.info().echoes[0];
  assert.ok(first && first.track && first.track.length > 2, 'echo keeps a recorded track');
  let moved = false, opened = false;
  for (let i = 0; i < 190; i++) {
    S.step();
    const e = S.info().echoes[0];
    if (e && Math.abs(e.x - first.x) > 5) moved = true;
    if (S.info().relays[0].open) opened = true;
  }
  assert.equal(moved, true, 'recorded double moves');
  assert.equal(opened, true, 'recorded double presses the door plate');
});

test('journey records airborne poses for a jump replay', () => {
  const { S } = boot();
  S.startJourney(6); S.step(3);
  moveTo(S, 403);
  hopTo(S, 511);
  assert.ok(Math.abs(S.P.y + S.P.h - 396) < 0.1, 'landed on the raised plate');
  S.step(60);
  S.shift(); S.step(4);
  const e = S.info().echoes[0];
  assert.ok(e && e.track.some(p => !p.grounded), 'echo track contains the jump');
});

test('journey supports multiple checkpoints and respawn', () => {
  const { S } = boot();
  S.startJourney(5); S.step(3);
  const cps = S.info().checkpoints;
  assert.equal(cps.length, 4);
  const cp = cps[0];
  S.P.x = cp.x - S.P.w / 2; S.P.y = cp.y - S.P.h; S.step();
  assert.equal(S.info().checkpoints[0].active, true);
  const spawn = S.info().respawn;
  S.P.y = 620; S.step(); S.step(65);
  assert.equal(S.G.dead, false);
  assert.ok(Math.abs(S.P.x - (cp.x - S.P.w / 2)) < 1);
  assert.equal(S.world, spawn.world);
});

test('journey progress is saved by chapter id and stays separate', () => {
  const { S, store } = boot();
  S.startJourney(0); S.step(3);
  const p = S.info().portal;
  S.P.x = p.x - 11; S.P.y = p.y - 13; S.step();
  for (let i = 0; i < 80 && S.state !== 'win'; i++) S.step();
  assert.equal(S.state, 'win');
  const data = JSON.parse(store.get('shift_save_v1'));
  assert.equal(data.journeyUnlocked, 1);
  assert.ok(data.journeyBest.sample_wait_for_me);
  assert.equal(data.best[0], undefined);
});

test('journey map and continue controls start the journey', () => {
  const { S, doc } = boot();
  doc.getElementById('journeyMapBtn').click();
  assert.equal(doc.getElementById('journeyOv').classList.contains('show'), true);
  doc.getElementById('journeyContinueBtn').click();
  assert.equal(S.mode, 'journey');
  assert.equal(S.li, 0);
});

test('all ten journey chapters can be completed with keyboard input', () => {
  const { S } = boot();

  S.startJourney(0); S.step(3);
  moveTo(S, 295); S.step(180);
  assert.equal(S.info().relays[0].plates[0].active, true);
  S.shift(); S.step(4);
  moveTo(S, 394); hopTo(S, 475);
  moveTo(S, 710); assert.ok(S.P.x > 684);
  moveTo(S, 940); assert.equal(S.info().checkpoints[0].active, true);
  if (S.world !== 0) shiftTo(S, 0);
  moveTo(S, 1267);
  const shiftsA = S.G.shifts; S.shift(); S.step(4);
  assert.ok(S.world === 0 && S.G.shifts === shiftsA, 'static shift inside LUN cage is denied');
  S.step(75); moveTo(S, 1350); shiftTo(S, 1);
  hopTo(S, 1530); moveTo(S, 1725); assert.ok(S.P.x > 1692);
  moveTo(S, 1930); assert.equal(S.info().checkpoints[1].active, true);
  if (S.world !== 0) shiftTo(S, 0);
  moveTo(S, 2239);
  const shiftsB = S.G.shifts; S.shift(); S.step(4);
  assert.ok(S.world === 0 && S.G.shifts === shiftsB, 'last floor plate also forbids a static shift');
  S.step(90); moveTo(S, 2324); shiftTo(S, 1);
  hopTo(S, 2455);
  assert.ok(Math.abs(S.P.y + S.P.h - 396) < 0.1, 'single jump reaches the upper plate');
  S.step(32); assert.ok(S.info().relays[2].plates.every(p => p.active), 'final pair lights together');
  S.step(48); assert.equal(S.info().relays[2].open, true);
  hopTo(S, 2540);
  finishJourney(S);

  S.startJourney(1); S.step(3);
  twoDoors(S); finishJourney(S);

  S.startJourney(2); S.step(3);
  upstairsPair(S, 367, 619, 0, 0);
  moveTo(S, 970); assert.equal(S.info().checkpoints[0].active, true);
  upstairsPair(S, 1231, 1447, 1, 1);
  finishJourney(S);

  S.startJourney(3); S.step(3);
  moveTo(S, 1879); S.step(135); moveTo(S, 1800); shiftTo(S, 1);
  moveTo(S, 1380); assert.equal(S.info().checkpoints[1].active, true);
  moveTo(S, 1231); S.step(135); moveTo(S, 1155); shiftTo(S, 0);
  moveTo(S, 979); assert.ok(S.info().relays[1].plates.every(p => p.active));
  moveTo(S, 700); assert.equal(S.info().checkpoints[0].active, true);
  shiftTo(S, 1); moveTo(S, 295); shiftTo(S, 0);
  finishJourney(S);

  S.startJourney(4); S.step(3);
  moveTo(S, 295); S.step(135); moveTo(S, 380); shiftTo(S, 1);
  moveTo(S, 810); assert.equal(S.info().checkpoints[0].active, true);
  moveTo(S, 979); S.step(135); moveTo(S, 1080); shiftTo(S, 0);
  moveTo(S, 1500); assert.equal(S.info().checkpoints[1].active, true);
  moveTo(S, 1663); S.step(135); moveTo(S, 1738); shiftTo(S, 1);
  hopTo(S, 1843); S.step(24);
  assert.ok(S.info().relays[2].plates.every(p => p.active));
  S.step(24); assert.equal(S.info().relays[2].open, true);
  finishJourney(S);

  S.startJourney(5); S.step(3);
  twoDoors(S);
  moveTo(S, 1100); assert.equal(S.info().checkpoints[1].active, true);
  upstairsPair(S, 1303, 1519, 0, 2);
  moveTo(S, 1870); assert.equal(S.info().checkpoints[2].active, true);
  upstairsPair(S, 2095, 2311, 1, 3);
  moveTo(S, 2670); assert.equal(S.info().checkpoints[3].active, true);
  shiftTo(S, 1);
  finishJourney(S);

  S.startJourney(6); S.step(3);
  jumpBackPair(S, 511, 331, 0, 0);
  moveTo(S, 885); assert.equal(S.info().checkpoints[0].active, true);
  jumpBackPair(S, 1303, 1123, 1, 1);
  finishJourney(S);

  S.startJourney(7); S.step(3);
  moveTo(S, 691); S.step(135); moveTo(S, 619); shiftTo(S, 1);
  moveTo(S, 367); assert.equal(S.info().relays[0].open, true);
  shiftTo(S, 0); assert.equal(S.info().relays[0].open, true);
  moveTo(S, 1060); assert.equal(S.info().checkpoints[0].active, true);
  shiftTo(S, 1); moveTo(S, 1519); S.step(135); moveTo(S, 1447); shiftTo(S, 0);
  moveTo(S, 1195); assert.equal(S.info().relays[1].open, true);
  shiftTo(S, 1);
  finishJourney(S);

  S.startJourney(8); S.step(3);
  threeDoors(S);
  moveTo(S, 1100); assert.equal(S.info().checkpoints[1].active, true);
  shiftTo(S, 0);
  moveTo(S, 1663); S.step(135); moveTo(S, 1738); shiftTo(S, 1);
  hopTo(S, 1879); S.step(24);
  assert.equal(S.info().relays[3].open, true);
  finishJourney(S);

  S.startJourney(9); S.step(3);
  moveTo(S, 223); hopTo(S, 331);
  assert.ok(Math.abs(S.P.y + S.P.h - 396) < 0.1, 'amber stepping stone is reachable');
  moveTo(S, 367); hopShiftTo(S, 475);
  moveTo(S, 511); hopTo(S, 655);
  assert.equal(S.info().checkpoints[0].active, true);
  moveTo(S, 810); assert.equal(S.info().checkpoints[2].active, true);
  upstairsPair(S, 1087, 1303, 1, 0);
  assert.equal(S.world, 0);
  finishJourney(S);
});
