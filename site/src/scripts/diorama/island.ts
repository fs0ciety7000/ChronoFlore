// The floating island: a home-made low-poly slab plus the Polyfork pieces that
// stand on it. Sizes are real metres and every model's origin is on the ground,
// so nothing is rescaled. This module has no relative imports because
// scripts/fetch-models.mjs loads it straight from Node to list the models.
import * as THREE from 'three';

export type Placement = {
  id: string;
  x: number;
  z: number;
  /** Yaw in radians. */
  ry?: number;
  /** Vertical offset in metres (clouds only: they are built 9 m up). */
  y?: number;
  /** Role in the scene; plants with a key react to the pointer. */
  key?: 'tree' | 'flower' | 'plant' | 'rock' | 'cloud';
};

export const ISLAND_RADIUS = 12;
export const POND = { x: 3.4, z: 2.6, r: 2.3 };

export const ALLOWED_IDS = [
  'cherry-blossom-tree-3f7ab7',
  'pastel-flowering-plant-d16a03',
  'wildflower-plant-cf4279',
  'fern-plant-1559b8',
  'leafy-bush-d37bba',
  'grass-tuft-62e90c',
  'field-rock-5e37c6',
  'towering-cloud-2e00f1',
] as const;

const TREE = 'cherry-blossom-tree-3f7ab7';
const PASTEL = 'pastel-flowering-plant-d16a03';
const WILD = 'wildflower-plant-cf4279';
const FERN = 'fern-plant-1559b8';
const BUSH = 'leafy-bush-d37bba';
const GRASS = 'grass-tuft-62e90c';
const ROCK = 'field-rock-5e37c6';
const CLOUD = 'towering-cloud-2e00f1';

