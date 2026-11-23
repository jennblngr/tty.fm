# Installation

tty.fm s'installe avec Docker Compose sur n'importe quelle machine Linux qui garde la musique à portée : un NAS, un mini-PC, un serveur à la maison. Deux conteneurs tournent côte à côte : le serveur (`server`) et le service d'analyse et de recommandations (`recommender`). Le rôle de chacun est décrit dans [architecture.md](architecture.md).

Pour un NAS UGREEN sous UGOS Pro, avec images construites sur un Mac et déploiement par SSH, voir [nas-ugreen.md](nas-ugreen.md).

## Prérequis

- Docker avec le plugin Compose.
- Une machine **x86_64** : `docker-compose.yml` fixe `platform: linux/amd64`, et Essentia, utilisé par le recommender, ne publie de wheel que pour Linux x86_64. Ailleurs (Apple Silicon par exemple), les images se construisent en émulation.
- Un accès à `essentia.upf.edu` au moment de construire l'image du recommender : elle y télécharge ses modèles (environ 25 Mo, voir [recommender/README.md](../recommender/README.md)).

## Mise en route

1. **Configurer** : copier `.env.example` en `.env` à la racine du dépôt, puis renseigner au moins :
   - `MUSIC_DIR` : le dossier de musique sur la machine (monté en lecture seule) ;
   - `DATA_DIR` : le dossier des données (base, pochettes, caches) ;
   - `ADMIN_PASSWORD` : le mot de passe du compte unique ;
   - `PUID` / `PGID` : l'utilisateur propriétaire des dossiers (`id` dans un terminal). Par défaut, le conteneur tourne en uid 0, mais sans aucune capability (`cap_drop: ALL`, `no-new-privileges`) : il ne peut pas contourner les permissions des fichiers.

2. **Construire et lancer** :
   ```bash
   docker compose up -d --build
   docker compose logs --tail 20
   ```
   Le premier scan démarre tout seul ; le log affiche `scan done … seen=… added=…`. Les fichiers ajoutés ensuite au dossier musique sont détectés une dizaine de secondes après la fin de la copie.

3. **Vérifier** : `curl http://<adresse>:4533/api/v1/health` doit répondre `{"status":"ok",…}`.

4. **Se connecter** depuis l'app ([app/README.md](../app/README.md)) avec l'adresse du serveur et le compte admin.

Le recommender commence alors l'analyse audio en arrière-plan, à basse priorité. Une première analyse demande une quinzaine d'heures pour 5 000 titres ; `docker compose stop recommender` la met en pause.

**Mise à jour** : `git pull`, puis `docker compose up -d --build`. Les migrations de la base s'appliquent au démarrage du serveur.

**Accès distant** : passer par un VPN (Tailscale, WireGuard…) plutôt que d'ouvrir le port 4533 sur Internet. Dans l'app, l'adresse du serveur sert partout, et l'adresse locale (facultative) est utilisée en priorité quand elle répond.

**Sauvegarde** : le dossier `DATA_DIR` suffit (la base `ttyfm.db`, plus les caches, qui sont régénérables).

**Tester localement avec Docker** : créer un `.env` de test (sur Mac avec Colima, des chemins sous `$HOME`, que Colima partage avec la VM), puis lancer `docker compose --env-file <fichier> up -d`. Sur Mac, fsnotify ne voit pas les fichiers ajoutés depuis macOS (limite du partage virtiofs) : le scan périodique ou `POST /api/v1/admin/scan` prend le relais.

## Configuration (variables d'environnement)

Dans `docker-compose.yml`, les variables `TTYFM_*` sont alimentées par `.env`.

| Variable | Défaut | Rôle |
|---|---|---|
| `TTYFM_MUSIC_DIR` | `/music` | racine de la bibliothèque |
| `TTYFM_DATA_DIR` | `/data` | base, pochettes, cache de transcodage |
| `TTYFM_LISTEN` | `:4533` | adresse d'écoute |
| `TTYFM_ADMIN_USER` | `admin` | utilisateur unique |
| `TTYFM_ADMIN_PASSWORD` | *(généré et affiché dans le log si vide)* | mot de passe ; s'il change dans `.env`, il est mis à jour au démarrage |
| `TTYFM_SCAN_ON_START` | `true` | scan incrémental au démarrage |
| `TTYFM_WATCH` | `true` | surveillance fsnotify du dossier musique |
| `TTYFM_WATCH_DEBOUNCE` | `10s` | délai avant rescan après des modifications |
| `TTYFM_SCAN_INTERVAL` | `1h` | scan incrémental périodique (filet de sécurité) |
| `TTYFM_SCAN_WORKERS` | nb de CPU | lectures de tags en parallèle |
| `TTYFM_TRANSCODE_CACHE_MB` | `2048` | taille max du cache de transcodage |
| `TTYFM_FFMPEG` | `ffmpeg` | binaire ffmpeg |
| `TTYFM_LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error` |

Le service `recommender` a ses propres variables (`ANALYSIS_WORKERS` dans `.env`, etc.) : voir [recommender/README.md](../recommender/README.md).

## Comportement du scan

- **Incrémental** : seuls les fichiers nouveaux ou modifiés (taille ou date de modification) sont relus.
- **Fichiers déplacés ou renommés** : ils sont reconnus (même taille, durée et titre) et gardent leur identifiant. Les playlists, les favoris et l'historique restent donc attachés.
- **Fichiers supprimés** : ils sont masqués, puis effacés définitivement après 30 jours. S'ils réapparaissent avant, ils retrouvent leur identifiant.
- **Volume non monté** : si le dossier musique est vide alors que la bibliothèque ne l'est pas, le scan s'arrête au lieu de tout marquer comme supprimé.
- **Pochettes** : le serveur prend `cover.*`, `folder.*`, `front.*` ou `album.*` dans le dossier, sinon l'image intégrée au premier morceau. Elles sont redimensionnées en 64, 300 et 800 px.
- **Dossiers ignorés** : dossiers cachés, `@eaDir`, `#recycle`.
- **Scan manuel** : `POST /api/v1/admin/scan` (avec `?full=1` pour tout relire), voir [api.md](api.md).
- **Paroles** : fichiers `.lrc` ou `.txt` à côté du morceau, ou tags, voir [api.md](api.md#paroles).
