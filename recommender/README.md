# recommender

Service Python de la phase 3. Il fait pour l'instant une seule chose : l'**analyse audio** des morceaux, y compris genre, ambiance et acoustique grâce aux modèles TensorFlow d'Essentia. Viendront ensuite les titres similaires, la radio infinie, les mix tirés de l'historique (`plays`) et la découverte via MusicBrainz / ListenBrainz (les `mbid` sont déjà stockés par le serveur).

## Fonctionnement

Le service tourne dans son propre conteneur (`recommender` dans `docker-compose.yml`). Il lit le dossier musique en lecture seule et ne touche jamais à la base : tout passe par l'API du serveur.

1. Il se connecte comme un appareil nommé `recommender`. Son jeton est gardé dans `DATA_DIR/recommender/token`, si bien qu'un redémarrage ne crée pas de nouvel appareil.
2. Il demande la file d'attente (`GET /api/v1/analysis/queue?analyzer=…`) : les titres jamais analysés, ou dont le fichier a changé depuis l'analyse, les plus récents d'abord ; puis ceux analysés par une autre version de l'analyseur (champ `analyzer`, par exemple `essentia-2.1b6.dev1389/1+discogs-effnet-2`). Une nouvelle version complète donc les anciennes analyses sans les effacer : elles restent affichées jusqu'à leur remplacement.
3. Il analyse chaque fichier dans un processus séparé : un fichier corrompu qui fait planter Essentia, ou qui bloque plus de `TTYFM_ANALYSIS_TIMEOUT`, ne bloque pas le reste.
4. Il renvoie le résultat (`PUT /api/v1/tracks/{id}/analysis`). En cas d'échec, l'erreur est enregistrée, et le titre n'est retenté que si son fichier change ou si on relance l'analyse.
5. Une fois la file vide, il revérifie toutes les `TTYFM_ANALYSIS_POLL` secondes.

Le processus tourne en priorité basse (`nice 10`). Une analyse prend environ 10 s pour un titre de 4 min (mesuré sur un CPU x86 à 4 cœurs ; un NAS peut être plus lent) : 5 s pour les algorithmes classiques, 3 à 4 s pour les modèles ML et 1 s pour charger Essentia et TensorFlow (chaque fichier est analysé dans un processus neuf). Une bibliothèque de 5 000 titres demande donc une quinzaine d'heures au premier lancement (moins avec `TTYFM_ANALYSIS_WORKERS` à 2 ou plus), puis seulement les ajouts.

## Ce qui est calculé