// Deterministic scatter (mulberry32) so the island is the same on every load.
function rng(seed: number) {
  let a = seed;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function compose(): Placement[] {
  const out: Placement[] = [];
  const rand = rng(7);
  const r2 = (n: number) => Math.round(n * 100) / 100;
  const spacing: Record<string, number> = { [TREE]: 2.2, [BUSH]: 0.6, [ROCK]: 0.6, [FERN]: 0.55 };
  const clearance = (id: string) => spacing[id] ?? 0.22;
  const free = (id: string, x: number, z: number) => {
    if (Math.hypot(x, z) > ISLAND_RADIUS - 1) return false;
    if (Math.hypot(x - POND.x, z - POND.z) < POND.r + 0.35) return false;
    return out.every((p) => Math.hypot(p.x - x, p.z - z) >= clearance(id) + clearance(p.id));
  };
  const put = (id: string, x: number, z: number, key: Placement['key']) => {
    out.push({ id, x: r2(x), z: r2(z), ry: r2(rand() * Math.PI * 2), key });
  };
  /** Scatter `n` copies of `id` around (cx, cz) within `spread` metres. */
  const cluster = (id: string, cx: number, cz: number, n: number, spread: number, key: Placement['key']) => {
    for (let placed = 0, tries = 0; placed < n && tries < n * 40; tries++) {
      const a = rand() * Math.PI * 2;
      const d = Math.sqrt(rand()) * spread;
      const x = cx + Math.cos(a) * d;
      const z = cz + Math.sin(a) * d;
      if (free(id, x, z)) {
        put(id, x, z, key);
        placed++;
      }
    }
  };

  // Three cherry trees frame the meadow; the pond sits in the open.
  for (const [x, z] of [
    [-5.2, -3.6],
    [3.6, -5.6],
    [-2.6, 6.2],
  ]) put(TREE, x, z, 'tree');

  // Bushes, ferns and rocks give the edges some weight.
  for (const [x, z] of [
    [-8.4, 1.2],
    [7.8, -2.4],
    [0.4, -8.6],
    [6.2, 6.8],
    [-7.6, -6.2],
  ]) cluster(BUSH, x, z, 1, 0.6, 'plant');
  for (const [x, z] of [
    [-3.4, -6.8],
    [5.6, -7.8],
    [-6.6, 4.4],
    [1.2, 8.8],
    [8.8, 2.2],
  ]) cluster(FERN, x, z, 1, 0.8, 'plant');
  for (const [x, z] of [
    [6.2, 0.6],
    [-9.4, -2.6],
    [1.8, 5.8],
    [-0.8, -4.2],
  ]) cluster(ROCK, x, z, 1, 0.4, 'rock');

  // Flower beds: pastel blooms around the pond and under the trees, wildflowers
  // and grass across the meadow.
  cluster(PASTEL, 0.2, 4.4, 10, 1.3, 'flower');
  cluster(PASTEL, -4.4, -1.0, 9, 1.2, 'flower');
  cluster(PASTEL, 5.8, -3.2, 9, 1.1, 'flower');
  cluster(PASTEL, -5.4, 7.4, 8, 1.0, 'flower');
  cluster(PASTEL, 7.6, 4.6, 8, 1.0, 'flower');
  cluster(WILD, -1.4, 0.8, 8, 1.6, 'flower');
  cluster(WILD, 3.6, 7.8, 7, 1.2, 'flower');
  cluster(WILD, -7.8, -3.4, 7, 1.2, 'flower');
  cluster(GRASS, 0, 0, 40, 10, 'plant');

  // Clouds drift around the island, off its edge and below its rim, so it
  // floats above them. They are built 9 m up: a uniform drop brings them level.
  for (const [x, z, y] of [
    [-21, -9, -18],
    [19, -14, -19],
    [-15, 19, -20],
    [22, 12, -17],
  ]) out.push({ id: CLOUD, x, z, y, ry: r2(rand() * Math.PI * 2), key: 'cloud' });

  return out;
}

export const ISLAND: Placement[] = compose();

/** Unique Polyfork ids used by the island, in first-use order. */
export function modelIds(): string[] {
  return [...new Set(ISLAND.map((p) => p.id))];
}

/* ------------------------------------------------------------------------ */
/* Home-made base: meadow top, earthy flanks tapering to a rocky point.      */
/* ------------------------------------------------------------------------ */

const MEADOW = ['#b9e4ad', '#b1dea4', '#c2e9b6'];
const LIP = '#9fd293';
const EARTH_TOP = '#a9795a';
const EARTH_LOW = '#8c6148';
const STONE = '#7d5843';
const WATER = '#9fd8e3';
const SHORE = '#eef3df';

/** Low-poly island base (non-indexed, vertex colours, flat shaded). */
export function buildIslandBase(): THREE.Group {
  const rand = rng(11);
  const group = new THREE.Group();
  const material = new THREE.MeshStandardMaterial({ vertexColors: true, flatShading: true, roughness: 0.95 });

  const SEG = 26;
  const ring = (radius: number, y: number, jitterR: number, jitterY: number, twist = 0) =>
    Array.from({ length: SEG }, (_, i) => {
      const a = ((i + twist) / SEG) * Math.PI * 2;
      const r = radius + (rand() - 0.5) * jitterR;
      return new THREE.Vector3(Math.cos(a) * r, y + (rand() - 0.5) * jitterY, Math.sin(a) * r);
    });

  const positions: number[] = [];
  const colors: number[] = [];
  const c = new THREE.Color();
  const e1 = new THREE.Vector3();
  const e2 = new THREE.Vector3();
  /** Adds a triangle, flipped if needed so it faces up (top) or outward (flanks). */
  const tri = (a: THREE.Vector3, b: THREE.Vector3, d: THREE.Vector3, hex: string, facing: 'up' | 'out') => {
    const n = e1.subVectors(b, a).cross(e2.subVectors(d, a));
    const cx = (a.x + b.x + d.x) / 3;
    const cz = (a.z + b.z + d.z) / 3;
    const ok = facing === 'up' ? n.y > 0 : n.x * cx + n.z * cz > 0;
    const [p, q] = ok ? [b, d] : [d, b];
    positions.push(a.x, a.y, a.z, p.x, p.y, p.z, q.x, q.y, q.z);
    c.set(hex);
    for (let k = 0; k < 3; k++) colors.push(c.r, c.g, c.b);
  };
  const band = (upper: THREE.Vector3[], lower: THREE.Vector3[], hex: () => string, facing: 'up' | 'out') => {
    for (let i = 0; i < SEG; i++) {
      const j = (i + 1) % SEG;
      tri(upper[i], lower[i], upper[j], hex(), facing);
      tri(upper[j], lower[i], lower[j], hex(), facing);
    }
  };
  const pick = (list: string[]) => () => list[Math.floor(rand() * list.length)];

  // Top: concentric rings, gently undulating, the rim a touch lower.
  const centre = new THREE.Vector3(0.3, 0.05, -0.2);
  // Alternate rings are twisted half a segment so the facets do not line up
  // into a radial star.
  const rings = [
    ring(2.4, 0.05, 0.5, 0.02),
    ring(4.8, 0.04, 0.6, 0.1, 0.5),
    ring(7.2, 0.02, 0.6, 0.12),
    ring(9.6, 0, 0.5, 0.1, 0.5),
    ring(ISLAND_RADIUS, -0.08, 0.3, 0.06),
  ];
  for (let i = 0; i < SEG; i++) tri(centre, rings[0][i], rings[0][(i + 1) % SEG], pick(MEADOW)(), 'up');
  for (let k = 0; k < rings.length - 1; k++) band(rings[k], rings[k + 1], pick(MEADOW), 'up');

  // Flanks: grassy lip, two earth layers, then a stony point.
  const rim = rings[rings.length - 1];
  const lip = rim.map((v) => new THREE.Vector3(v.x * 1.01, v.y - 0.55, v.z * 1.01));
  const earth1 = ring(11.5, -2.8, 0.8, 0.5, 0.5);
  const earth2 = ring(9.8, -5.6, 1.2, 0.8);
  const stone1 = ring(6.6, -8.6, 1.2, 0.9, 0.5);
  const stone2 = ring(3.2, -11.4, 0.9, 0.8);
  band(rim, lip, () => LIP, 'out');
  band(lip, earth1, pick([EARTH_TOP, EARTH_TOP, '#b3866a']), 'out');
  band(earth1, earth2, pick([EARTH_TOP, EARTH_LOW, EARTH_LOW]), 'out');
  band(earth2, stone1, pick([EARTH_LOW, EARTH_LOW, STONE]), 'out');
  band(stone1, stone2, pick([STONE, EARTH_LOW]), 'out');
  const stone = stone2;
  const tip = new THREE.Vector3(0.5, -14.5, -0.3);
  for (let i = 0; i < SEG; i++) tri(stone[i], tip, stone[(i + 1) % SEG], pick([STONE, EARTH_LOW])(), 'out');

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geometry.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
  geometry.computeVertexNormals();
  const base = new THREE.Mesh(geometry, material);
  base.receiveShadow = true;
  base.castShadow = true;
  base.name = 'island-base';
  group.add(base);

  // Pond: a shore ring and the water, laid just above the meadow.
  const pondSeg = 14;
  const pondShape = (r: number) =>
    new THREE.Shape(
      Array.from({ length: pondSeg }, (_, i) => {
        const a = (i / pondSeg) * Math.PI * 2;
        const k = r * (1 + (rand() - 0.5) * 0.12);
        return new THREE.Vector2(Math.cos(a) * k * 1.12, Math.sin(a) * k * 0.9);
      }),
    );
  const flat = (shape: THREE.Shape, hex: string, y: number) => {
    const g = new THREE.ShapeGeometry(shape);
    g.rotateX(-Math.PI / 2);
    const m = new THREE.Mesh(g, new THREE.MeshStandardMaterial({ color: hex, flatShading: true, roughness: 0.6 }));
    m.position.set(POND.x, y, POND.z);
    m.receiveShadow = true;
    return m;
  };
  const shore = flat(pondShape(POND.r + 0.35), SHORE, 0.1);
  const water = flat(pondShape(POND.r), WATER, 0.13);
  water.name = 'pond';
  group.add(shore, water);
  return group;
}
