export type Env = {
  reducedMotion: boolean;
  finePointer: boolean;
  webgl: boolean;
  saveData: boolean;
  deviceMemory?: number;
};

/** Creates a throwaway WebGL context and releases it at once (no leaked context). */
export function probeWebGL(doc: Document = document): boolean {
  try {
    const canvas = doc.createElement('canvas');
    const gl = (canvas.getContext('webgl2') ?? canvas.getContext('webgl')) as WebGLRenderingContext | null;
    if (!gl) return false;
    gl.getExtension('WEBGL_lose_context')?.loseContext();
    return true;
  } catch {
    return false;
  }
}

/** Snapshot of the capabilities that decide how much motion and 3D to use. */
export function readEnv(): Env {
  const nav = navigator as Navigator & {
    deviceMemory?: number;
    connection?: { saveData?: boolean };
  };
  let webgl: boolean | undefined;
  return {
    reducedMotion: matchMedia('(prefers-reduced-motion: reduce)').matches,
    finePointer: matchMedia('(pointer: fine)').matches,
    // Probed on first read only: most visits never need it (reduced motion,
    // save-data) and each probe costs a GPU context.
    get webgl() {
      webgl ??= probeWebGL();
      return webgl;
    },
    saveData: nav.connection?.saveData === true,
    deviceMemory: nav.deviceMemory,
  };
}

export function shouldUse3D(env: Env): boolean {
  if (env.reducedMotion || env.saveData) return false;
  if (env.deviceMemory !== undefined && env.deviceMemory < 4) return false;
  return env.webgl; // last: reading it may probe the GPU
}
