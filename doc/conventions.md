# Conventions

Règles pour les branches, les commits et les pull requests. Elles valent pour tout le monde, agents compris.

## Branches

Tout changement passe par une branche partie de `origin/main`. On ne pousse jamais directement sur `main`. Chaque branche est fusionnée par une pull request, en squash.

Une branche porte un seul changement. Son nom est un préfixe, une barre oblique, puis une courte description en anglais, en minuscules et avec des tirets :

| préfixe | pour | exemple |
|---|---|---|
| `feature/` | une fonctionnalité ou un ajout visible | `feature/audio-analysis` |
| `bugfix/` | la correction d'un bug | `bugfix/shuffle-playback-gap` |
| `refactoring/` | une restructuration du code, sans changement de comportement | `refactoring/track-select-query` |
| `chore/` | l'entretien : dépendances, CI, outillage, documentation | `chore/bump-flutter` |

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

Le type du commit va avec le préfixe de la branche : `feature/` → `feat`, `bugfix/` → `fix`, `refactoring/` → `refactor`, `chore/` → `chore`, `docs`, `ci`, `build` ou `test`.

Exemples :

```
feat(recommender): analyse tempo, key and loudness of each track
fix(app): keep playing while toggling shuffle
refactor(server): share the track query between lists and search
chore(ci): run the recommender tests on every pull request
feat(server)!: return bpm and camelot in track lists
```

## Langue et contenu

- Les commits, les titres et les descriptions de pull request sont **en anglais**.
- Ils sont **courts** et disent **ce qu'on ajoute ou corrige, et pourquoi**, pas comment. Le comment, c'est le diff.
  - Oui : `fix(app): restart the track on "previous" instead of resuming an old position`
  - Non : `fix(app): reset _lastPosition in PlaybackController before calling seek(0)`
- La description d'une pull request tient en quelques lignes : le besoin, ce qui change pour l'utilisateur, ce qui n'est pas testé ou reste à faire, et l'issue concernée (`Closes #27`).

## Pull requests

Avec la fusion en squash, le **titre de la pull request** devient le message du commit sur `main` : il suit donc les mêmes règles que les commits. La CI doit passer avant la fusion (voir `AGENTS.md`).
