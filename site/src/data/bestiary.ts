// The game's 12-plant bestiary, copied by hand from
// game/data/species/<id>.tres on branch origin/claude/chronoflore-game
// (display_name, emotion, rarity, min_hour, fragment; the "(provisoire) "
// prefix is dropped, the page carries one global notice instead).
// Thumbnails: game/assets/custom/plants/thumbs/<id>.png -> public/herbier/<id>.webp.
// Order: gentle plants by hour then rarity, then hostile ones by hour.

export type Rarity = 'commune' | 'peu commune' | 'rare';

export interface Species {
  id: string;
  name: string;
  /** Lower-case emotion, as shown on the card. */
  emotion: string;
  /** Emotion with its article ("de la joie légère", "de l'espoir", "du regret"). */
  emotionOf: string;
  rarity: Rarity;
  /** Game hour from which the plant can appear (0 = from the start of the night). */
  fromHour: number;
  hostile: boolean;
  fragment: string;
  /** Square thumbnail (192 x 192) under public/. */
  image: string;
}

export const THUMB_SIZE = 192;

const species = (s: Omit<Species, 'image'>): Species => ({ ...s, image: `/herbier/${s.id}.webp` });

export const BESTIARY: readonly Species[] = [
  species({
    id: 'revette',
    name: 'Rêvette',
    emotion: 'joie légère',
    emotionOf: 'de la joie légère',
    rarity: 'commune',
    fromHour: 0,
    hostile: false,
    fragment:
      "Une petite joie qui ne pesait rien, comme un rire entendu de l'autre côté d'un mur. Elle file dès qu'on la regarde, de peur qu'on la retienne. Pourtant elle sent encore le matin d'été.",
  }),
  species({
    id: 'nostalgerbe',
    name: 'Nostalgerbe',
    emotion: 'nostalgie',
    emotionOf: 'de la nostalgie',
    rarity: 'commune',
    fromHour: 0,
    hostile: false,
    fragment:
      "Elle ne se souvient plus de quoi, seulement que c'était doux. Elle zigzague entre les herbes comme entre des photos jaunies. Quand on la regarde de trop près, elle se fige, un peu gênée.",
  }),
  species({
    id: 'calinette',
    name: 'Câlinette',
    emotion: 'tendresse',
    emotionOf: 'de la tendresse',
    rarity: 'commune',
    fromHour: 0,
    hostile: false,
    fragment:
      "Une tendresse qui n'ose pas tout à fait. Elle vient se blottir tout près, puis recule d'un bond, effrayée par sa propre audace. Il faut la cueillir au moment où elle s'avance.",
  }),
  species({
    id: 'souffloine',
    name: 'Souffloine',
    emotion: 'insouciance',
    emotionOf: "de l'insouciance",
    rarity: 'peu commune',
    fromHour: 1,
    hostile: false,
    fragment:
      "Une après-midi sans montre, où l'on soufflait sur les pissenlits pour voir jusqu'où le vent irait. Elle bondit sans regarder où elle retombe. Personne ne l'attrape en plein vol.",
  }),
  species({
    id: 'timidelle',
    name: 'Timidelle',
    emotion: 'timidité',
    emotionOf: 'de la timidité',
    rarity: 'peu commune',
    fromHour: 2,
    hostile: false,
    fragment:
      "Elle voulait seulement dire bonjour, mais les mots sont restés sous la terre. Alors elle s'enterre dès qu'on s'approche, et ressort plus loin, le cœur battant. Un jour, quelqu'un lui répondra.",
  }),
  species({
    id: 'melancolys',
    name: 'Mélancolys',
    emotion: 'mélancolie',
    emotionOf: 'de la mélancolie',
    rarity: 'peu commune',
    fromHour: 3,
    hostile: false,
    fragment:
      "Une tristesse douce, de celles qu'on garde parce qu'elles ressemblent à quelqu'un. Elle marche lentement vers l'eau pour s'y cacher. Dans l'étang, plus rien ne l'atteint.",
  }),
  species({
    id: 'lumiole',
    name: 'Lumiole',
    emotion: 'espoir',
    emotionOf: "de l'espoir",
    rarity: 'rare',
    fromHour: 4,
    hostile: false,
    fragment:
      "Une petite lumière apparue au cœur de la nuit, quand tout semblait trop loin. Elle file à toute allure et laisse derrière elle une traînée de lucioles. La suivre, c'est déjà avancer.",
  }),
  species({
    id: 'ronce_angoisse',
    name: 'Ronce-Angoisse',
    emotion: 'angoisse',
    emotionOf: "de l'angoisse",
    rarity: 'commune',
    fromHour: 0,
    hostile: true,
    fragment:
      "Elle n'a pas de visage, seulement un poids sur la poitrine qui avance, doucement, sans jamais s'arrêter. On ne peut la capturer qu'endormie. Le calme revient, mais elle sait où on habite.",
  }),
  species({
    id: 'croque_colere',
    name: 'Croque-Colère',
    emotion: 'colère',
    emotionOf: 'de la colère',
    rarity: 'peu commune',
    fromHour: 2,
    hostile: true,
    fragment:
      'Une grande bouche qui claque pour un rien : un mot de travers, une porte qui résiste. Elle se ramasse, gonfle les joues, puis fonce tout droit sans regarder. Un pas de côté suffit ; après, elle reste là, un peu bête, à souffler.',
  }),
  species({
    id: 'lierre_jalousie',
    name: 'Lierre-Jalousie',
    emotion: 'jalousie',
    emotionOf: 'de la jalousie',
    rarity: 'peu commune',
    fromHour: 3,
    hostile: true,
    fragment:
      "Un petit lierre acide qui regarde toujours ce que les autres ont. Il ne court pas, il s'accroche : des lianes jaillissent sous les pieds pour retenir, juste un instant, ce qui allait partir.",
  }),
  species({
    id: 'ortie_regret',
    name: 'Ortie-Regret',
    emotion: 'regret',
    emotionOf: 'du regret',
    rarity: 'rare',
    fromHour: 4,
    hostile: true,
    fragment:
      "Une ortie aux feuilles tombantes, plantée là où l'on aurait dû dire quelque chose. Elle ne bouge pas : elle renvoie de loin, en arc, les petites épines des choses qu'on n'a pas faites. On voit toujours leur ombre arriver.",
  }),
  species({
    id: 'champi_panique',
    name: 'Champi-Panique',
    emotion: 'panique',
    emotionOf: 'de la panique',
    rarity: 'rare',
    fromHour: 5,
    hostile: true,
    fragment:
      'Un petit champignon aux yeux qui tournent, qui arrive tard dans la nuit, quand tout s\'accélère. Il gonfle, gonfle, puis éclate en nuage. Dedans, les jambes deviennent lourdes ; il suffit d\'attendre que ça passe.',
  }),
];

export const GENTLE = BESTIARY.filter((s) => !s.hostile);
export const HOSTILE = BESTIARY.filter((s) => s.hostile);

/** "N° 001" ... "N° 012": position in the full bestiary. */
export const plateNumber = (s: Species): string => String(BESTIARY.indexOf(s) + 1).padStart(3, '0');

export const altOf = (s: Species): string => `${s.name}, plante ${s.emotionOf}`;

export const hourLabel = (s: Species): string => (s.fromHour > 0 ? `dès ${s.fromHour} h` : 'dès la tombée du sommeil');
