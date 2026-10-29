// Live diorama: the floating island rendered with three.js. Loaded on demand
// by loader.ts (its own chunk), never in the initial bundle.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { mergeVertices } from 'three/addons/utils/BufferGeometryUtils.js';
import { compileGently, fadeTo, instantiate, loadCharacters, type CharacterInstance } from '../characters-3d';
import { lightAt } from '../lighting';
import { clampProgress, dawnFactor, nightFactor } from '../timeline';
import { DESKTOP_MIN, ISLAND_SCREEN_RADIUS_M, focusRect, metresPerPixel } from './framing';
import { ISLAND, buildIslandBase, type Placement } from './island';
import { WALK_SPEED, duoAt } from './stroll';

export type Diorama = {
  setProgress(p: number): void;
  /** Pointer in viewport coordinates, -1..1 on both axes (y down). */
  setPointer(nx: number, ny: number): void;
  /** 0 = hero composition, 1 = island resting in the right-hand lane (desktop). */
  setGlide(g: number): void;
  dispose(): void;
};

type Options = { onReady(): void; onError(e: unknown): void };

const MODELS_URL = '/models/polyfork/';
const DEG = Math.PI / 180;
const TURN_SECONDS = 120; // one island revolution
const FIREFLIES = 40;
const PETALS = 48;
const PETALS_PER_HOVER = 6;

// Emissive weight per role: blossoms glow softly, flower beds glow bright.
const GLOW_WEIGHT: Partial<Record<NonNullable<Placement['key']>, number>> = { tree: 0.55, flower: 1.5, plant: 0.3 };

