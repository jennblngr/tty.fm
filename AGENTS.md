# AGENTS.md

Repères pour les agents qui travaillent sur ce dépôt.

## Documentation

- `README.md` : architecture du monorepo et installation sur le NAS.
- `app/README.md` : client Flutter.
- `design/HANDOFF.md` : écrans, tokens, règles et décisions du design ; les maquettes de `design/mockups/` font foi pour les détails visuels.
- `doc/conventions.md` : guide rapide, branches, commits, pull requests, reverts et vérifications.
- `doc/roadmap.md` : phases du projet, issues ouvertes et écarts entre les maquettes et l'app. À lire avant de choisir une tâche, et à mettre à jour quand une issue est fermée ou qu'un écart est corrigé.

## Façon de travailler

- Une branche par changement, partie de `origin/main` et nommée selon `doc/conventions.md` avec pour préfixe le type du changement, comme pour les commits (`feat/`, `fix/`, `refactor/`, `chore/`, `docs/`, `ci/`, `revert/`…) ; commits en anglais au format Conventional Commits, **portée obligatoire** (`server`, `app`, `recommender`, `design`, `doc` ou `repo` : `fix(app): …`) ; fusion par merge commit classique, jamais en squash : les commits de la branche arrivent tels quels sur `main`.
- Annuler un changement : `revert(#<n° de la PR>): <en-tête du commit annulé>` avec un pied `Refs: <sha>`, jamais le message de `git revert` ni le bouton « Revert » de GitHub tels quels (`doc/conventions.md`, § 5).
- Avant de committer dans un nouveau clone, lancer `tools/setup-git.sh` : il active le modèle de message et les hooks qui vérifient les messages de commit et le nom de la branche. `tools/conventions/check.sh` permet de vérifier à la main (`check.sh title "<titre de la PR>"`, `check.sh commits origin/main HEAD`).
- La CI vérifie chaque PR : `.github/workflows/ci.yml` le format, le lint, les tests et le build du serveur, de l'app et du recommender ; `.github/workflows/conventions.yml` le nom de la branche, le titre de la PR et chaque commit. GitHub ne bloque pas la fusion quand un job échoue (pas de protection de branche sur ce plan) : ne pas fusionner tant que les deux ne sont pas verts.
