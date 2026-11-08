# tty.fm

Lecteur de musique auto-hébergé : un serveur Go + SQLite tourne sur le NAS, le client Flutter natif tourne sur macOS et Android (Windows et iOS plus tard).

> Le nom affiché est *tty.fm* (`app.Title` dans `server/internal/app/app.go`, `appDisplayName` dans `app/lib/app_info.dart`). L’identifiant technique est `ttyfm` : module Go, binaire, image Docker, préfixe `TTYFM_` des variables, base `ttyfm.db`. Les identifiants de bundle sont `fm.tty.app`.

```
server/       API REST + streaming (Go, SQLite WAL + FTS5, ffmpeg)
app/          client Flutter
recommender/  service de recommandations (phase 3, Python + Essentia) : analyse audio (dont genre et ambiance) pour l'instant
```

## Installation sur le NAS (UGREEN DXP2800, UGOS Pro)

Prérequis : Docker activé dans UGOS Pro, SSH activé (Panneau de configuration → Terminal → SSH, puis **Appliquer**). Les commandes ci-dessous se lancent depuis le Terminal du Mac ; remplacer `user` et `nas` par le compte UGOS et l'adresse du NAS.

1. **Accès sans mot de passe** (une fois) :
   ```bash
   ssh-copy-id user@nas                                   # demande le mot de passe UGOS
   ssh -t user@nas 'sudo usermod -aG docker user'         # Docker sans sudo
   ```
   Une mise à jour d'UGOS peut retirer le compte du groupe `docker` ; il suffit alors de relancer la deuxième commande.

