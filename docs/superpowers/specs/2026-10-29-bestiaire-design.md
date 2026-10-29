# ChronoFlore — Bestiaire de plantes faites maison : design

Date : 2026-10-29 · Statut : validé par l'utilisateur · Complète `2026-10-29-tranche-verticale-design.md` (§5.4)

## 1. Intention

L'utilisateur veut des plantes **modélisées maison dans Blender**, plus variées : des **gentilles** à capturer et des **hostiles** (« monstres plantes »). Il en veut **10 à 12 pour commencer**. Chaque plante incarne une émotion de la rêveuse. Les gentilles sont kawaï. Les hostiles sont « mignonnes mais menaçantes », jamais effrayantes.

## 2. Règles communes

- **Gentilles :** elles fuient. On les ralentit, puis on les capture au filet (§5.1 de la spec principale). Chaque capture fait avancer la nuit : commune +20 min, peu commune +40, rare +60.
- **Hostiles :**
  - elles coûtent un pétale au contact ou en touchant avec leur attaque ;
  - **3 fléchettes les endorment** ;
  - **une hostile endormie peut être capturée au filet** : c'est risqué mais rentable, avec une page d'herbier et +40 min ;
  - une hostile qui touche l'héroïne la repousse et reste étourdie 1 s (règle de la Tâche V).
- **Apparition :** les espèces apparaissent par paliers d'heure, si bien que la difficulté monte avec la nuit.
- **Modèles :** générés par script Blender (bpy), un GLB par espèce dans `game/assets/custom/plants/<id>/`. Chaque modèle a un visage expressif et des animations nommées : `Idle`, `Move` (fuite ou approche), `Attack` (hostiles), `Sleep`, `Caught`.

## 3. Les 12 espèces (proposition)

### Gentilles (7)

| Espèce | Émotion | Rareté (apparition) | Comportement |
|---|---|---|---|
| **Rêvette** | joie légère | commune (0 h) | Petite fleur ronde. Sprints courts et pauses. *(existe)* |
| **Nostalgerbe** | nostalgie | commune (0 h) | Herbe-plume. Zigzague, se fige hors du regard. *(existe)* |
| **Câlinette** | tendresse | commune (0 h) | Boule de mousse. S'approche de l'héroïne puis recule d'un bond au dernier moment. Il faut la cueillir pendant l'approche. |
| **Timidelle** | timidité | peu commune (2 h) | Bouton rose. S'enterre et ressort plus loin. *(existe)* |
| **Souffloine** | insouciance | peu commune (1 h) | Pissenlit. Fait de grands bonds, et ne se capture qu'au sol. |
| **Mélancolys** | mélancolie | peu commune (3 h) | Lys bleu, lent, qui file se cacher dans l'étang (intouchable dans l'eau). Il faut l'intercepter avant qu'il l'atteigne. |
| **Lumiole** | espoir | rare (4 h) | Bulbe lumineux flottant, très rapide, qui laisse une traînée de lucioles. +60 min. |

### Hostiles (5)

| Espèce | Émotion | Apparition | Comportement |
|---|---|---|---|
| **Ronce-Angoisse** | angoisse | 0 h | Boule de ronces. Avance lentement vers l'héroïne. *(existe)* |
| **Croque-Colère** | colère | 2 h | Plante carnivore à grande gueule. Se ramasse 0,8 s, puis charge en ligne droite. On l'esquive sur le côté. |
| **Lierre-Jalousie** | jalousie | 3 h | Fait jaillir un cercle de lianes du sol sous l'héroïne, avec un signe au sol 1 s avant. Si elle est prise, elle reste immobilisée 1 s. |
| **Ortie-Regret** | regret | 4 h | Enracinée. Crache des épines en arc, avec une ombre au sol qui annonce l'impact. |
| **Champi-Panique** | panique | 5 h | Champignon qui gonfle puis éclate en nuage de spores. Dans le nuage, l'héroïne est ralentie 2 s. Pas de perte de pétale, sauf au contact direct. |

## 4. Approches envisagées
1. **Un comportement par fichier (`behavior_*.gd`), plus des données par espèce dans les `.tres`**, sur le modèle existant (Tâche 8). Les attaques à distance (épines, lianes, spores) sont de petites scènes de danger (« hazard ») réutilisables. **Recommandée** : on reste dans l'architecture actuelle.
2. Une machine à états générique paramétrée par des données. Trop abstraite pour 12 comportements très différents.

## 5. Impacts techniques (pour le plan)

- **`PlantSpecies` :**
  - `Behavior` gagne `SHY_APPROACH`, `HOPPER`, `POND_SEEKER`, `FLOATER` (gentilles) et `CHARGER`, `ROOT_TRAP`, `SPITTER`, `SPORE` (hostiles) ;
  - un champ `hostile: bool` remplace l'usage de `capturable` pour la Ronce. Les hostiles deviennent capturables endormies.
- **Scènes de danger :** `thorn_projectile`, `vine_ring`, `spore_cloud`. Chacune annonce l'attaque au sol avant l'impact (lisibilité, anti-objectif : ne jamais piéger sans prévenir).
- **Héroïne :** un état « immobilisée » (lianes) et un état « ralentie » (spores).
- **Herbier :** 12 pages, chacune avec son fragment de souvenir et ses deux détails (textes provisoires).
- **Palier du harpon :** il reste à « 3 espèces capturables découvertes ». Les hostiles comptent une fois capturées.

## 6. Ordre proposé
1. Les modèles Blender des 4 espèces existantes, pour remplacer les primitives.
2. Les 8 nouvelles espèces par lots : les gentilles d'abord, puis les hostiles avec leurs dangers.
3. L'herbier passe à 12 pages.
