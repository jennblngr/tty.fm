# AGENTS.md

Repères pour les agents qui travaillent sur ce dépôt.

## Documentation

- `README.md` : architecture du monorepo et installation sur le NAS.
- `app/README.md` : client Flutter.
- `design/HANDOFF.md` : écrans, tokens, règles et décisions du design ; les maquettes de `design/mockups/` font foi pour les détails visuels.
- `doc/roadmap.md` : phases du projet, issues ouvertes et écarts entre les maquettes et l'app. À lire avant de choisir une tâche, et à mettre à jour quand une issue est fermée ou qu'un écart est corrigé.

## Façon de travailler

- Une branche par changement, partie de `origin/main` ; les PR sont fusionnées en squash.
- La CI (`.github/workflows/ci.yml`) vérifie le format, le lint, les tests et le build du serveur et de l'app sur chaque PR.
