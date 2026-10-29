---
description: Initialise un nouveau projet : détecte le type, choisit les skills, remplit CLAUDE.md et AGENTS.md
argument-hint: "<description courte du projet>"
---

Démarre un nouveau projet à partir de cette description : $ARGUMENTS

Procède dans l'ordre :

1. **Classer le projet.** Lis `.claude/skills-registry.md` et choisis le type dans la « Table de routage ». Si le projet mélange plusieurs types, liste-les tous. Si aucun ne correspond, utilise `find-skills`.
2. **Poser les questions manquantes** (maximum 3, en une seule fois) : stack exacte, commandes de build/test, contraintes particulières. Si la réponse est déductible de la description, ne demande pas.
3. **Vérifier les skills.** Pour chaque skill requis, confirme qu'il est installé (liste des skills disponibles). Si l'un manque, propose de lancer `./scripts/setup-skills.sh` ou la commande `npx skills add ...` correspondante.
4. **Charger les skills du type**, dans l'ordre indiqué par le registre, puis `writing-for-agents`.
5. **Remplir `CLAUDE.md`** : section « Projet courant » (type, stack, commandes). Ne modifie pas le reste.
6. **Remplir `AGENTS.md`** : nom, type, résumé, commandes, structure réelle du dépôt.
7. **Créer le squelette** minimal du projet (dossiers, fichier de config de base, `.gitignore`, `.env.example`) adapté à la stack.
8. **Résumer** en 5 lignes maximum : type retenu, skills chargés, fichiers créés, prochaine étape recommandée (par ex. lancer le skill de brainstorming de Superpowers pour la première fonctionnalité).

Contraintes : n'installe rien sans accord de l'utilisateur ; ne crée pas de code applicatif au-delà du squelette.
