// Live portraits: the heroine (Planche II) and the companion (Planche III),
// idling and slowly turning, with a net swing on hover, focus or tap.
// One WebGLRenderer, kept off the page, draws both: each frame it renders a
// visible portrait and copies the pixels into that card's 2D canvas, so the
// page never holds more than two WebGL contexts (this one and the diorama's).
// Renders only while a card is on screen and the tab is visible.
import * as THREE from 'three';
import { CHARACTERS, type CharacterKey } from '../characters';
import { compileGently, fadeTo, instantiate, loadCharacters, type CharacterInstance } from '../characters-3d';

export type Portraits = { dispose(): void };
type Options = { onError(e?: unknown): void };

const FOV = 24;
/** Camera framing: the whole figure (about 1.05 m) with air above and the shadow below. */
const CAMERA = new THREE.Vector3(0, 0.8, 3.7);
const LOOK_AT = new THREE.Vector3(0, 0.52, 0);
/** Three-quarter pose, turned toward the text beside the card. */
const FACING: Record<CharacterKey, number> = { heroine: 0.45, companion: -0.45 };
/** Gentle oscillation (never a full turn: the back would show too long). */
const TURN_AMPLITUDE = 0.35;
const TURN_PERIOD = 10;
/** Idle time (s) of the pose used for the still images (render-poster.mjs). */
const STILL_POSE_TIME = 0.5;

type Slot = {
  key: CharacterKey;
  card: HTMLElement;
  canvas: HTMLCanvasElement;
  ctx: CanvasRenderingContext2D;
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  character: CharacterInstance;
  current: THREE.AnimationAction;
  phase: number;
  visible: boolean;
  playing?: boolean;
  shown: boolean;
  cssWidth: number;
  cssHeight: number;
  cleanup: (() => void)[];
};

function shadowTexture(): THREE.CanvasTexture {
  const size = 128;
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d')!;
  const grad = g.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  grad.addColorStop(0, 'rgba(255,255,255,1)');
  grad.addColorStop(0.45, 'rgba(255,255,255,0.55)');
  grad.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, size, size);
  return new THREE.CanvasTexture(c);
}

