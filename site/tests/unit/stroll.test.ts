import { describe, expect, it } from 'vitest';
import { ISLAND, ISLAND_RADIUS, POND } from '../../src/scripts/diorama/island';
import { DUO_SPACING, STROLL_LOOP_SECONDS, duoAt, strollPath } from '../../src/scripts/diorama/stroll';

const SAMPLES = 900;
const times = Array.from({ length: SAMPLES }, (_, i) => (i / SAMPLES) * STROLL_LOOP_SECONDS);

/** Radial distance (m) from a point to the water's edge (negative in the water). Walking on the sandy shore is fine. */
function pondGap(x: number, z: number) {
  // Water of island.ts: radius r, stretched 1.12 in x and 0.9 in z (+-6 % jitter).
  const r = POND.r * 1.06;
  const k = Math.hypot((x - POND.x) / (r * 1.12), (z - POND.z) / (r * 0.9));
  return Math.hypot(x - POND.x, z - POND.z) * (1 - 1 / k);
}

const obstacles = ISLAND.filter((p) => p.key !== 'cloud' && !p.id.startsWith('grass'));
// From a character's centre: its half-width (~0.2 m) plus the model's radius
// (Polyfork bounds: tree trunk and low canopy, 0.5 m bush/rock/fern, 0.14 m flowers).
const clearanceOf = (id: string) => (id.startsWith('cherry') ? 1.0 : id.startsWith('leafy') || id.startsWith('field-rock') || id.startsWith('fern') ? 0.75 : 0.34);

describe('stroll path', () => {
  it('is a closed loop around the pond', () => {
    const path = strollPath();
    const a = path.at(0);
    const b = path.at(path.length);
    expect(Math.hypot(a.x - b.x, a.z - b.z)).toBeLessThan(1e-6);
    expect(path.length).toBeGreaterThan(10);
    // The pond centre is inside the loop: the heading turns a full circle.
    let turn = 0;
    let prev = path.at(0).heading;
    for (let i = 1; i <= 400; i++) {
      const h = path.at((i / 400) * path.length).heading;
      let d = h - prev;
      while (d > Math.PI) d -= 2 * Math.PI;
      while (d < -Math.PI) d += 2 * Math.PI;
      turn += d;
      prev = h;
    }
    expect(Math.abs(Math.abs(turn) - 2 * Math.PI)).toBeLessThan(0.05);
  });
});

describe('duoAt', () => {
  it('is deterministic and loops', () => {
    expect(duoAt(12.3)).toEqual(duoAt(12.3));
    const a = duoAt(5);
    const b = duoAt(5 + STROLL_LOOP_SECONDS);
    expect(b[0].x).toBeCloseTo(a[0].x, 6);
    expect(b[1].z).toBeCloseTo(a[1].z, 6);
  });

  it('keeps both characters on the meadow, out of the pond and clear of trees, rocks and flowers', () => {
    for (const t of times) {
      for (const c of duoAt(t)) {
        expect(Math.hypot(c.x, c.z), `on the island at ${t}`).toBeLessThan(ISLAND_RADIUS - 1.5);
        expect(pondGap(c.x, c.z), `out of the pond at ${t}`).toBeGreaterThan(0.3);
        for (const o of obstacles) {
          const d = Math.hypot(c.x - o.x, c.z - o.z);
          expect(d, `${o.id} at ${o.x},${o.z} vs ${c.x.toFixed(2)},${c.z.toFixed(2)} (t=${t.toFixed(1)})`).toBeGreaterThan(clearanceOf(o.id));
        }
      }
    }
  });

  it('keeps the two close together and never overlapping', () => {
    for (const t of times) {
      const [a, b] = duoAt(t);
      const d = Math.hypot(a.x - b.x, a.z - b.z);
      expect(d).toBeGreaterThan(0.55);
      expect(d).toBeLessThan(DUO_SPACING + 0.4);
    }
  });

  it('alternates walking and idle pauses, both characters together', () => {
    const states = times.map((t) => duoAt(t).map((c) => c.walking));
    for (const [a, b] of states) expect(a).toBe(b);
    const walking = states.filter(([a]) => a).length / SAMPLES;
    expect(walking).toBeGreaterThan(0.5);
    expect(walking).toBeLessThan(0.9);
    let pauses = 0;
    for (let i = 0; i < SAMPLES; i++) if (states[i][0] && !states[(i + 1) % SAMPLES][0]) pauses++;
    expect(pauses).toBeGreaterThanOrEqual(2);
  });

  it('walks at a stroll (no sliding feet) and turns smoothly', () => {
    const dt = STROLL_LOOP_SECONDS / SAMPLES;
    for (let i = 0; i < SAMPLES; i++) {
      const a = duoAt(times[i]);
      const b = duoAt(times[i] + dt);
      for (const k of [0, 1]) {
        const v = Math.hypot(b[k].x - a[k].x, b[k].z - a[k].z) / dt;
        expect(v, `speed at ${times[i]}`).toBeLessThan(1.2);
        let dh = b[k].heading - a[k].heading;
        while (dh > Math.PI) dh -= 2 * Math.PI;
        while (dh < -Math.PI) dh += 2 * Math.PI;
        expect(Math.abs(dh) / dt, `turn rate at ${times[i]}`).toBeLessThan(3);
      }
    }
  });
});