const smoothstep = (a: number, b: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const damp = (dt: number, rate: number) => 1 - Math.exp(-dt * rate);

/** Patches a Polyfork material so its pink/warm vertex colours glow at night. */
function addGlow(material: THREE.Material, uniform: { value: number }) {
  material.onBeforeCompile = (shader) => {
    shader.uniforms.uGlow = uniform;
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', '#include <common>\nuniform float uGlow;')
      .replace(
        '#include <emissivemap_fragment>',
        `#include <emissivemap_fragment>
#ifdef USE_COLOR
  // Petals (pink, orange, violet) glow; leaves, wood and stone stay dark.
  float bloom = smoothstep(0.1, 0.35, max(vColor.r, vColor.b) - vColor.g);
  totalEmissiveRadiance += vColor.rgb * bloom * uGlow;
#endif`,
      );
  };
  material.customProgramCacheKey = () => 'chronoflore-glow';
}

function dotTexture(): THREE.CanvasTexture {
  const size = 64;
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d')!;
  const grad = g.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  grad.addColorStop(0, 'rgba(255,255,255,1)');
  grad.addColorStop(0.25, 'rgba(255,255,255,0.85)');
  grad.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, size, size);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

/** Soft cloud look: smooth normals, near-white, lit a little from within. */
function softenCloud(mesh: THREE.Mesh, material: THREE.MeshStandardMaterial) {
  const g = mesh.geometry.clone();
  g.deleteAttribute('normal');
  const smooth = mergeVertices(g, 1e-3);
  g.dispose();
  smooth.computeVertexNormals();
  mesh.geometry = smooth;
  mesh.material = material;
}

type Swayer = { obj: THREE.Object3D; box: THREE.Box3; amp: number; start: number; petal: THREE.Color };
type Stroller = CharacterInstance & { current?: THREE.AnimationAction };

export function createDiorama(canvas: HTMLCanvasElement, opts: Options): Diorama {
  // Phones and tablets: fewer pixels and no shadow pass.
  const phone = matchMedia('(pointer: coarse)').matches || window.innerWidth < 768;
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
  renderer.toneMapping = THREE.NoToneMapping; // Polyfork colours are authored without ACES
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, phone ? 1.5 : 2));
  renderer.shadowMap.enabled = !phone;
  renderer.shadowMap.type = THREE.PCFShadowMap; // soft by default since r182

  const scene = new THREE.Scene();
  const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 1, 400);
  const target = new THREE.Vector3(0, -2.5, 0);

  const hemi = new THREE.HemisphereLight();
  const sun = new THREE.DirectionalLight();
  sun.castShadow = !phone;
  sun.shadow.mapSize.set(2048, 2048);
  Object.assign(sun.shadow.camera, { left: -17, right: 17, top: 17, bottom: -17, near: 1, far: 90 });
  sun.shadow.bias = -0.0004;
  sun.shadow.normalBias = 0.03;
  scene.add(hemi, sun, sun.target);

  // Fog in the page colour gives the far clouds some air.
  const fog = new THREE.Fog('#ffffff', 94, 128);
  scene.fog = fog;

  const island = new THREE.Group();
  const clouds = new THREE.Group();
  scene.add(island, clouds);

  const base = buildIslandBase();
  island.add(base);
  const pond = base.getObjectByName('pond') as THREE.Mesh<THREE.BufferGeometry, THREE.MeshStandardMaterial>;

  // Fireflies: soft dots hovering over the meadow, visible at night only.
  const dot = dotTexture();
  const flyBase = new Float32Array(FIREFLIES * 3);
  const flyPos = new Float32Array(FIREFLIES * 3);
  for (let i = 0; i < FIREFLIES; i++) {
    const a = Math.random() * Math.PI * 2;
    const r = Math.sqrt(Math.random()) * 10.5;
    flyBase.set([Math.cos(a) * r, 0.6 + Math.random() * 3.6, Math.sin(a) * r], i * 3);
  }
  flyPos.set(flyBase);
  const flyGeo = new THREE.BufferGeometry();
  flyGeo.setAttribute('position', new THREE.BufferAttribute(flyPos, 3));
  const flyMat = new THREE.PointsMaterial({
    color: '#fff4b8',
    map: dot,
    size: 9, // CSS pixels: three multiplies by the pixel ratio
    sizeAttenuation: false,
    transparent: true,
    opacity: 0,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  });
  const fireflies = new THREE.Points(flyGeo, flyMat);
  fireflies.visible = false;
  island.add(fireflies);

  // Petals released by a hovered plant: a small instanced pool, faded by scale.
  const petalGeo = new THREE.OctahedronGeometry(0.26, 0);
  petalGeo.scale(1, 0.3, 0.7);
  const petalMat = new THREE.MeshStandardMaterial({ flatShading: true, roughness: 0.7 });
  const petals = new THREE.InstancedMesh(petalGeo, petalMat, PETALS);
  petals.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
  petals.frustumCulled = false;
  const petalState = Array.from({ length: PETALS }, () => ({
    life: 0,
    pos: new THREE.Vector3(),
    vel: new THREE.Vector3(),
    spin: new THREE.Euler(),
    spinRate: new THREE.Vector3(),
  }));
  const zero = new THREE.Matrix4().makeScale(0, 0, 0);
  for (let i = 0; i < PETALS; i++) {
    petals.setMatrixAt(i, zero);
    petals.setColorAt(i, new THREE.Color('#f6b3c9'));
  }
  island.add(petals);
  let nextPetal = 0;

  const swayers: Swayer[] = [];
  // The heroine and her companion strolling around the pond (stroll.ts).
  const duo: Stroller[] = [];
  // A soft contact shadow under each of them (cheaper than casting skinned
  // shadows, and readable at this size).
  const footGeo = new THREE.CircleGeometry(0.36, 20);
  footGeo.rotateX(-Math.PI / 2);
  footGeo.scale(1, 1, 0.75);
  const footMat = new THREE.MeshBasicMaterial({ color: '#3b3350', map: dot, transparent: true, opacity: 0.3, depthWrite: false });
  const groundRay = new THREE.Raycaster();
  const down = new THREE.Vector3(0, -1, 0);
  const probe = new THREE.Vector3();
  const glowUniforms: { uniform: { value: number }; weight: number }[] = [];
  const materialCache = new Map<string, THREE.Material>();
  const timer = new THREE.Timer();
  timer.connect(document);

  // Clouds share one soft material whose inner light follows the sky.
  const cloudMat = new THREE.MeshStandardMaterial({ color: '#ffffff', vertexColors: true, roughness: 1, emissive: '#ffffff', emissiveIntensity: 0.3 });
  const replaced = new Set<THREE.Material>();

  // State driven from outside.
  let progressTarget = 0;
  let progress = 0;
  let glideTarget = 0;
  let glide = 0;
  let lastRender = 0;
  let islandAttr = '';
  const pointerTarget = new THREE.Vector2();
  const pointer = new THREE.Vector2();
  let pointerDirty = false;
  let hovered: Swayer | null = null;

  let ready = false;
  let disposed = false;
  let raf = 0;
  let onScreen = true;
  let width = 0;
  let height = 0;

  const resize = () => {
    const w = canvas.clientWidth || window.innerWidth;
    const h = canvas.clientHeight || window.innerHeight;
    if (w === width && h === height) return;
    width = w;
    height = h;
    renderer.setSize(w, h, false);
  };
  const resizeObserver = new ResizeObserver(resize);
  resizeObserver.observe(canvas);

  const host = canvas.parentElement ?? canvas;
  const io = new IntersectionObserver((entries) => {
    onScreen = entries[entries.length - 1].isIntersecting;
    schedule();
  });
  io.observe(host);
  const onVisibility = () => schedule();
  document.addEventListener('visibilitychange', onVisibility);

  function schedule() {
    const run = ready && !disposed && onScreen && !document.hidden;
    if (run && !raf) raf = requestAnimationFrame(frame);
    if (!run && raf) {
      cancelAnimationFrame(raf);
      raf = 0;
    }
  }

  const light = { background: new THREE.Color(), sky: new THREE.Color(), ground: new THREE.Color(), sun: new THREE.Color() };
  const ray = new THREE.Raycaster();
  const localRay = new THREE.Ray();
  const inverse = new THREE.Matrix4();
  const hit = new THREE.Vector3();
  const tmpMatrix = new THREE.Matrix4();
  const tmpQuat = new THREE.Quaternion();
  const tmpScale = new THREE.Vector3();

  function placeCamera(dt: number) {
    const p = progress;
    const dive = smoothstep(0.04, 0.62, p);
    const dawn = dawnFactor(p);
    const g = width >= DESKTOP_MIN ? glide : 0;
    pointer.lerp(pointerTarget, damp(dt, 4));
    // Scroll lowers the camera toward the island (35° -> 22°) and moves in;
    // the dawn pulls back a little. The pointer adds a ±3° parallax.
    const elevation = (lerp(35, 22, dive) + lerp(0, 6, dawn) - pointer.y * 3) * DEG;
    const azimuth = (45 + pointer.x * 3) * DEG;
    const dist = 90;
    camera.position.set(
      target.x + Math.cos(elevation) * Math.sin(azimuth) * dist,
      target.y + Math.sin(elevation) * dist,
      target.z + Math.cos(elevation) * Math.cos(azimuth) * dist,
    );
    camera.lookAt(target);

    // Orthographic frustum laid out so the target lands on the focus point.
    const f = focusRect(width, height, dive, g);
    const s = metresPerPixel(f.size);
    camera.left = -f.x * s;
    camera.right = (width - f.x) * s;
    camera.top = f.y * s;
    camera.bottom = -(height - f.y) * s;
    // A slight push-in while the island is the hero; none once it rests in the lane.
    camera.zoom = 1 + (0.12 * dive - 0.06 * dawn) * (1 - g);
    camera.updateProjectionMatrix();

    // Clouds tuck in under the island as it moves into the lane (and always on
    // small screens, where the copy runs full width), so none drifts out under
    // the text; they also sink so they never poke through the meadow.
    const tuck = width < DESKTOP_MIN ? 1 : g;
    const k = lerp(1, 0.38, tuck);
    for (const c of clouds.children) {
      c.position.set(c.userData.x * k, c.userData.y + c.userData.bob - 5.5 * tuck, c.userData.z * k);
    }

    // Published for the e2e test that keeps copy clear of the island.
    const r = (ISLAND_SCREEN_RADIUS_M / s) * camera.zoom;
    const attr = `${Math.round(f.x)},${Math.round(f.y)},${Math.round(r)}`;
    if (attr !== islandAttr) host.dataset.island = islandAttr = attr;
  }

  function applyLight() {
    // Unsmoothed: the sky must match the page colour (--bg) in the same frame,
    // so the island never sits on a different sky than the page while scrolling.
    const p = progressTarget;
    const l = lightAt(nightFactor(p), dawnFactor(p));
    scene.background = light.background.set(l.background);
    fog.color.copy(light.background);
    hemi.color.copy(light.sky.set(l.hemiSky));
    cloudMat.emissive.copy(light.sky);
    cloudMat.emissiveIntensity = 0.3 * (1 - 0.7 * l.glow); // soft by day, dim at night
    cloudMat.color.setScalar(1 - 0.35 * l.glow);
    hemi.groundColor.copy(light.ground.set(l.hemiGround));
    hemi.intensity = l.hemiIntensity;
    sun.color.copy(light.sun.set(l.sunColor));
    sun.intensity = l.sunIntensity;
    // The sun sits front-left of the camera and sinks with the hour.
    const el = l.sunElevationDeg * DEG;
    const az = (45 - 70) * DEG;
    sun.position.set(Math.cos(el) * Math.sin(az) * 40, Math.sin(el) * 40, Math.cos(el) * Math.cos(az) * 40);
    sun.target.position.set(0, 0, 0);
    for (const g of glowUniforms) g.uniform.value = l.glow * g.weight;
    pond.material.emissive.set('#5fc3d6');
    pond.material.emissiveIntensity = l.glow * 0.45;
    flyMat.opacity = l.glow;
    footMat.opacity = 0.3 - 0.14 * l.glow;
    fireflies.visible = l.glow > 0.01;
    return l;
  }

  function updateHover(now: number) {
    if (!pointerDirty) return;
    pointerDirty = false;
    ray.setFromCamera(new THREE.Vector2(pointerTarget.x, -pointerTarget.y), camera);
    inverse.copy(island.matrixWorld).invert();
    localRay.copy(ray.ray).applyMatrix4(inverse);
    let best: Swayer | null = null;
    let bestDist = Infinity;
    for (const s of swayers) {
      if (localRay.intersectBox(s.box, hit)) {
        const d = hit.distanceToSquared(localRay.origin);
        if (d < bestDist) {
          bestDist = d;
          best = s;
        }
      }
    }
    if (best && best !== hovered && now - best.start > 0.9) {
      best.start = now;
      emitPetals(best);
    }
    hovered = best;
  }

  function emitPetals(s: Swayer) {
    const top = new THREE.Vector3((s.box.min.x + s.box.max.x) / 2, s.box.max.y - 0.1, (s.box.min.z + s.box.max.z) / 2);
    const spread = Math.min(1.2, (s.box.max.x - s.box.min.x) / 2);
    for (let k = 0; k < PETALS_PER_HOVER; k++) {
      const i = nextPetal;
      nextPetal = (nextPetal + 1) % PETALS;
      const st = petalState[i];
      st.life = 1;
      st.pos.set(top.x + (Math.random() - 0.5) * spread, top.y, top.z + (Math.random() - 0.5) * spread);
      st.vel.set((Math.random() - 0.5) * 1.4, 1.1 + Math.random() * 0.9, (Math.random() - 0.5) * 1.4);
      st.spinRate.set(Math.random() * 6 - 3, Math.random() * 6 - 3, Math.random() * 6 - 3);
      petals.setColorAt(i, s.petal);
    }
    if (petals.instanceColor) petals.instanceColor.needsUpdate = true;
  }

  function updatePetals(dt: number) {
    let any = false;
    for (let i = 0; i < PETALS; i++) {
      const st = petalState[i];
      if (st.life <= 0) continue;
      any = true;
      st.life -= dt / 2.2;
      st.vel.y -= 1.6 * dt;
      st.vel.multiplyScalar(1 - 0.9 * dt);
      st.pos.addScaledVector(st.vel, dt);
      st.spin.x += st.spinRate.x * dt;
      st.spin.y += st.spinRate.y * dt;
      st.spin.z += st.spinRate.z * dt;
      const k = st.life > 0 ? Math.sin(Math.min(1, st.life * 1.4) * Math.PI * 0.5) : 0;
      tmpQuat.setFromEuler(st.spin);
      tmpMatrix.compose(st.pos, tmpQuat, tmpScale.setScalar(k));
      petals.setMatrixAt(i, st.life > 0 ? tmpMatrix : zero);
    }
    if (any) petals.instanceMatrix.needsUpdate = true;
  }

  function updateSway(now: number) {
    for (const s of swayers) {
      const t = now - s.start;
      if (t > 3) {
        if (s.obj.rotation.x !== 0 || s.obj.rotation.z !== 0) s.obj.rotation.x = s.obj.rotation.z = 0;
        continue;
      }
      const a = s.amp * Math.exp(-t * 1.8) * Math.sin(t * 9);
      s.obj.rotation.z = a;
      s.obj.rotation.x = a * 0.4;
    }
  }

  function updateFireflies(now: number) {
    if (!fireflies.visible) return;
    for (let i = 0; i < FIREFLIES; i++) {
      const o = i * 3;
      flyPos[o] = flyBase[o] + Math.sin(now * 0.35 + i * 1.7) * 0.9;
      flyPos[o + 1] = flyBase[o + 1] + Math.sin(now * 0.8 + i * 2.3) * 0.5;
      flyPos[o + 2] = flyBase[o + 2] + Math.cos(now * 0.3 + i * 0.9) * 0.9;
    }
    flyGeo.attributes.position.needsUpdate = true;
    flyMat.size = 8 + 2.5 * Math.sin(now * 2);
  }

  function updateDuo(now: number, dt: number) {
    if (!duo.length) return;
    const poses = duoAt(now);
    duo.forEach((c, i) => {
      const pose = poses[i];
      // Stand on the meadow, which undulates by a few centimetres.
      groundRay.set(island.localToWorld(probe.set(pose.x, 2, pose.z)), down);
      const hit = groundRay.intersectObject(base, true)[0];
      const y = hit ? island.worldToLocal(probe.copy(hit.point)).y : 0;
      c.root.position.set(pose.x, y, pose.z);
      c.root.rotation.y = pose.heading;
      const next = pose.walking ? c.actions.Walk : c.actions.Idle;
      if (next !== c.current) {
        fadeTo(c.current, next, 0.35);
        c.current = next;
      }
      // Stride follows the speed so the feet do not slide while easing in and out.
      c.actions.Walk.timeScale = Math.max(0.45, pose.speed / WALK_SPEED);
      c.mixer.update(dt);
    });
  }

  function render(dt: number) {
    const now = timer.getElapsed();
    progress = lerp(progress, progressTarget, damp(dt, 6));
    if (Math.abs(progress - progressTarget) < 1e-4) progress = progressTarget;
    glide = lerp(glide, glideTarget, damp(dt, 5));
    if (Math.abs(glide - glideTarget) < 1e-3) glide = glideTarget;
    island.rotation.y = (now / TURN_SECONDS) * Math.PI * 2;
    // Clouds stay on their side of the island (off the hero copy) and bob.
    clouds.children.forEach((c, i) => {
      c.userData.bob = Math.sin(now * 0.25 + i * 1.3) * 0.6;
      c.rotation.y = (c.userData.ry as number) + Math.sin(now * 0.05 + i) * 0.2;
    });
    placeCamera(dt);
    applyLight();
    island.updateMatrixWorld();
    updateHover(now);
    updateSway(now);
    updatePetals(dt);
    updateFireflies(now);
    updateDuo(now, dt);
    renderer.render(scene, camera);
  }

  function frame(time: number) {
    raf = 0;
    if (disposed) return;
    // Resting small in the lane: ~30 fps is plenty for a slow turn.
    if (glide > 0.98 && glideTarget > 0.98 && time - lastRender < 32) {
      schedule();
      return;
    }
    lastRender = time;
    timer.update(time);
    const dt = Math.min(Math.max(timer.getDelta(), 0), 0.1);
    render(dt);
    schedule();
  }

  async function load() {
    const res = await fetch(`${MODELS_URL}manifest.json`, { cache: 'no-cache' });
    if (!res.ok) throw new Error(`manifest: HTTP ${res.status}`);
    const manifest = (await res.json()) as Record<string, string>;
    const loader = new GLTFLoader();
    const ids = [...new Set(ISLAND.map((p) => p.id))];
    const models = new Map<string, THREE.Object3D>();
    // The characters load alongside; the island does not wait on (or fail with) them.
    const characters = loadCharacters();
    characters.catch(() => {});
    await Promise.all(
      ids.map(async (id) => {
        const file = manifest[id];
        if (!file) throw new Error(`manifest: no file for ${id}`);
        const gltf = await loader.loadAsync(MODELS_URL + file);
        models.set(id, gltf.scene);
      }),
    );
    if (disposed) return;

    for (const p of ISLAND) {
      const obj = models.get(p.id)!.clone();
      obj.position.set(p.x, p.y ?? 0, p.z);
      obj.rotation.y = p.ry ?? 0;
      const weight = GLOW_WEIGHT[p.key ?? 'rock'] ?? 0;
      obj.traverse((child) => {
        const mesh = child as THREE.Mesh;
        if (!mesh.isMesh) return;
        mesh.castShadow = p.key === 'tree' || p.key === 'rock' || p.id.startsWith('leafy-bush') || p.id.startsWith('fern');
        mesh.receiveShadow = p.key !== 'cloud';
        if (p.key === 'cloud') {
          replaced.add(mesh.material as THREE.Material);
          softenCloud(mesh, cloudMat);
          return;
        }
        if (weight > 0) {
          // One material per role, so blossoms and flower beds glow differently.
          const src = mesh.material as THREE.MeshStandardMaterial;
          const key = `${src.uuid}:${weight}`;
          let mat = materialCache.get(key);
          if (!mat) {
            mat = src.clone();
            const uniform = { value: 0 };
            addGlow(mat, uniform);
            glowUniforms.push({ uniform, weight });
            materialCache.set(key, mat);
          }
          replaced.add(src);
          mesh.material = mat;
        }
      });
      if (p.key === 'cloud') {
        // Built 9 m up; a uniform offset brings them level with the island.
        Object.assign(obj.userData, { x: p.x, y: p.y ?? 0, z: p.z, ry: p.ry ?? 0, bob: 0 });
        clouds.add(obj);
        continue;
      }
      island.add(obj);
      if (p.key && p.key !== 'rock') {
        obj.updateMatrixWorld(true);
        const box = new THREE.Box3().setFromObject(obj).expandByScalar(p.key === 'tree' ? 0 : 0.25);
        const petal = new THREE.Color(p.id.startsWith('wildflower') ? '#ffd08a' : p.key === 'plant' ? '#b5e3a0' : '#f6b3c9');
        swayers.push({ obj, box, amp: p.key === 'tree' ? 0.035 : 0.16, start: -10, petal });
      }
    }
    resize();
    applyLight();
    renderer.compile(scene, camera);
    ready = true;
    render(0);
    opts.onReady();
    schedule();
    await addDuo(characters);
  }

  /**
   * Adds the strolling pair once the island is live: their shaders compile
   * asynchronously (parallel compile where supported), so the first frame of
   * the island and the page's main thread never wait on them.
   */
  async function addDuo(characters: ReturnType<typeof loadCharacters>) {
    try {
      const { heroine, companion } = await characters;
      if (disposed) return;
      const group = new THREE.Group();
      const pair: Stroller[] = [heroine, companion].map((gltf) => {
        // Real size (about 1.1 m), origin at the feet: placed as authored.
        const c: Stroller = instantiate(gltf);
        c.root.traverse((o) => {
          const mesh = o as THREE.Mesh;
          if (mesh.isMesh) mesh.receiveShadow = true;
        });
        const foot = new THREE.Mesh(footGeo, footMat);
        foot.position.y = 0.02;
        foot.renderOrder = -1;
        c.root.add(foot);
        group.add(c.root);
        return c;
      });
      await compileGently(renderer, group, camera, scene, () => disposed);
      if (disposed) {
        pair.forEach((c) => c.dispose());
        return;
      }
      for (const c of pair) island.add(c.root);
      duo.push(...pair);
      updateDuo(timer.getElapsed(), 0);
    } catch (e) {
      if (!disposed) console.warn('[diorama] island without the duo:', e);
    }
    if (!disposed) host.dataset.duo = String(duo.length);
  }
  load().catch((e) => {
    if (!disposed) opts.onError(e);
  });

  return {
    setProgress(p: number) {
      progressTarget = clampProgress(p);
      if (!ready) progress = progressTarget;
    },
    setGlide(g: number) {
      glideTarget = Math.min(1, Math.max(0, Number.isFinite(g) ? g : 0));
      if (!ready) glide = glideTarget;
    },
    setPointer(nx: number, ny: number) {
      pointerTarget.set(Math.max(-1, Math.min(1, nx)), Math.max(-1, Math.min(1, ny)));
      pointerDirty = true;
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      if (raf) cancelAnimationFrame(raf);
      raf = 0;
      io.disconnect();
      resizeObserver.disconnect();
      document.removeEventListener('visibilitychange', onVisibility);
      timer.dispose();
      for (const c of duo) c.dispose();
      const materials = new Set<THREE.Material>(replaced);
      scene.traverse((o) => {
        const mesh = o as THREE.Mesh;
        // The characters' geometry and materials are shared with the portraits.
        if (o.userData.sharedCharacter) return;
        if (mesh.geometry) mesh.geometry.dispose();
        const mats = mesh.material ? (Array.isArray(mesh.material) ? mesh.material : [mesh.material]) : [];
        mats.forEach((m) => materials.add(m));
      });
      for (const m of materials) {
        // Dispose any texture the material holds (map, emissiveMap, ...).
        for (const value of Object.values(m)) if (value instanceof THREE.Texture) value.dispose();
        m.dispose();
      }
      petals.dispose();
      footGeo.dispose();
      footMat.dispose();
      sun.shadow.dispose();
      dot.dispose();
      renderer.dispose();
      try {
        renderer.forceContextLoss(); // free the GPU context now, not at GC time
      } catch {
        /* already lost */
      }
    },
  };
}