2. **Construire l'image sur le Mac** (Apple Silicon, émulation x86_64 via Colima + Rosetta, environ 3 min) et l'envoyer :
   ```bash
   colima start --vm-type vz --vz-rosetta --cpu 4 --memory 4   # une fois par session
   docker build --platform linux/amd64 --build-arg VERSION=$(git describe --always) -t ttyfm:latest server/
   docker build --platform linux/amd64 --build-arg VERSION=$(git describe --always) -t ttyfm-recommender:latest recommender/
   docker save ttyfm:latest ttyfm-recommender:latest | gzip | ssh user@nas 'gunzip | docker load'
   ```
   La seconde image est le service d'analyse audio ([recommender/README.md](recommender/README.md)). Il tourne à côté du serveur et peut être arrêté à part (`docker compose stop recommender`).
   (`scp` vers `/volume1` échoue sur UGOS : le SFTP ne voit pas les volumes, d'où le passage par `ssh`.)

3. **Configurer** dans `/volume1/docker/ttyfm` :
   ```bash
   ssh user@nas 'mkdir -p /volume1/docker/ttyfm/data'
   sed '/^    build:/,/^        VERSION/d' docker-compose.yml | ssh user@nas 'cat > /volume1/docker/ttyfm/docker-compose.yml'
   ssh user@nas 'cat > /volume1/docker/ttyfm/.env' < .env   # préparé à partir de .env.example
   ```
   Dans `.env` : `MUSIC_DIR` (ex. `/volume1/music`), `DATA_DIR` (ex. `/volume1/docker/ttyfm/data`), `ADMIN_PASSWORD`.

   **Utilisateur du conteneur** : UGOS Pro refuse la surveillance inotify des dossiers partagés aux utilisateurs autres que root (`watch: cannot add … permission denied`). Le conteneur tourne donc en uid 0, mais **sans aucune capability** (`cap_drop: ALL`, `no-new-privileges`) : il ne peut pas contourner les permissions des fichiers, et la musique est montée en lecture seule.

4. **Lancer** :
   ```bash
   ssh user@nas 'cd /volume1/docker/ttyfm && docker compose up -d && docker compose logs --tail 20'
   ```
   Le projet apparaît aussi dans l'application Docker de UGOS Pro. Le premier scan démarre automatiquement ; le log affiche `scan done … seen=… added=…`. Les fichiers copiés ensuite dans le dossier musique (par SMB depuis le Mac, par exemple) sont détectés une dizaine de secondes après la fin de la copie.

5. **Vérifier** : `curl http://nas:4533/api/v1/health` doit répondre `{"status":"ok",…}`.

**Accès distant** : Tailscale sur le NAS (paquet UGOS ou conteneur `tailscale/tailscale` en `network_mode: host`) et sur les clients. Dans l'application, utiliser l'adresse Tailscale du NAS (`100.x.y.z:4533` ou `nas.<tailnet>.ts.net:4533`) comme adresse du serveur, et l'adresse locale comme adresse locale. Ne pas ouvrir le port 4533 sur Internet.

**Mise à jour** : `tools/deploy-nas.sh` fait tout depuis le Mac. Il construit l'image, l'envoie, sauvegarde la base (serveur arrêté quelques secondes, dans `/volume1/docker/ttyfm/backups`, 5 copies gardées), relance le service et attend que `/health` annonce la nouvelle version. Une fois : copier `.deploy.env.example` en `.deploy.env` et y mettre `TTYFM_NAS=user@nas`.

```bash
tools/deploy-nas.sh                  # le serveur (par défaut)
tools/deploy-nas.sh recommender      # le service d'analyse
tools/deploy-nas.sh all --compose    # les deux, et le docker-compose.yml du dépôt
```

Les migrations de la base s'appliquent au démarrage du serveur. À la main : refaire l'étape 2, puis `ssh user@nas 'cd /volume1/docker/ttyfm && docker compose up -d'`.

**Tester localement avec Docker** : créer un `.env` de test (chemins sous `$HOME`, que Colima partage avec la VM), puis lancer `docker compose --env-file <fichier> up -d`. Sur Mac, fsnotify ne voit pas les fichiers ajoutés depuis macOS (limite du partage virtiofs) : le scan périodique ou `POST /api/v1/admin/scan` prend le relais. Sur le NAS, la surveillance fonctionne normalement.

**Sauvegarde** : le dossier `DATA_DIR` suffit (la base `ttyfm.db`, plus les caches, qui sont régénérables).

### Configuration (variables d'environnement)

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

Le service `recommender` a ses propres variables (`ANALYSIS_WORKERS` dans `.env`, etc.) : voir [recommender/README.md](recommender/README.md).

### Comportement du scan

- **Incrémental** : seuls les fichiers nouveaux ou modifiés (taille ou date de modification) sont relus.
- **Fichiers déplacés ou renommés** : ils sont reconnus (même taille, durée et titre) et gardent leur identifiant. Les playlists, les favoris et l'historique restent donc attachés.
- **Fichiers supprimés** : ils sont masqués, puis effacés définitivement après 30 jours. S'ils réapparaissent avant, ils retrouvent leur identifiant.
- **Volume non monté** : si le dossier musique est vide alors que la bibliothèque ne l'est pas, le scan s'arrête au lieu de tout marquer comme supprimé.
- **Pochettes** : le serveur prend `cover.*`, `folder.*`, `front.*` ou `album.*` dans le dossier, sinon l'image intégrée au premier morceau. Elles sont redimensionnées en 64, 300 et 800 px.
- **Dossiers ignorés** : dossiers cachés, `@eaDir`, `#recycle`.
- **Scan manuel** : `POST /api/v1/admin/scan` (avec `?full=1` pour tout relire).

## API (v1)

Toutes les routes sauf `health` et `auth/login` exigent `Authorization: Bearer <jeton>`. Le stream et les pochettes acceptent aussi `?token=`.

| Méthode | Route | Notes |
|---|---|---|
| GET | `/api/v1/health` | |
| POST | `/api/v1/auth/login` | `{username, password, device_name, platform}` → `{token, device}` |
| POST | `/api/v1/auth/logout` | révoque le jeton courant |
| GET | `/api/v1/me` | appareil courant + stats de la bibliothèque |
| GET/DELETE | `/api/v1/devices[/{id}]` | |
| GET | `/api/v1/home` | ajouts récents, récemment écoutés |
| GET | `/api/v1/artists?cursor=&limit=&album_artists=1` | pagination par curseur (`next`) |
| GET | `/api/v1/artists/{id}` | artiste + albums |
| GET | `/api/v1/albums?sort=name\|added\|year&cursor=&limit=` | |
| GET | `/api/v1/albums/{id}` | album + morceaux |
| GET | `/api/v1/tracks?sort=name\|added&cursor=&limit=`, `/tracks/{id}` | |
| GET | `/api/v1/tracks/{id}/analysis` | `{analysis, compatible}` : bpm, tonalité (+ Camelot), LUFS, énergie, dansant… et les titres qui s'enchaînent bien (ton voisin, tempo à ±6 %) ; 404 si pas encore analysé. Les titres analysés portent aussi `bpm` et `camelot` dans toutes les listes |
| PUT/DELETE | `/api/v1/tracks/{id}/analysis` | PUT : résultat envoyé par `recommender` (avec `embedding`, 1280 valeurs, quand il a les modèles ML) ; DELETE : relancer l'analyse du titre |
| GET | `/api/v1/tracks/{id}/similar?limit=` | `{items}` : les titres au son le plus proche (distance cosinus entre embeddings, table `sqlite-vec`), chacun avec `similarity` (1 = identique), sans le titre lui-même ni les archivés ; vide tant que le titre n'a pas d'embedding, 404 s'il n'existe pas |
| GET | `/api/v1/radio?track=\|artist=&recent=&exclude=&limit=` | `{seed, mode, items}` : un lot de radio (20 par défaut, 50 au plus) à partir d'un titre ou d'un artiste (moyenne de ses titres). Voisins du vecteur moyen de la graine et des 3 derniers titres de `recent` (ids séparés par des virgules, du plus ancien au plus récent), léger bonus pour un enchaînement compatible avec le dernier (tonalité voisine, bpm ±6 %) ; au plus 1 titre par album et 2 par artiste, jamais le même artiste deux fois de suite (assoupli si la bibliothèque est trop petite). Sans `recent`, `exclude` (titres déjà en file), le titre de départ ni les archivés. `mode` vaut `similar`, ou `fallback` sans embedding : même genre ou même artiste, puis le reste. Pour la suite, rappeler avec la même graine, `recent` et `exclude` à jour. 400 sans graine ou avec les deux, 404 si elle n'existe pas |
| GET | `/api/v1/mixes`, `/api/v1/mixes/{n}` | mix du jour : `{items}` sans les titres (`position`, `name` « mix_01 », `description` « dance-pop · festif », `artists`, `cover_ids`, `track_count`, `duration_ms`), aussi dans `/home` sous `mixes` ; `/mixes/{n}` avec `tracks`. Calculés chaque nuit à 4 h (et au démarrage s'il en manque) : k-means sur les embeddings des titres vraiment écoutés ces 28 jours (non passés, ≥ 30 s), puis pour chaque groupe ses titres les plus écoutés et des voisins peu ou jamais écoutés ; stables sur la journée (table `daily_mixes`). Aucun mix sous 8 titres écoutés |
| GET | `/api/v1/releases?days=&limit=` | nouvelles sorties : `{items}`, celles des `days` derniers jours (90 par défaut) et celles à venir, plus récentes d'abord (`artist_id`, `artist`, `title`, `kind` album/ep/single, `released` AAAA-MM-JJ ou AAAA-MM, `upcoming`, `album_id` si la bibliothèque l'a) ; aussi dans `/home` sous `new_releases` (6 au plus) |
| GET | `/api/v1/releases/queue?limit=` | pour le recommender : artistes d'album à chercher sur MusicBrainz (`artist_id`, `name`, `mbid` connu, `albums`), jamais vérifiés ou vérifiés il y a plus d'une semaine |
| PUT | `/api/v1/artists/{id}/releases` | pour le recommender : `{mbid, releases: [{mbid, title, kind, released}]}` remplace les sorties de l'artiste (`mbid` nul : inconnu de MusicBrainz) |
| GET/PATCH/DELETE | `/api/v1/analysis` | GET : `{enabled, total, analyzed, failed, pending}` ; PATCH `{enabled}` : « analyse audio » on/off pour tout le serveur (off : la file reste vide, les analyses faites restent) ; DELETE : tout réanalyser |
| GET | `/api/v1/analysis/queue?limit=&analyzer=` | titres à analyser (`id`, `path` relatif, `file_mtime`) ; avec `analyzer`, aussi ceux analysés par une autre version ; vide quand l'analyse est désactivée |
| GET | `/api/v1/tracks/{id}/lyrics` | `{synced, source, lines: [{ms, text}]}` ; 404 sans paroles |
| GET | `/api/v1/search?q=&genre=&year_min=&year_max=&format=&bpm_min=&bpm_max=&camelot=&limit=` | préfixes, accents ignorés ; filtres seuls possibles. `bpm_min` / `bpm_max` (bornes comprises) et `camelot` (`1A`…`12B`) ne gardent que les titres analysés ; 400 si la tonalité ou la plage est invalide |
| GET | `/api/v1/search/facets` | genres, formats, années disponibles |
| GET | `/api/v1/covers/{id}?size=64\|300\|800` | cache immuable |
| GET | `/api/v1/stream/{id}` | original, requêtes Range |
| GET | `/api/v1/stream/{id}?format=opus\|aac\|mp3&bitrate=128&offset=s` | transcodé (mis en cache, Range au 2ᵉ accès) |
| GET | `/api/v1/playlists/tree` | arborescence complète |
| POST/PATCH/DELETE | `/api/v1/folders[/{id}]` | PATCH : `name`, `parent_id` (null = racine), `position` |
| POST/GET/PATCH/DELETE | `/api/v1/playlists[/{id}]` | PATCH : `name`, `folder_id`, `position` |
| GET/POST/PATCH | `/api/v1/playlists/{id}/tracks` | POST `{track_ids, at_position?}`, PATCH `{entry_id, to_position}` |
| DELETE | `/api/v1/playlists/{id}/tracks/{entry_id}` | |
| POST | `/api/v1/plays` | `{plays: [{track_id, started_at (ms), listened_ms, skipped, context_kind?, context_id?}]}` |
| GET | `/api/v1/favorites[?full=1]` | identifiants, ou listes complètes |
| PUT/DELETE | `/api/v1/favorites/{tracks\|albums\|artists}/{id}` | |
| GET | `/api/v1/hidden` | identifiants des titres masqués (`{"tracks": [...]}`) |
| PUT/DELETE | `/api/v1/hidden/{id}` | masquer un titre (grisé, jamais mis en file) ou le réafficher |
| POST/GET | `/api/v1/admin/scan[?full=1]` | lancer / état |
| GET | `/api/v1/ws` | WebSocket du hub en direct (voir ci-dessous) |

### Hub en direct (`/api/v1/ws`)

Chaque app garde une WebSocket ouverte (jeton en `Authorization` ou `?token=`). Messages JSON avec un champ `type` :

- **Serveur → app** : `hello` (son `device_id` et les autres appareils en ligne, avec leur état), `presence` (un appareil arrive ou part), `state` (état de lecture d'un autre appareil), `command` (commande reçue d'un autre appareil), `changed` (`library`, `playlists`, `favorites` ou `hidden` : rafraîchir), `error`.
- **App → serveur** : `state` (son propre état de lecture, opaque pour le serveur), `command` (`target`, `action`, `args`).
- **Actions** : `play`, `pause`, `toggle`, `next`, `previous`, `seek {ms}`, `volume {value}`, `jump {index}`, `remove {index}`, `move {from, to}`, `shuffle {on}`, `repeat {mode}`, `load {file d'attente…}`, `transfer {to}` (l'appareil source envoie sa file à `to` puis se met en pause).

Le serveur garde en mémoire le dernier état de chaque appareil connecté et relaie ; rien n'est persisté.

### Paroles

Le serveur cherche, dans l'ordre : `morceau.lrc`, puis `morceau.txt` à côté du fichier audio, puis les paroles intégrées aux tags (`LYRICS`, `UNSYNCEDLYRICS`). Les fichiers LRC (`[mm:ss.xx]texte`, plusieurs horodatages par ligne, `[offset:]`) donnent des paroles synchronisées.

## Développement

### Serveur

Prérequis : Go ≥ 1.27, un compilateur C (Xcode CLT sur macOS), ffmpeg (`brew install ffmpeg`).

```bash
cd server
make test                                   # tests (ffmpeg requis pour scanner et API)
TTYFM_MUSIC_DIR=~/Music make run       # serveur local sur :4533, données dans ../data
```

Le build tag `sqlite_fts5` est obligatoire : passer par le `Makefile`, ou ajouter `-tags sqlite_fts5` à la main.

### Client

Voir [app/README.md](app/README.md).
