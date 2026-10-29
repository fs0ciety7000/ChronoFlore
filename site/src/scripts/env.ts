export type Env = {
  reducedMotion: boolean;
  finePointer: boolean;
  webgl: boolean;
  saveData: boolean;
  deviceMemory?: number;
};

function hasWebGL(): boolean {
  try {
    const canvas = document.createElement('canvas');
    return Boolean(canvas.getContext('webgl2') ?? canvas.getContext('webgl'));
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
  return {
    reducedMotion: matchMedia('(prefers-reduced-motion: reduce)').matches,
    finePointer: matchMedia('(pointer: fine)').matches,
    webgl: hasWebGL(),
    saveData: nav.connection?.saveData === true,
    deviceMemory: nav.deviceMemory,
  };
}

export function shouldUse3D(env: Env): boolean {
  if (env.reducedMotion || !env.webgl || env.saveData) return false;
  return env.deviceMemory === undefined || env.deviceMemory >= 4;
}
