# Conventions

Règles pour les branches, les commits et les pull requests. Elles valent pour tout le monde, agents compris.

## Branches

Tout changement passe par une branche partie de `origin/main`. On ne pousse jamais directement sur `main`. Chaque branche est fusionnée par une pull request, **sans squash** : ses commits arrivent tels quels sur `main` (voir « Pull requests »).

Une branche porte un seul changement. Son nom est un préfixe, une barre oblique, puis une courte description en anglais, en minuscules et avec des tirets :

| préfixe | pour | exemple |
|---|---|---|
| `feature/` | une fonctionnalité ou un ajout visible | `feature/audio-analysis` |
| `bugfix/` | la correction d'un bug | `bugfix/shuffle-playback-gap` |
| `refactoring/` | une restructuration du code, sans changement de comportement | `refactoring/track-select-query` |
| `chore/` | l'entretien : dépendances, outillage, nettoyage | `chore/bump-flutter` |
| `docs/` | la documentation seule (README, `doc/`, `design/HANDOFF.md`) | `docs/conventions` |
| `ci/` | la CI et le build (workflows, Dockerfile, Makefile) | `ci/recommender-checks` |
| `test/` | des tests ajoutés ou corrigés, sans toucher au code testé | `test/analysis-api` |

Si le changement correspond à une issue, on peut ajouter son numéro : `bugfix/27-previous-restarts-track`.

## Commits

Les messages de commit suivent [Conventional Commits](https://www.conventionalcommits.org/fr/v1.0.0/) :

```
<type>(<portée>): <description>

<corps, facultatif>

<pied, facultatif>
```

- **type** : `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `build`, `perf`, `style`.
- **portée** (facultative) : la partie du dépôt touchée, `server`, `app`, `recommender`, `design` ou `doc`.
- **description** : à l'impératif, en minuscules, sans point final, 72 caractères au plus pour toute la première ligne.
- **changement incompatible** (API, schéma de base, format de cache…) : `!` après le type ou la portée, et un pied `BREAKING CHANGE: …` qui dit ce qui casse.

Le type du commit va avec le préfixe de la branche : `feature/` → `feat`, `bugfix/` → `fix`, `refactoring/` → `refactor`, `chore/` → `chore`, `docs/` → `docs`, `ci/` → `ci` ou `build`, `test/` → `test`. Une branche peut contenir d'autres types quand ils accompagnent le changement, par exemple un commit `test` ou `docs` dans une branche `feature/`.

Exemples :

```
feat(recommender): analyse tempo, key and loudness of each track
fix(app): keep playing while toggling shuffle
refactor(server): share the track query between lists and search
ci: run the recommender tests on every pull request
feat(server)!: return bpm and camelot in track lists
```

## Langue et contenu

- Les commits, les titres et les descriptions de pull request sont **en anglais**.
- Ils sont **courts** et disent **ce qu'on ajoute ou corrige, et pourquoi**, pas comment. Le comment, c'est le diff.
  - Oui : `fix(app): restart the track on "previous" instead of resuming an old position`
  - Non : `fix(app): reset _lastPosition in PlaybackController before calling seek(0)`
- La description d'une pull request tient en quelques lignes : le besoin, ce qui change pour l'utilisateur, ce qui n'est pas testé ou reste à faire, et l'issue concernée (`Closes #27`).

## Pull requests

- **Fusion par merge commit classique, jamais en squash** (ni en rebase). Les commits de la branche sont conservés sur `main` : chacun doit donc respecter les règles ci-dessus et former une étape cohérente (il compile, ses tests passent).
- Avant d'ouvrir la pull request, on nettoie l'historique de sa branche : on regroupe les commits « wip », « fix typo » ou « review » dans le commit qu'ils corrigent (`git rebase -i origin/main`, avec `fixup!`). On ne réécrit que ses propres branches, jamais `main` ni la branche de quelqu'un d'autre.
- Le titre de la pull request suit le même format que les commits.
- La CI doit passer avant la fusion (voir `AGENTS.md`).