Le calcul utilise [Essentia](https://essentia.upf.edu) (`ttyfm_recommender/analyze.py`) : ses algorithmes classiques, puis ses modèles TensorFlow appliqués aux embeddings Discogs EffNet (audio ramené à 16 kHz mono, moyenne sur le morceau) :

| champ | algorithme | remarque |
|---|---|---|
| `bpm` | `RhythmExtractor2013` (multifeature) | ramené entre 60 et 200 bpm (demi / double tempo) |
| `key`, `scale`, `key_strength` | `KeyExtractor`, profil `bgate` | le serveur en déduit la notation Camelot (`8A`) |
| `loudness_lufs`, `loudness_range` | `LoudnessEBUR128` | intégrée, sur le signal stéréo d'origine |
| `danceability` | `Danceability` (DFA) | ramené de 0,5–2,5 à 0–1 |
| `energy` | heuristique (`features.py`) | ½ volume + 0,3 densité d'attaques + 0,2 brillance (centroïde spectral) |
| `genres` | `genre_discogs400` (400 styles Discogs) | deux entrées : le genre dont les styles pèsent le plus (nom en français : `électro`, `hip-hop`…), puis son style le plus fort (`synthwave`), chacun en part de l'activation totale |
| `mood` | `mood_happy`, `mood_sad`, `mood_relaxed`, `mood_aggressive`, `mood_party` | les classes à plus de 50 %, deux au plus, la plus sûre d'abord : `mélancolique · calme` ; absent si aucune |
| `acousticness` | `mood_acoustic` | probabilité de la classe « acoustique » |
| `embedding` | `discogs-effnet-bs64` | moyenne des embeddings (1280 valeurs) sur le morceau, ramenée à une norme de 1. Le serveur l'indexe avec `sqlite-vec` et en tire les titres similaires (`GET /api/v1/tracks/{id}/similar`, distance cosinus), base de la radio |

Les fichiers de plus de 15 min sont analysés sur leurs 15 premières minutes.

### Modèles

Les modèles (environ 25 Mo) viennent de [essentia.upf.edu/models](https://essentia.upf.edu/models/). `ttyfm_recommender/models.py` en tient la liste avec leur sha256 ; `python -m ttyfm_recommender.models DIR` télécharge ceux qui manquent et vérifie chaque fichier. L'image Docker le fait à la construction, dans `/models` (il faut donc un accès à essentia.upf.edu pour construire l'image). TensorFlow ajoute environ 300 Mo à l'image (paquet `essentia-tensorflow` à la place d'`essentia`).

Sans les modèles (`TTYFM_MODELS_DIR` vide ou incomplet), le service le signale au démarrage et ne calcule que les champs classiques, sous l'analyseur `…/1`. Une fois les modèles en place, l'analyseur devient `…/1+discogs-effnet-2` et toute la bibliothèque repasse dans la file pour gagner ces champs. Le suffixe vient de `models.VERSION`, à changer quand les fichiers ou la lecture de leurs sorties changent ; `discogs-effnet-2` ajoute l'`embedding` aux champs de `discogs-effnet-1`, si bien qu'une bibliothèque déjà analysée repasse entièrement dans la file (une quinzaine d'heures pour 5 000 titres), les anciens résultats restant affichés en attendant.

## Nouvelles sorties (MusicBrainz)

À côté de l'analyse, un second fil cherche les sorties des artistes de la bibliothèque sur MusicBrainz :

1. Il demande au serveur les artistes d'album à vérifier (`GET /releases/queue`) : ceux jamais vérifiés, puis ceux vérifiés il y a plus d'une semaine, les plus écoutés d'abord.
2. Sans identifiant MusicBrainz dans les tags, il cherche l'artiste par son nom exact. Entre deux homonymes, il garde celui dont les sorties ont le plus de titres en commun avec les albums de la bibliothèque.
3. Il liste ses albums, EP et singles. Il laisse de côté les compilations, les live, les remix (types secondaires) et les sorties sans date, puis les envoie au serveur (`PUT /artists/{id}/releases`). Le serveur les compare à la bibliothèque et en tire l'accueil (`GET /releases`).

MusicBrainz demande au plus une requête par seconde et un User-Agent qui nomme l'application (`tty.fm/<version> ( https://github.com/jennblngr/tty.fm )`). Le client attend donc 1,1 s entre deux requêtes. Sur un 503, qui arrive de temps en temps même sous la limite, il réessaie jusqu'à cinq fois en attendant de plus en plus longtemps. Le cache, c'est le serveur : un artiste n'est revérifié qu'au bout d'une semaine. `TTYFM_RELEASES=off` coupe ce fil.

## Configuration

| Variable | Défaut | Rôle |
|---|---|---|
| `TTYFM_SERVER_URL` | `http://server:4533` | adresse du serveur |
| `TTYFM_ADMIN_USER` / `TTYFM_ADMIN_PASSWORD` | `admin` / *(requis)* | identifiants, les mêmes que le serveur |
| `TTYFM_MUSIC_DIR` | `/music` | même dossier que le serveur (les chemins de la file sont relatifs) |
| `TTYFM_STATE_DIR` | `/state` | jeton de l'appareil |
| `TTYFM_MODELS_DIR` | `/models` | modèles TensorFlow (déjà dans l'image) |
| `TTYFM_ANALYSIS_WORKERS` | `1` | analyses en parallèle |
| `TTYFM_ANALYSIS_TIMEOUT` | `300` | secondes max par fichier |
| `TTYFM_ANALYSIS_POLL` | `60` | secondes entre deux vérifications quand la file est vide |
| `TTYFM_ANALYSIS_NICE` | `10` | priorité CPU |
| `TTYFM_RELEASES` | `on` | nouvelles sorties sur MusicBrainz (`off` pour couper) |
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
.venv/bin/python -m ttyfm_recommender.models ../data/models
TTYFM_MODELS_DIR=../data/models .venv/bin/python -m unittest discover -s tests -t .   # dont une analyse réelle d'un fichier synthétique
.venv/bin/ruff format . && .venv/bin/ruff check .
TTYFM_SERVER_URL=http://localhost:4533 TTYFM_ADMIN_PASSWORD=admin TTYFM_MUSIC_DIR=~/Music \
  TTYFM_STATE_DIR=../data/recommender TTYFM_MODELS_DIR=../data/models .venv/bin/python -m ttyfm_recommender
```
