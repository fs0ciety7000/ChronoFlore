// The two home-made characters (heroine and companion), shared by the island
// duo (diorama/scene.ts) and the live portraits (portraits/scene.ts).
// Unlike the Polyfork models they are committed, under {id}.{sha8}.glb names
// (nginx serves /models/ as immutable). To update one: copy the new GLB from
// the game branch (game/assets/custom/{heroine,hero2}/), rename it with the
// first 8 hex digits of its sha256 and change `file` below;
// tests/unit/characters.test.ts checks the hash.
// No three.js import here: the page's initial bundle reads the labels.

export const CUSTOM_MODELS_URL = '/models/custom/';

/** Clips every character carries (same skeleton, same actions). */
export const CHARACTER_CLIPS = ['Idle', 'Walk', 'Swing', 'Hurt'] as const;
export type ClipName = (typeof CHARACTER_CLIPS)[number];

export type CharacterKey = 'heroine' | 'companion';

export type Character = {
  file: string;
  /** Accessible name of the portrait card (role="img"). */
  label: string;
};

export const CHARACTERS: Record<CharacterKey, Character> = {
  heroine: {
    file: 'heroine.36637732.glb',
    label: "L'héroïne en 3D : peau foncée, longues tresses, lunettes roses, haut à rayures",
  },
  companion: {
    file: 'companion.d9aa8fad.glb',
    label: 'Le compagnon en 3D : casquette de tweed grise, veste kaki, barbe courte',
  },
};

export const characterUrl = (key: CharacterKey) => CUSTOM_MODELS_URL + CHARACTERS[key].file;
