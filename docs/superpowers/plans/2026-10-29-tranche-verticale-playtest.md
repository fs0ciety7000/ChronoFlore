# Tranche verticale — Notes de playtest (Tâches 14 et 15)

Date : 2026-10-29 · Build : Godot 4.7.2, export Web sans threads (preset « Web »), commit `6384dfb`.

Cette passe est **automatique** (Chromium headless via Playwright). Elle vérifie que la build Web démarre, se joue et sauvegarde. Le ressenti, le rythme et la lisibilité restent à juger par un humain : voir la checklist en bas.

## Build

| Fichier | Release (`build/web/`) | Debug (`build/web-debug/`) |
|---|---|---|
| `index.wasm` | 39,5 Mo (≈ 10,1 Mo en gzip) | 37,9 Mo |
| `index.pck` | 1,99 Mo | 1,99 Mo |
| `index.js` | 280 Ko | — |

- Export : `godot --headless --path game --export-release "Web" ../build/web/index.html`, code 0, aucun avertissement.
- Le `.pck` est petit : rien à élaguer. Le poids vient du moteur (`.wasm`). Servez-le compressé (gzip ou brotli) ; nginx ne compresse `application/wasm` que si on l'ajoute à `gzip_types`.
- Presets Linux, Windows Desktop et macOS (universal, sans signature) ajoutés. Ils sont reconnus, mais l'export échoue faute des templates desktop (seuls les templates `web_*` sont installés ici). Le macOS universal exige l'import ETC2/ASTC, désormais activé dans `project.godot`.

## Vérifié automatiquement

Environnement : Chromium headless, WebGL 2 via **SwiftShader** (rendu logiciel, sans GPU), viewport 1280×720.
Script : `/tmp/claude-0/-home-user-ChronoFlore/f264b819-aaa3-553d-973a-709f6d3bd3d7/scratchpad/preview/web/smoke.js` (scratchpad de session, non versionné).

