# Conventions

Règles pour les branches, les commits et les pull requests. Elles valent pour tout le monde, agents compris, et la CI les vérifie (§ 6).

1. [Guide rapide](#1-guide-rapide)
2. [Branches](#2-branches)
3. [Commits](#3-commits)
4. [Pull requests](#4-pull-requests)
5. [Annuler un changement](#5-annuler-un-changement)
6. [Vérifications](#6-vérifications)

## 1. Guide rapide

Une fois par clone, pour activer le modèle de message et les hooks git (§ 6) :

```bash
tools/setup-git.sh
```

Puis, pour chaque changement :

1. Partir de `origin/main` sur une branche à soi, nommée `<préfixe>/<description>` : `git switch -c fix/shuffle-playback-gap origin/main` (§ 2).
2. Committer par étapes cohérentes, avec des messages `<type>(<portée>): <description>` en anglais : `fix(app): keep playing while toggling shuffle` (§ 3).
3. Nettoyer l'historique de la branche : regrouper les `fixup!` (`git rebase -i --autosquash origin/main`).
4. Ouvrir une pull request dont le titre suit le même format, attendre que la CI soit verte, fusionner par merge commit (§ 4).

## 2. Branches

### Règles

- Tout changement passe par une branche partie de `origin/main`. On ne pousse jamais directement sur `main`.
- Une branche porte un seul changement et se fusionne par une pull request, sans squash (§ 4).

### Nommage

Un préfixe, une barre oblique, puis une courte description en anglais, en minuscules et avec des tirets. **Le préfixe est le type du changement**, le même que celui des commits (§ 3) : `feat/`, `fix/`, `refactor/`, `perf/`, `style/`, `chore/`, `docs/`, `test/`, `ci/`, `build/` ou `revert/`.

```
feat/audio-analysis
fix/shuffle-playback-gap
refactor/track-select-query
chore/bump-flutter
docs/conventions
ci/recommender-checks
revert/shuffle-playback-gap
```

Si le changement correspond à une issue, on peut ajouter son numéro : `fix/27-previous-restarts-track`.

## 3. Commits

### Format

Les messages de commit suivent [Conventional Commits 1.0.0](https://www.conventionalcommits.org/fr/v1.0.0/), avec une différence : **la portée est obligatoire** (la spécification la laisse facultative). Elle dit tout de suite quelle partie du dépôt le commit touche.

```
<type>(<portée>): <description>

<corps, facultatif>

<pied, facultatif>
```

- **type** :

  | type | pour |
  |---|---|
  | `feat` | une fonctionnalité ou un ajout visible |
  | `fix` | la correction d'un bug |
  | `refactor` | une restructuration du code, sans changement de comportement |
  | `perf` | un gain de performance |
  | `style` | la mise en forme du code (format, espaces), sans changement de sens |
  | `chore` | l'entretien : dépendances, outillage, nettoyage |
  | `docs` | la documentation seule (README, `doc/`, `design/HANDOFF.md`) |
  | `test` | des tests ajoutés ou corrigés, sans toucher au code testé |
  | `ci` | la CI (workflows) |
  | `build` | le build et le packaging (Dockerfile, Makefile, images) |
  | `revert` | l'annulation d'un changement (§ 5) |

  Le type des commits va avec le préfixe de la branche. Une branche peut aussi contenir d'autres types quand ils accompagnent le changement, par exemple un commit `test` ou `docs` dans une branche `feat/`.

- **portée** (obligatoire) : la partie du dépôt touchée.

  | portée | pour |
  |---|---|
  | `server` | `server/` : le serveur Go |
  | `app` | `app/` : le client Flutter |
  | `recommender` | `recommender/` : le service d'analyse et de recommandation |
  | `design` | `design/` : maquettes et `HANDOFF.md` |
  | `doc` | `doc/` |
  | `repo` | le reste, commun à tout le dépôt : `README.md`, `AGENTS.md`, `tools/`, `.github/` hors d'un service précis, `docker-compose.yml`… |

  Un commit qui touche plusieurs parties les liste sans espace : `feat(server,app): …`. Pour un revert, la portée est le numéro de la pull request annulée : `revert(#36): …` (§ 5).

- **description** : à l'impératif, en minuscules, sans point final, 72 caractères au plus pour toute la première ligne.
- **changement incompatible** (API, schéma de base, format de cache…) : `!` après la portée, et un pied `BREAKING CHANGE: …` qui dit ce qui casse.

### Exemples

```
feat(recommender): analyse tempo, key and loudness of each track
fix(app): keep playing while toggling shuffle
refactor(server): share the track query between lists and search
ci(recommender): run the tests on every pull request
docs(repo): point agents to the convention checks
feat(server,app): show the bpm in track lists
feat(server)!: return bpm and camelot in track lists
```

### Langue et contenu

- Les messages sont **en anglais**.
- Ils sont **courts** et disent **ce qu'on ajoute ou corrige, et pourquoi**, pas comment. Le comment, c'est le diff.
  - Oui : `fix(app): restart the track on "previous" instead of resuming an old position`
  - Non : `fix(app): reset _lastPosition in PlaybackController before calling seek(0)`
- Une ligne vide sépare l'en-tête du corps. Le pied donne les références : `Closes #27`, `Refs: <sha>`, `BREAKING CHANGE: …`.

## 4. Pull requests

### Titre et description

- Le titre suit le même format que les commits, portée comprise, et il est en anglais.
- La description tient en quelques lignes, en anglais : le besoin, ce qui change pour l'utilisateur, ce qui n'est pas testé ou reste à faire, et l'issue concernée (`Closes #27`).
- Le commit de merge reprend le titre comme en-tête et la description comme corps (réglage du dépôt) : l'un et l'autre finissent sur `main`.

### Historique de la branche

- Avant d'ouvrir la pull request, on nettoie l'historique : les commits « wip », « fix typo » ou « review » rejoignent le commit qu'ils corrigent (`git commit --fixup=<sha>`, puis `git rebase -i --autosquash origin/main`).
- Chaque commit forme une étape cohérente : il respecte le format, il compile et ses tests passent.
- On ne réécrit que ses propres branches, jamais `main` ni la branche de quelqu'un d'autre.

### Fusion

- **Merge commit classique, jamais en squash ni en rebase** : les commits de la branche arrivent tels quels sur `main`.
- La CI doit être verte avant la fusion : `ci` et `conventions` (§ 6).

## 5. Annuler un changement

Un revert est un changement comme un autre : il passe par une branche et une pull request.

- **Branche** : le préfixe `revert/`, puis la description du changement annulé : `revert/shuffle-playback-gap`.
- **Commit** : le type `revert`, avec pour portée le numéro de la pull request qui a introduit le changement annulé, puis l'en-tête exact du commit annulé. Le corps dit **pourquoi** on annule, et un pied `Refs:` donne le sha du commit annulé. La limite de 72 caractères vaut pour l'en-tête annulé, pas pour la ligne entière.

  ```
  revert(#36): fix(app): keep playing while toggling shuffle

  The fix drops the queue on Android when the app is in the background.

  Refs: 1a2b3c4
  ```

  Pour retrouver la PR d'un commit : `gh pr list --state merged --search <sha>`.
- **Toute une pull request** : on annule son commit de merge (ajouter `-m 1` à `git revert`). L'en-tête du commit de merge est le titre de la PR : c'est lui qu'on reprend après `revert(#<n°>): `.

On n'utilise pas tels quels le bouton « Revert » de GitHub ni `git revert` sans option : ils produisent une branche `revert-<n>-<branche>` et un message `Revert "<titre>"` qui ne suivent pas ces règles (la CI les refuse). En local, on lance `git revert --no-commit <sha>`, puis `git commit` avec un message conforme. Avec le bouton de GitHub, on recrée la branche sous un nom conforme et on corrige le titre de la PR et le message du commit avant de fusionner.

## 6. Vérifications

Les rulesets et la protection de branche de GitHub, qui imposeraient ces règles côté serveur, demandent GitHub Pro sur un dépôt privé. Les règles sont donc vérifiées par la CI, et en local par des hooks git. Les deux passent par le même script, `tools/conventions/check.sh`, qu'on peut aussi lancer à la main :

```bash
tools/conventions/check.sh title "fix(app): keep playing while toggling shuffle"
```

```bash
tools/conventions/check.sh commits origin/main HEAD
```

### CI

Le job `conventions` (`.github/workflows/conventions.yml`) tourne sur chaque pull request, et de nouveau quand on modifie son titre. Il vérifie le nom de la branche, le titre de la PR et chaque commit de la branche.

- Les commits de merge (ceux qui ramènent `main` dans la branche) ne sont pas vérifiés : c'est le titre de la PR qui donne l'en-tête du commit de merge sur `main`.
- Les commits `fixup!` / `squash!` sont refusés : ils doivent être regroupés avant la fusion.
- Sans protection de branche, GitHub ne peut pas bloquer la fusion quand ce job échoue : on ne fusionne pas tant qu'il n'est pas vert.

### En local

`tools/setup-git.sh`, une fois par clone, active :

- le modèle de message `.gitmessage`, qui rappelle le format dans l'éditeur à chaque `git commit` ;
- les hooks de `tools/git-hooks` : `commit-msg` vérifie le message (les `fixup!` y sont acceptés) et `pre-push` refuse un push sur `main` ou sur une branche mal nommée.

`--no-verify` contourne les hooks au besoin ; la CI vérifie quand même.

### Réglages du dépôt

Dans Settings → General → Pull Requests : seule la fusion par merge commit est permise, son message reprend le titre et la description de la PR, et la branche est supprimée après la fusion.
