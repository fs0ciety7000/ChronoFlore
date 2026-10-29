// The duo's stroll on the island: a soft closed path around the pond, walked
// at a gentle pace with idle pauses. Pure maths (no three.js), shared by
// scene.ts and the unit tests. Positions are island-local metres; a heading is
// the yaw that turns a model facing +Z along the direction of travel.

/**
 * Hand-placed loop around the pond (POND in island.ts), threaded between the
 * flower beds, the rocks and the ferns; tests/unit/stroll.test.ts checks the
 * clearances against the island composition.
 */
const WAYPOINTS: readonly [number, number][] = [
  [3.4, -0.65],
  [5.6, -0.8],
  [7.45, -0.25],
  [7.65, 0.75],
  [6.95, 1.6],
  [6.6, 2.7],
  [6.4, 3.6],
  [6.05, 4.45],
  [5.25, 5.25],
  [3.8, 5.75],
  [2.75, 6.6],
  [1.6, 7.25],
  [0.0, 6.75],
  [-1.1, 5.6],
  [-1.55, 4.2],
  [-1.3, 2.85],
  [-0.2, 1.9],
  [0.55, 1.0],
  [1.5, -0.25],
];
/** Waypoints where the pair stops for a moment. */
const PAUSES = [8, 12, 17];

/** Cruise speed (m/s): a chibi stroll that matches the Walk clip's stride. */
export const WALK_SPEED = 0.55;
/** Seconds to speed up from a stop (and to slow down into one). */
const RAMP = 0.8;
/** Seconds of each idle pause, including the turns in and out of it. */
const PAUSE_SECONDS = 4;
/** Seconds to turn toward each other at the start (and back at the end) of a pause. */
const TURN_SECONDS = 1.2;
/** How far (0..1) the leader turns back toward the follower while paused. */
const LEADER_TURN = 0.6;
/** Arc distance (m) between the two along the path. */
export const DUO_SPACING = 0.95;
/** Side step (m) of the follower off the path, so they do not walk in a line. */
const SIDE_STEP = 0.2;

export type PathPoint = { x: number; z: number; heading: number };
export type StrollPath = { length: number; at(s: number): PathPoint };
export type Walker = PathPoint & { walking: boolean; speed: number };

const TAU = Math.PI * 2;
const wrapAngle = (a: number) => a - TAU * Math.floor((a + Math.PI) / TAU);
const smoothstep = (x: number) => {
  const t = Math.min(1, Math.max(0, x));
  return t * t * (3 - 2 * t);
};

let cached: (StrollPath & { cumulative: number[]; xs: number[]; zs: number[] }) | undefined;

/** The loop as a closed Catmull-Rom curve, sampled and parametrised by arc length. */
export function strollPath(): StrollPath {
  if (cached) return cached;
  const n = WAYPOINTS.length;
  const SUB = 48;
  const xs: number[] = [];
  const zs: number[] = [];
  for (let i = 0; i < n; i++) {
    const [p0, p1, p2, p3] = [-1, 0, 1, 2].map((k) => WAYPOINTS[(i + k + n) % n]);
    for (let j = 0; j < SUB; j++) {
      const t = j / SUB;
      const t2 = t * t;
      const t3 = t2 * t;
      const cr = (a: number, b: number, c: number, d: number) =>
        0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
      xs.push(cr(p0[0], p1[0], p2[0], p3[0]));
      zs.push(cr(p0[1], p1[1], p2[1], p3[1]));
    }
  }
  xs.push(xs[0]);
  zs.push(zs[0]);
  const cumulative = [0];
  for (let i = 1; i < xs.length; i++) cumulative.push(cumulative[i - 1] + Math.hypot(xs[i] - xs[i - 1], zs[i] - zs[i - 1]));
  const length = cumulative[cumulative.length - 1];

  const at = (s: number): PathPoint => {
    const u = ((s % length) + length) % length;
    // Binary search for the sample segment holding u.
    let lo = 0;
    let hi = cumulative.length - 1;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (cumulative[mid] <= u) lo = mid;
      else hi = mid;
    }
    const seg = cumulative[hi] - cumulative[lo] || 1;
    const f = (u - cumulative[lo]) / seg;
    const x = xs[lo] + (xs[hi] - xs[lo]) * f;
    const z = zs[lo] + (zs[hi] - zs[lo]) * f;
    // Tangent from a small centred difference keeps the heading smooth.
    const h = 0.12;
    const a = sample(u - h);
    const b = sample(u + h);
    return { x, z, heading: Math.atan2(b.x - a.x, b.z - a.z) };
  };
  const sample = (s: number) => {
    const u = ((s % length) + length) % length;
    let i = cumulative.findIndex((c) => c > u);
    if (i <= 0) i = 1;
    const f = (u - cumulative[i - 1]) / (cumulative[i] - cumulative[i - 1] || 1);
    return { x: xs[i - 1] + (xs[i] - xs[i - 1]) * f, z: zs[i - 1] + (zs[i] - zs[i - 1]) * f };
  };
  cached = { length, at, cumulative, xs, zs };
  return cached;
}

