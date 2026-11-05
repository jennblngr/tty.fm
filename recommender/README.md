# recommender

Service Python de la phase 3. Il fait pour l'instant une seule chose : l'**analyse audio** des morceaux. Viendront ensuite les titres similaires, la radio infinie, les mix tirés de l'historique (`plays`) et la découverte via MusicBrainz / ListenBrainz (les `mbid` sont déjà stockés par le serveur).

## Fonctionnement

Le service tourne dans son propre conteneur (`recommender` dans `docker-compose.yml`). Il lit le dossier musique en lecture seule et ne touche jamais à la base : tout passe par l'API du serveur.

1. Il se connecte comme un appareil nommé `recommender`. Son jeton est gardé dans `DATA_DIR/recommender/token`, si bien qu'un redémarrage ne crée pas de nouvel appareil.
2. Il demande la file d'attente (`GET /api/v1/analysis/queue`) : les titres jamais analysés, ou dont le fichier a changé depuis l'analyse, les plus récents d'abord.
3. Il analyse chaque fichier dans un processus séparé : un fichier corrompu qui fait planter Essentia, ou qui bloque plus de `TTYFM_ANALYSIS_TIMEOUT`, ne bloque pas le reste.
4. Il renvoie le résultat (`PUT /api/v1/tracks/{id}/analysis`). En cas d'échec, l'erreur est enregistrée, et le titre n'est retenté que si son fichier change ou si on relance l'analyse.
5. Une fois la file vide, il revérifie toutes les `TTYFM_ANALYSIS_POLL` secondes.

Le processus tourne en priorité basse (`nice 10`). Une analyse prend 1 à 3 s par titre sur un CPU récent. Une bibliothèque de 5 000 titres demande donc quelques heures au premier lancement, puis seulement les ajouts.

## Ce qui est calculé

Le calcul utilise les algorithmes classiques d'[Essentia](https://essentia.upf.edu) (`ttyfm_recommender/analyze.py`) :

| champ | algorithme | remarque |
|---|---|---|
| `bpm` | `RhythmExtractor2013` (multifeature) | ramené entre 60 et 200 bpm (demi / double tempo) |
| `key`, `scale`, `key_strength` | `KeyExtractor`, profil `bgate` | le serveur en déduit la notation Camelot (`8A`) |
| `loudness_lufs`, `loudness_range` | `LoudnessEBUR128` | intégrée, sur le signal stéréo d'origine |
| `danceability` | `Danceability` (DFA) | ramené de 0,5–2,5 à 0–1 |
| `energy` | heuristique (`features.py`) | ½ volume + 0,3 densité d'attaques + 0,2 brillance (centroïde spectral) |

Les fichiers de plus de 15 min sont analysés sur leurs 15 premières minutes.

**Pas encore calculés** : genre et sous-genre en %, ambiance, acoustique. Ils demandent les modèles TensorFlow d'Essentia (`discogs-effnet`, classifieurs `mood_*`), soit environ 300 Mo de plus dans l'image. Le schéma et l'API ont déjà les champs (`genres`, `mood`, `acousticness`), et l'app les affiche dès qu'ils sont remplis.

## Configuration

| Variable | Défaut | Rôle |
|---|---|---|
| `TTYFM_SERVER_URL` | `http://server:4533` | adresse du serveur |
| `TTYFM_ADMIN_USER` / `TTYFM_ADMIN_PASSWORD` | `admin` / *(requis)* | identifiants, les mêmes que le serveur |
| `TTYFM_MUSIC_DIR` | `/music` | même dossier que le serveur (les chemins de la file sont relatifs) |
| `TTYFM_STATE_DIR` | `/state` | jeton de l'appareil |
| `TTYFM_ANALYSIS_WORKERS` | `1` | analyses en parallèle |
| `TTYFM_ANALYSIS_TIMEOUT` | `300` | secondes max par fichier |
| `TTYFM_ANALYSIS_POLL` | `60` | secondes entre deux vérifications quand la file est vide |
| `TTYFM_ANALYSIS_NICE` | `10` | priorité CPU |
| `TTYFM_LOG_LEVEL` | `info` | |

Pour mettre l'analyse en pause : `docker compose stop recommender`.

## Développement

Prérequis : Python 3.12 ou 3.13 sous Linux x86_64. Essentia ne publie pas de wheel pour macOS : sur le Mac, passer par l'image Docker (Colima, comme pour le serveur).

```bash
# Mac : construire et lancer contre un serveur local
docker build --platform linux/amd64 -t ttyfm-recommender recommender/
docker run --rm --platform linux/amd64 -v ~/Music:/music:ro -v "$PWD/data/recommender:/state" \
  -e TTYFM_SERVER_URL=http://host.docker.internal:4533 -e TTYFM_ADMIN_PASSWORD=admin ttyfm-recommender
```

Sous Linux :

```bash
cd recommender
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt ruff
.venv/bin/python -m unittest discover -s tests -t .   # dont une analyse réelle d'un fichier synthétique
.venv/bin/ruff format . && .venv/bin/ruff check .
TTYFM_SERVER_URL=http://localhost:4533 TTYFM_ADMIN_PASSWORD=admin TTYFM_MUSIC_DIR=~/Music \
  TTYFM_STATE_DIR=../data/recommender .venv/bin/python -m ttyfm_recommender
```
