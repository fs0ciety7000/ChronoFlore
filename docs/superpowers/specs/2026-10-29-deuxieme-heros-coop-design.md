# ChronoFlore — Deuxième héros, choix du personnage et coop locale : design

Date : 2026-10-29 · Statut : validé par l'utilisateur · Complète `2026-10-29-tranche-verticale-design.md`

## 1. Intention

L'utilisateur veut un deuxième personnage jouable, modélisé maison dans Blender à partir de ses photos : un jeune homme à casquette gavroche en tweed. Il veut qu'on puisse le jouer **seul, au choix**, et **à deux en coop locale**.

**Règle de récit (décidée par l'utilisateur) : seule l'héroïne rêve.** Le héros est une figure de son rêve : un compagnon que la rêveuse a fait venir dans sa nuit. La nuit, la lucidité, l'herbier et les souvenirs restent les siens.

## 2. Objectifs, non-objectifs

**Objectifs**
- **Le modèle du héros :** mêmes os, mêmes animations (Idle, Walk, Swing, Hurt) et même style chibi que l'héroïne v2.
- **Écran de choix** après « Commencer la nuit » : Solo (l'héroïne ou le héros) ou Coop à deux.
- **Coop locale à deux** sur le même écran et la même île.

**Non-objectifs (pour l'instant)**
- Coop en ligne.
- Écran partagé (split screen).
- Coop à plus de deux.
- Capacités différentes selon le personnage : les deux ont les mêmes outils et les mêmes règles.

## 3. Game design (proposition, à valider)

### 3.1 Solo
- Le joueur choisit l'héroïne ou le héros. Tout le reste est identique : outils, pétales, horloge, herbier.
- **Si on joue le héros :** il parcourt le rêve de l'héroïne. Le texte d'intro et les écrans de fin parlent d'elle (« Elle se réveille… »). Le HUD reste la fleur-horloge de la rêveuse.

### 3.2 Coop locale à deux
- **Rôles :** joueur 1 = héroïne, joueur 2 = héros. Pas d'inversion pour la tranche, pour garder le récit lisible.
- **Lucidité partagée :** ce sont les pétales de la rêveuse. Un coup de Ronce sur l'un ou l'autre coûte un pétale commun. Chaque personnage a sa propre invulnérabilité de 1,5 s.
- **Horloge partagée :** chaque capture, par l'un ou l'autre, fait avancer la même nuit.
- **Herbier partagé**, puisque c'est celui de la rêveuse. Les outils débloqués valent pour les deux.
- **Caméra unique :** elle cadre les deux personnages (le centre entre eux) et zoome un peu plus large quand ils s'éloignent, dans une limite. Au-delà de cette distance (≈ 14 m), le personnage qui s'éloigne est freiné (« laisse » douce), sans téléportation.
- **Équilibrage (proposition) :** population de plantes ×1,3 et Ronces +1 en coop, car deux filets vident l'île plus vite. Les récompenses en minutes ne changent pas.
- **Entrées :**
  - les deux manettes branchées : manette 1 → J1, manette 2 → J2 ;
  - une seule manette : clavier-souris → J1, manette → J2 ;
  - aucune manette : clavier partagé, ZQSD/WASD + F (outil) + R (changer) pour J1, flèches + Ctrl droit (outil) + Maj droite (changer) pour J2. Visée automatique pour les deux, comme le futur mode mobile.
- **HUD :** une seule fleur-horloge (partagée), plus une petite cartouche d'outil par joueur, à gauche pour J1 et à droite pour J2.

## 4. Approches envisagées

1. **Deux instances du même `Heroine` paramétré** (modèle visuel + index de joueur → actions d'entrée et appareil). La session gère une liste de joueurs. Peu de code nouveau, et les règles existantes s'appliquent telles quelles. **Recommandée.**
2. Une classe `Hero` séparée. Duplication, aucun gain : les règles sont identiques.
3. Coop par écran partagé. Exclue : l'île est petite et le diorama se lit mieux en plan unique.

## 5. Impacts techniques (pour le builder)
- **InputMap :** dupliquer les actions par joueur (`p1_move_left`… `p2_use_tool`…) avec un appareil (device) assigné par joueur. Le solo utilise `p1_*`.
- **`Heroine`** reçoit un `player_index` et une `visual_scene` (héroïne v2 ou héros). `aim_source` est propre à chaque joueur.
- **`NightSession` :**
  - liste de joueurs ;
  - `set_threat` des plantes = le joueur le plus proche ;
  - une Ronce cible le joueur le plus proche ;
  - apparition des plantes loin de tous les joueurs ;
  - la caméra suit le barycentre et ajuste sa taille entre min et max.
- **`GameState`** garde le mode choisi (`solo_heroine`, `solo_hero`, `coop`).
- **Tests :** lucidité partagée, plante qui vise le joueur le plus proche, cadrage de la caméra, assignation des appareils.

## 6. Ordre proposé
Après la passe visuelle (Tâche V) et l'intégration de l'héroïne v2 :
1. intégration du modèle du héros, une fois ses rendus validés ;
2. écran de choix et solo avec le héros ;
3. coop locale.
