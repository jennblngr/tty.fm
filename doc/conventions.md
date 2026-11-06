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

- **type** : `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `build`, `perf`, `style`, et `revert` pour annuler un changement (voir « Annuler un changement »).
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

## Annuler un changement (revert)

Un revert est un changement comme un autre : il passe par une branche et une pull request.

- **Branche** : le préfixe `bugfix/` (ou celui du changement annulé), puis `revert-` et la description du changement : `bugfix/revert-shuffle-playback-gap`.
- **Commit** : le type `revert`, avec pour portée le numéro de la pull request qui a introduit le changement annulé, puis l'en-tête exact du commit annulé : `revert(#36): <en-tête annulé>`. Le corps dit **pourquoi** on annule, et un pied `Refs:` donne le sha du commit annulé. La limite de 72 caractères vaut pour l'en-tête annulé, pas pour la ligne entière. Pour retrouver la PR d'un commit : `gh pr list --state merged --search <sha>`.

  ```
  revert(#36): fix(app): keep playing while toggling shuffle

  The fix drops the queue on Android when the app is in the background.

  Refs: 1a2b3c4
  ```

- Pour annuler toute une pull request, on annule son commit de merge (ajouter `-m 1` à `git revert`). L'en-tête du commit de merge est le titre de la PR : c'est lui qu'on reprend après `revert(#<n°>): `.

On n'utilise pas tels quels le bouton « Revert » de GitHub ni `git revert` sans option : ils produisent une branche `revert-<n>-<branche>` et un message `Revert "<titre>"` qui ne suivent pas ces règles (la CI les refuse). En local, on lance `git revert --no-commit <sha>`, puis `git commit` avec un message conforme. Avec le bouton de GitHub, on recrée la branche sous un nom conforme et on corrige le titre de la PR et le message du commit avant de fusionner.

## Langue et contenu

- Les commits, les titres et les descriptions de pull request sont **en anglais**.
- Ils sont **courts** et disent **ce qu'on ajoute ou corrige, et pourquoi**, pas comment. Le comment, c'est le diff.
  - Oui : `fix(app): restart the track on "previous" instead of resuming an old position`
  - Non : `fix(app): reset _lastPosition in PlaybackController before calling seek(0)`
- La description d'une pull request tient en quelques lignes : le besoin, ce qui change pour l'utilisateur, ce qui n'est pas testé ou reste à faire, et l'issue concernée (`Closes #27`).

## Pull requests

- **Fusion par merge commit classique, jamais en squash** (ni en rebase). Les commits de la branche sont conservés sur `main` : chacun doit donc respecter les règles ci-dessus et former une étape cohérente (il compile, ses tests passent).
- Avant d'ouvrir la pull request, on nettoie l'historique de sa branche : on regroupe les commits « wip », « fix typo » ou « review » dans le commit qu'ils corrigent (`git rebase -i origin/main`, avec `fixup!`). On ne réécrit que ses propres branches, jamais `main` ni la branche de quelqu'un d'autre.
- Le titre de la pull request suit le même format que les commits. Le commit de merge reprend le titre de la PR comme en-tête et sa description comme corps (réglage du dépôt) : l'un et l'autre finissent donc sur `main`.
- La CI doit passer avant la fusion (voir `AGENTS.md`).
