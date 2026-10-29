// Loads the two home-made characters once and hands out animated instances.
// Shared by the island duo and the portraits (both in deferred chunks), so the
// GLBs are fetched and parsed a single time; each instance is a
// SkeletonUtils.clone (own skeleton, shared geometry and materials) with its
// own AnimationMixer.
import * as THREE from 'three';
import { GLTFLoader, type GLTF } from 'three/addons/loaders/GLTFLoader.js';
import { clone as cloneSkinned } from 'three/addons/utils/SkeletonUtils.js';
import { CHARACTERS, CHARACTER_CLIPS, characterUrl, type CharacterKey, type ClipName } from './characters';

export type CharacterInstance = {
  root: THREE.Object3D;
  mixer: THREE.AnimationMixer;
  actions: Record<ClipName, THREE.AnimationAction>;
  /** Stops the actions and releases the per-instance state (not the shared GLB). */
  dispose(): void;
};

let pending: Promise<Record<CharacterKey, GLTF>> | undefined;

/** Both GLBs, fetched once per page. A failed load can be retried. */
export function loadCharacters(): Promise<Record<CharacterKey, GLTF>> {
  pending ??= (async () => {
    const loader = new GLTFLoader();
    const keys = Object.keys(CHARACTERS) as CharacterKey[];
    const gltfs = await Promise.all(keys.map((k) => loader.loadAsync(characterUrl(k))));
    for (const [i, g] of gltfs.entries()) {
      const names = g.animations.map((c) => c.name);
      const missing = CHARACTER_CLIPS.filter((c) => !names.includes(c));
      if (missing.length) throw new Error(`${keys[i]}: missing clips ${missing.join(', ')}`);
      // Shared across instances (and renderers): never disposed by an instance.
      g.scene.traverse((o) => (o.userData.sharedCharacter = true));
    }
    return Object.fromEntries(keys.map((k, i) => [k, gltfs[i]])) as Record<CharacterKey, GLTF>;
  })();
  pending.catch(() => (pending = undefined));
  return pending;
}

export function instantiate(gltf: GLTF): CharacterInstance {
  const root = cloneSkinned(gltf.scene);
  const mixer = new THREE.AnimationMixer(root);
  const actions = Object.fromEntries(
    CHARACTER_CLIPS.map((name) => [name, mixer.clipAction(THREE.AnimationClip.findByName(gltf.animations, name)!)]),
  ) as Record<ClipName, THREE.AnimationAction>;
  return {
    root,
    mixer,
    actions,
    dispose() {
      mixer.stopAllAction();
      mixer.uncacheRoot(root);
      root.traverse((o) => {
        const skinned = o as THREE.SkinnedMesh;
        if (skinned.isSkinnedMesh) skinned.skeleton.dispose(); // per-clone bone texture
      });
    },
  };
}

/**
 * Compiles the shaders of `object` one mesh at a time, yielding in between:
 * where shaders compile synchronously (no KHR_parallel_shader_compile,
 * software GL), each program is its own short task instead of one long freeze.
 */
export async function compileGently(
  renderer: THREE.WebGLRenderer,
  object: THREE.Object3D,
  camera: THREE.Camera,
  scene: THREE.Scene,
  cancelled: () => boolean,
) {
  const meshes: THREE.Object3D[] = [];
  object.traverse((o) => {
    if ((o as THREE.Mesh).isMesh) meshes.push(o);
  });
  for (const mesh of meshes) {
    if (cancelled()) return;
    await renderer.compileAsync(mesh, camera, scene);
    await new Promise((r) => setTimeout(r, 0));
  }
}

/** Cross-fades `from` into `to` (restarting `to`), the usual clip switch. */
export function fadeTo(from: THREE.AnimationAction | undefined, to: THREE.AnimationAction, seconds: number) {
  if (from === to) return;
  to.reset().setEffectiveWeight(1).play();
  if (from) from.crossFadeTo(to, seconds, false);
}