export function createPortraits(cards: HTMLElement[], opts: Options): Portraits {
  // Still mode: frozen Idle pose at the base angle, for the fallback images.
  const still = document.documentElement.hasAttribute('data-portrait-still');
  const phone = matchMedia('(pointer: coarse)').matches || window.innerWidth < 768;
  const dpr = () => Math.min(window.devicePixelRatio || 1, phone ? 1.5 : 2);

  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, powerPreference: 'high-performance' });
  renderer.toneMapping = THREE.NoToneMapping; // same colour pipeline as the diorama
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.setClearColor(0x000000, 0);
  renderer.setPixelRatio(1); // sizes below are already in device pixels

  const shadowTex = shadowTexture();
  const shadowGeo = new THREE.PlaneGeometry(1.05, 0.75);
  shadowGeo.rotateX(-Math.PI / 2);
  const shadowMat = new THREE.MeshBasicMaterial({ color: '#3b3350', map: shadowTex, transparent: true, opacity: 0.2, depthWrite: false });

  const slots: Slot[] = [];
  const timer = new THREE.Timer();
  timer.connect(document);
  let raf = 0;
  let lastRender = 0;
  const drawSize = new THREE.Vector2();
  let disposed = false;
  let ready = false;

  const onLost = () => opts.onError(new Error('portrait WebGL context lost'));
  renderer.domElement.addEventListener('webglcontextlost', onLost);

  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      const slot = slots.find((s) => s.card === e.target);
      if (slot) slot.visible = e.isIntersecting;
    }
    schedule();
  });
  const ro = new ResizeObserver((entries) => {
    for (const e of entries) {
      const slot = slots.find((s) => s.card === e.target);
      if (!slot) continue;
      slot.cssWidth = e.contentRect.width;
      slot.cssHeight = e.contentRect.height;
    }
  });
  const onVisibility = () => schedule();
  document.addEventListener('visibilitychange', onVisibility);

  function setPlaying(slot: Slot, playing: boolean) {
    if (slot.playing === playing) return;
    slot.playing = playing;
    slot.card.dataset.playing = String(playing);
  }

  function schedule() {
    const running = ready && !disposed && !document.hidden;
    for (const s of slots) setPlaying(s, running && s.visible);
    const run = running && slots.some((s) => s.visible);
    if (run && !raf) raf = requestAnimationFrame(frame);
    if (!run && raf) {
      cancelAnimationFrame(raf);
      raf = 0;
    }
  }

  function draw(slot: Slot, now: number, dt: number) {
    const w = Math.max(1, Math.round(slot.cssWidth * dpr()));
    const h = Math.max(1, Math.round(slot.cssHeight * dpr()));
    if (slot.canvas.width !== w || slot.canvas.height !== h) {
      slot.canvas.width = w;
      slot.canvas.height = h;
    }
    const size = renderer.getSize(drawSize);
    if (size.x !== w || size.y !== h) renderer.setSize(w, h, false);
    if (slot.camera.aspect !== w / h) {
      slot.camera.aspect = w / h;
      slot.camera.updateProjectionMatrix();
    }
    const { root, mixer } = slot.character;
    if (!still) {
      mixer.update(dt);
      root.rotation.y = FACING[slot.key] + TURN_AMPLITUDE * Math.sin(((now + slot.phase) / TURN_PERIOD) * Math.PI * 2);
    }
    renderer.render(slot.scene, slot.camera);
    // Copied in the same task as the render, before the WebGL buffer is presented.
    slot.ctx.clearRect(0, 0, w, h);
    slot.ctx.drawImage(renderer.domElement, 0, 0);
    if (!slot.shown) {
      slot.shown = true;
      slot.card.append(slot.canvas);
      slot.card.dataset.state = 'live';
      slot.card.tabIndex = 0; // focus plays the swing; the card keeps its role="img" label
    }
  }

  function frame(time: number) {
    raf = 0;
    if (disposed) return;
    // ~30 fps: plenty for a slow idle and turn, half the GPU work.
    if (time - lastRender < 32) {
      schedule();
      return;
    }
    lastRender = time;
    timer.update(time);
    const dt = Math.min(Math.max(timer.getDelta(), 0), 0.1);
    const now = timer.getElapsed();
    for (const slot of slots) if (slot.visible && slot.cssWidth > 0) draw(slot, now, dt);
    schedule();
  }

  function swing(slot: Slot) {
    const { Swing } = slot.character.actions;
    if (still || slot.current === Swing) return;
    Swing.setLoop(THREE.LoopOnce, 1);
    Swing.clampWhenFinished = true;
    Swing.timeScale = 0.8; // the authored 0.45 s gesture, a touch softer
    fadeTo(slot.current, Swing, 0.12);
    slot.current = Swing;
    slot.card.dataset.action = 'Swing';
  }

  function buildSlot(card: HTMLElement, key: CharacterKey, character: CharacterInstance, phase: number): Slot {
    const scene = new THREE.Scene();
    const side = Math.sign(FACING[key]);
    scene.add(new THREE.HemisphereLight('#fff4ea', '#b8a9d9', 1.7));
    const key1 = new THREE.DirectionalLight('#fff0dc', 2.3);
    key1.position.set(side * 1.6, 2.6, 2.6);
    const rim = new THREE.DirectionalLight('#f7c3d2', 1.6);
    rim.position.set(-side * 1.8, 1.9, -2.4);
    const shadow = new THREE.Mesh(shadowGeo, shadowMat);
    shadow.position.y = 0.002;
    scene.add(key1, rim, shadow, character.root);
    character.root.rotation.y = FACING[key];

    const camera = new THREE.PerspectiveCamera(FOV, 4 / 5, 0.1, 20);
    camera.position.copy(CAMERA);
    camera.lookAt(LOOK_AT);

    const canvas = document.createElement('canvas');
    canvas.className = 'portrait__canvas';
    canvas.setAttribute('aria-hidden', 'true');
    const ctx = canvas.getContext('2d')!;

    const { Idle } = character.actions;
    Idle.play();
    if (still) character.mixer.setTime(STILL_POSE_TIME);
    card.dataset.action = 'Idle';

    const slot: Slot = {
      key,
      card,
      canvas,
      ctx,
      scene,
      camera,
      character,
      current: Idle,
      phase,
      visible: false,
      shown: false,
      cssWidth: card.clientWidth,
      cssHeight: card.clientHeight,
      cleanup: [],
    };
    const onFinished = (e: { action: THREE.AnimationAction }) => {
      if (e.action !== character.actions.Swing) return;
      fadeTo(character.actions.Swing, Idle, 0.3);
      slot.current = Idle;
      card.dataset.action = 'Idle';
    };
    character.mixer.addEventListener('finished', onFinished);
    const onEnter = (e: PointerEvent) => {
      if (e.pointerType === 'mouse') swing(slot);
    };
    const onDown = (e: PointerEvent) => {
      if (e.pointerType !== 'mouse') swing(slot);
    };
    const onFocus = () => swing(slot);
    card.addEventListener('pointerenter', onEnter);
    card.addEventListener('pointerdown', onDown);
    card.addEventListener('focus', onFocus);
    slot.cleanup.push(
      () => character.mixer.removeEventListener('finished', onFinished),
      () => card.removeEventListener('pointerenter', onEnter),
      () => card.removeEventListener('pointerdown', onDown),
      () => card.removeEventListener('focus', onFocus),
    );
    return slot;
  }

  loadCharacters()
    .then((gltfs) => {
      if (disposed) return;
      cards.forEach((card, i) => {
        const key = card.dataset.portrait as CharacterKey;
        if (!(key in CHARACTERS)) return;
        slots.push(buildSlot(card, key, instantiate(gltfs[key]), i * 3.7));
        io.observe(card);
        ro.observe(card);
      });
      // Parallel shader compile where supported, in small tasks otherwise.
      return slots.reduce((chain, s) => chain.then(() => compileGently(renderer, s.scene, s.camera, s.scene, () => disposed)), Promise.resolve());
    })
    .then(() => {
      if (disposed) return;
      ready = true;
      schedule();
    })
    .catch((e) => {
      if (!disposed) opts.onError(e);
    });

  return {
    dispose() {
      if (disposed) return;
      disposed = true;
      if (raf) cancelAnimationFrame(raf);
      raf = 0;
      io.disconnect();
      ro.disconnect();
      document.removeEventListener('visibilitychange', onVisibility);
      renderer.domElement.removeEventListener('webglcontextlost', onLost);
      timer.dispose();
      for (const s of slots) {
        s.cleanup.forEach((c) => c());
        s.character.dispose();
      }
      // The characters' geometry and materials are shared (characters-3d.ts):
      // the context loss below frees their GPU copies here.
      shadowGeo.dispose();
      shadowMat.dispose();
      shadowTex.dispose();
      renderer.dispose();
      try {
        renderer.forceContextLoss();
      } catch {
        /* already lost */
      }
    },
  };
}