Déroulé : chargement → titre → Entrée (choix du personnage) → Entrée (Elle, solo) → 20 s de jeu (ZQSD/WASD maintenus, visée souris en cercle autour de l'héroïne, clics avec le fusil, le harpon et le filet) → Échap (pause) → « Abandonner la nuit » → écran de réveil → rechargement de l'onglet → Herbier.

| Vérification | Résultat |
|---|---|
| Démarrage du moteur | OK, ≈ 6 s en local |
| Écran titre, choix du personnage, nuit, pause, réveil | OK, tous affichés |
| Déplacement et changement d'outil (1/2/3, cartouche HUD) | OK |
| Réveil en sursaut (abandon) | OK : « Elle se réveille en sursaut à 0 h 00 » |
| Sauvegarde écrite dans IndexedDB (`/userfs/.../ChronoFlore/save.json`) | OK après l'abandon |
| Sauvegarde relue après rechargement | OK : une sauvegarde injectée (Rêvette ×6, Timidelle ×2, Souffloine ×1, harpon, record 140 min) est lue (record « 2 h 20 », harpon dans la ceinture), réécrite à l'abandon sans perte, puis affichée dans l'Herbier après rechargement |
| Option debug `?minutes_x=24` | Lue sans erreur en build debug ; non exercée, faute de capture pendant le jeu automatique |

Captures (`/tmp/claude-0/-home-user-ChronoFlore/f264b819-aaa3-553d-973a-709f6d3bd3d7/scratchpad/preview/web/`) :

- `release-01-title.png` : écran titre
- `release-02-character-select.png` : Elle / Lui / À deux
- `release-03-night-start.png` : début de nuit (pastel), 0 h 00, cartouche « Filet »
- `release-04-play-{1,2,3}.png`, `release-05-play-end.png` : jeu, Rêvette et Ronce visibles
- `release-06-pause.png` : menu pause
- `release-07-wake.png` : réveil en sursaut
- `release-08-title-after-reload.png`, `release-09-herbarium-after-reload.png` : après rechargement (herbier vide, normal sans capture)
- `debug-01…09-*.png` : même déroulé en build debug avec la sauvegarde injectée ; `debug-04-play-1.png` montre le harpon, `debug-07-wake.png` le record « 2 h 20 », `debug-09-herbarium-after-reload.png` l'herbier rempli
- `release-result.json`, `debug-result.json` : console, fps, contenu IndexedDB

**Non obtenu automatiquement :** « vers 4 h (indigo, plantes lumineuses) » et l'écran d'aube. L'horloge n'avance qu'avec les captures, et le bot à l'aveugle n'en a fait aucune en 20 s. À faire par l'humain, avec `?minutes_x=24` en build debug : une capture = l'aube.

## Console

- **Aucune erreur ni avertissement du jeu** (ni `push_error`, ni `push_warning`, ni `pageerror`), en release comme en debug.
- Seul bruit : `GL Driver Message … GPU stall due to ReadPixels` (×4, propre à SwiftShader et aux captures d'écran). Le 404 du run debug vient du script (page vide utilisée pour injecter la sauvegarde).
- À savoir : si IndexedDB est incohérent (fichier sans ses dossiers parents), Godot écrit `IndexedDB not available` et la partie tourne **sans persistance**, sans rien dire au joueur. Le cas s'est produit pendant la mise au point de l'injection, pas en jeu normal.

## Performances

| Écran | Images/s (`requestAnimationFrame`, 4 s) |
|---|---|
| Titre | ≈ 34 |
| Nuit (île, plantes, eau) | ≈ 4,2 |

Ces chiffres viennent de SwiftShader, un rendu logiciel sur CPU : ils ne disent rien d'un vrai GPU. Il faut les mesurer sur une vraie machine (Chrome, puis Firefox et Safari), idéalement avec un portable modeste.

## Réglages

Aucun chiffre modifié : sans capture automatique, le rythme et la difficulté n'ont pas pu être jugés. Les valeurs de départ (§5) restent en place.

## Debug : accélérer la nuit

`GameState.debug_minutes_multiplier` multiplie les minutes gagnées par capture, **seulement en build debug** (`OS.is_debug_build()`), 1 par défaut :

- Web : `godot --headless --path game --export-debug "Web" ../build/web-debug/index.html`, puis ouvrir `index.html?minutes_x=24` (une capture commune = 480 min = l'aube).
- Desktop : `godot --path game -- --minutes-x=24`.

## Checklist du playtest humain

Notez pour chaque point : OK / problème (avec l'heure en jeu et une capture).

- [ ] **Nuit complète jusqu'à l'aube**, sans le multiplicateur : durée réelle, nombre de captures (cible ≈ 20 pour 8 h), fondu rose de l'aube, souvenir d'aube révélé, record mis à jour.
- [ ] Palette : pastel en début de nuit, **indigo vers 4 h** avec plantes lumineuses, retour vers l'aube. Faire une capture d'écran à chaque étape.
- [ ] **Réveil en sursaut** : perdre les 5 pétales (fuites, coups des hostiles), fondu blanc, écran de réveil cohérent.
- [ ] **Harpon débloqué** à 3 espèces capturables découvertes (Timidelle comprise) : message sur l'écran de réveil, harpon présent à la nuit suivante, il cloue 3 s, recharge 2,5 s.
- [ ] **Herbier persistant après rechargement** de l'onglet (F5) : en fin de nuit, et aussi en fermant l'onglet en pleine nuit juste après une découverte.
- [ ] Navigation privée ou stockage bloqué : le jeu démarre quand même (sans persistance).
- [ ] **Passage souris ↔ manette** en pleine nuit, dans les deux sens ; débrancher la manette en jeu : la visée suit le dernier périphérique et ne se fige pas.
- [ ] **Coop avec 2 manettes** (« À deux ») : attribution J1/J2, caméra qui garde les deux héros, outils et pétales de chacun.
- [ ] **Coop au clavier partagé** (J1 ZQSD/WASD + souris, J2 flèches + Ctrl) : les flèches ne doivent plus bouger J1 en coop (elles sont aussi liées à `p1_move_*`), J2 jouable sans souris.
- [ ] **Lisibilité des signes d'attaque** de chaque hostile, chacune au moins 3 fois : Ronce d'angoisse, Croque-colère, Lierre de jalousie, Champi-panique, Ortie du regret. Le signe au sol se voit-il assez tôt, de jour comme de nuit ?
- [ ] Les 7 gentilles (Rêvette, Souffloine, Câlinette, Nostalgerbe, Lumiole, Timidelle, Mélancolys) : comportement reconnaissable, capture faisable.
- [ ] **Rythme de la difficulté** : vitesse +8 %/h sensible sans être injuste ; peu communes dès 2 h, rares dès 4 h ; 1 à 3 cauchemars ; la pression des Ronces ; Timidelle trop facile ou trop dure.
- [ ] **Performance** sur vraie machine : fps en début de nuit et vers 6 h (plus de plantes), temps de chargement en ligne.
- [ ] Échap / pause, Herbier depuis la pause, « Abandonner la nuit » ; focus clavier et manette dans tous les menus.
