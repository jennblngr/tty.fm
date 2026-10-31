# selfstream

Lecteur de musique auto-hébergé : un serveur Go + SQLite tourne sur le NAS, le client Flutter natif tourne sur macOS et Android (Windows et iOS plus tard).

> *selfstream* est un nom de travail. Il est centralisé dans `server/internal/app/app.go` (nom, préfixe des variables d'environnement), `.env` (`APP_NAME`) et `app/lib/app_info.dart`.

```
server/       API REST + streaming (Go, SQLite WAL + FTS5, ffmpeg)
app/          client Flutter
recommender/  service de recommandations (phase 3, vide)
```

## Installation sur le NAS (UGREEN DXP2800, UGOS Pro)

Prérequis : Docker activé dans UGOS Pro, accès SSH activé (Panneau de configuration → Terminal).

1. **Créer les dossiers** dans un dossier partagé, par exemple :
   - musique : `/volume1/Music` (lecture seule pour le conteneur)
   - données : `/volume1/docker/selfstream` (base SQLite, cache des pochettes et du transcodage)

2. **Copier le dépôt sur le NAS**, par exemple dans `/volume1/docker/selfstream-src` :
   ```bash
   rsync -av --exclude app/ --exclude .git/ ./ admin@nas:/volume1/docker/selfstream-src/
   ```

3. **Configurer** :
   ```bash
   ssh admin@nas
   cd /volume1/docker/selfstream-src
   cp .env.example .env
   id            # → renseigner PUID / PGID dans .env
   vi .env       # MUSIC_DIR, DATA_DIR, ADMIN_PASSWORD
   ```
   L'utilisateur `PUID` doit pouvoir lire `MUSIC_DIR` et écrire dans `DATA_DIR`.

4. **Construire et lancer** :
   ```bash
   sudo docker compose up -d --build
   sudo docker compose logs -f
   ```
   On peut aussi importer `docker-compose.yml` comme projet dans l'application Docker de UGOS Pro (Projet → Créer), en pointant sur ce dossier.

   Le premier scan démarre automatiquement. Le log affiche `scan done … seen=… added=…`.

5. **Vérifier** : `curl http://nas:4533/api/v1/health` doit répondre `{"status":"ok",…}`.

**Accès distant** : installer Tailscale sur le NAS (paquet UGOS ou conteneur `tailscale/tailscale`) et sur les clients. Utiliser ensuite l'adresse Tailscale du NAS (`http://nas.<tailnet>.ts.net:4533`) dans l'application. Ne pas ouvrir le port 4533 sur Internet.

**Mise à jour** : recopier le dépôt, puis `sudo docker compose up -d --build`.

**Variante sans build sur le NAS** : construire l'image sur le Mac (Apple Silicon, émulation x86_64 via Colima + Rosetta, environ 3 min), puis l'envoyer au NAS :
```bash
colima start --vm-type vz --vz-rosetta --cpu 4 --memory 4   # une fois par session
docker buildx build --platform linux/amd64 --load -t selfstream:latest server/
docker save selfstream:latest | gzip | ssh admin@nas 'gunzip | sudo docker load'
ssh admin@nas 'cd /volume1/docker/selfstream-src && sudo docker compose up -d'
```

**Tester localement avec Docker** : créer un `.env` de test (chemins sous `$HOME`, que Colima partage avec la VM), puis lancer `docker compose --env-file <fichier> up -d`. Sur Mac, fsnotify ne voit pas les fichiers ajoutés depuis macOS (limite du partage virtiofs) : le scan périodique ou `POST /api/v1/admin/scan` prend le relais. Sur le NAS, la surveillance fonctionne normalement.

**Sauvegarde** : le dossier `DATA_DIR` suffit (la base `selfstream.db`, plus les caches, qui sont régénérables).

### Configuration (variables d'environnement)

Dans `docker-compose.yml`, les variables `SELFSTREAM_*` sont alimentées par `.env`.

| Variable | Défaut | Rôle |
|---|---|---|
| `SELFSTREAM_MUSIC_DIR` | `/music` | racine de la bibliothèque |
| `SELFSTREAM_DATA_DIR` | `/data` | base, pochettes, cache de transcodage |
| `SELFSTREAM_LISTEN` | `:4533` | adresse d'écoute |
| `SELFSTREAM_ADMIN_USER` | `admin` | utilisateur unique |
| `SELFSTREAM_ADMIN_PASSWORD` | *(généré et affiché dans le log si vide)* | mot de passe ; s'il change dans `.env`, il est mis à jour au démarrage |
| `SELFSTREAM_SCAN_ON_START` | `true` | scan incrémental au démarrage |
| `SELFSTREAM_WATCH` | `true` | surveillance fsnotify du dossier musique |
| `SELFSTREAM_WATCH_DEBOUNCE` | `10s` | délai avant rescan après des modifications |
| `SELFSTREAM_SCAN_INTERVAL` | `1h` | scan incrémental périodique (filet de sécurité) |
| `SELFSTREAM_SCAN_WORKERS` | nb de CPU | lectures de tags en parallèle |
| `SELFSTREAM_TRANSCODE_CACHE_MB` | `2048` | taille max du cache de transcodage |
| `SELFSTREAM_FFMPEG` | `ffmpeg` | binaire ffmpeg |
| `SELFSTREAM_LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error` |

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
| GET | `/api/v1/search?q=&limit=` | préfixes, accents ignorés |
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
| POST/GET | `/api/v1/admin/scan[?full=1]` | lancer / état |

## Développement

### Serveur

Prérequis : Go ≥ 1.27, un compilateur C (Xcode CLT sur macOS), ffmpeg (`brew install ffmpeg`).

```bash
cd server
make test                                   # tests (ffmpeg requis pour scanner et API)
SELFSTREAM_MUSIC_DIR=~/Music make run       # serveur local sur :4533, données dans ../data
```

Le build tag `sqlite_fts5` est obligatoire : passer par le `Makefile`, ou ajouter `-tags sqlite_fts5` à la main.

### Client

Voir [app/README.md](app/README.md).