type Leg = { from: number; distance: number; walk: number; start: number };

let schedule: { legs: Leg[]; loop: number } | undefined;

/** Walking legs between the pauses, each followed by PAUSE_SECONDS of idle. */
function legs() {
  if (schedule) return schedule;
  const path = strollPath() as ReturnType<typeof strollPath> & { cumulative: number[] };
  const SUB = 48;
  const stops = PAUSES.map((i) => path.cumulative[i * SUB]);
  const out: Leg[] = [];
  let start = 0;
  for (let k = 0; k < stops.length; k++) {
    const from = stops[k];
    const to = stops[(k + 1) % stops.length];
    const distance = (to - from + path.length) % path.length || path.length;
    const walk = distance / WALK_SPEED + RAMP;
    out.push({ from, distance, walk, start });
    start += walk + PAUSE_SECONDS;
  }
  schedule = { legs: out, loop: start };
  return schedule;
}

/** Seconds for one full lap, pauses included. */
export const STROLL_LOOP_SECONDS = legs().loop;

/** Distance covered `t` seconds into a leg (trapezoid speed profile) and the speed. */
function travel(leg: Leg, t: number): { s: number; v: number } {
  const v = WALK_SPEED;
  const T = leg.walk;
  if (t <= 0) return { s: 0, v: 0 };
  if (t >= T) return { s: leg.distance, v: 0 };
  if (t < RAMP) return { s: (v * t * t) / (2 * RAMP), v: (v * t) / RAMP };
  if (t > T - RAMP) return { s: leg.distance - (v * (T - t) ** 2) / (2 * RAMP), v: (v * (T - t)) / RAMP };
  return { s: (v * RAMP) / 2 + v * (t - RAMP), v };
}

/** The pair at time `t` (s): [leader (heroine), follower (companion)]. */
export function duoAt(t: number): [Walker, Walker] {
  const path = strollPath();
  const { legs: all, loop } = legs();
  const time = ((t % loop) + loop) % loop;
  let leg = all[all.length - 1];
  for (const l of all) if (time >= l.start) leg = l;
  const local = time - leg.start;
  const { s, v } = travel(leg, local);
  const walking = local < leg.walk;
  const lead = path.at(leg.from + s);
  const back = path.at(leg.from + s - DUO_SPACING);
  // The follower walks a little to one side, so they do not walk in a line.
  const side = { x: Math.cos(back.heading), z: -Math.sin(back.heading) };
  const follow = { x: back.x + side.x * SIDE_STEP, z: back.z + side.z * SIDE_STEP, heading: back.heading };

  // While paused they turn toward each other, then back to the path.
  const paused = local - leg.walk;
  const turn = walking ? 0 : smoothstep(paused / TURN_SECONDS) * smoothstep((PAUSE_SECONDS - paused) / TURN_SECONDS);
  const toward = (from: PathPoint, to: { x: number; z: number }) => Math.atan2(to.x - from.x, to.z - from.z);
  const blend = (h: number, target: number, k: number) => wrapAngle(h + wrapAngle(target - h) * k);
  return [
    { ...lead, heading: blend(lead.heading, toward(lead, follow), turn * LEADER_TURN), walking, speed: v },
    { ...follow, heading: blend(follow.heading, toward(follow, lead), turn), walking, speed: v },
  ];
}
