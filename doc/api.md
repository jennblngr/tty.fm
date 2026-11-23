# API REST v1

Le serveur expose une API REST sous `/api/v1`, un hub WebSocket et le streaming audio. Les clients (l'app Flutter, le service `recommender`) ne passent que par elle. Vue d'ensemble des composants : [architecture.md](architecture.md).

## Routes

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
| GET | `/api/v1/mixes`, `/api/v1/mixes/{n}` | mix du jour : `{items}` sans les titres (`position`, `name` « mix_01 », `description` « synth-pop · festif », `artists`, `cover_ids`, `track_count`, `duration_ms`), aussi dans `/home` sous `mixes` ; `/mixes/{n}` avec `tracks`. Calculés chaque nuit à 4 h (et au démarrage s'il en manque) : k-means sur les embeddings des titres vraiment écoutés ces 28 jours (non passés, ≥ 30 s), puis pour chaque groupe ses titres les plus écoutés et des voisins peu ou jamais écoutés ; stables sur la journée (table `daily_mixes`). Aucun mix sous 8 titres écoutés |
| GET | `/api/v1/releases?days=&limit=` | nouvelles sorties : `{items}`, celles des `days` derniers jours (90 par défaut) et celles à venir, plus récentes d'abord (`artist_id`, `artist`, `title`, `kind` album/ep/single, `released` AAAA-MM-JJ ou AAAA-MM, `upcoming`, `album_id` si la bibliothèque l'a) ; aussi dans `/home` sous `new_releases` (6 au plus) |
| GET | `/api/v1/releases/queue?limit=` | pour le recommender : artistes d'album à chercher sur MusicBrainz (`artist_id`, `name`, `mbid` connu, `albums`), jamais vérifiés ou vérifiés il y a plus d'une semaine |
| PUT | `/api/v1/artists/{id}/releases` | pour le recommender : `{mbid, releases: [{mbid, title, kind, released}]}` remplace les sorties de l'artiste (`mbid` nul : inconnu de MusicBrainz) |
| GET | `/api/v1/follows` | artistes suivis, c'est-à-dire les artistes likés (`/favorites/artists`) : `{items}` (`id`, `name`, `cover_id`, `new_release` si une sortie de moins de 30 jours ou à venir manque à la biblio), ceux avec une nouvelle sortie d'abord, puis les plus écoutés ; un artiste liké est aussi cherché sur MusicBrainz |
| GET | `/api/v1/discovery?limit=` | à découvrir : `{items}`, artistes proches des artistes likés que la biblio n'a pas (ni par nom ni par MBID), d'après ListenBrainz (`mbid`, `name`, `comment`, `score` : somme des proximités, 1 = le plus proche d'un artiste liké, `because` : les artistes likés dont il est proche) ; aussi dans `/home` sous `discoveries` (8 au plus) |
| GET | `/api/v1/discovery/queue?limit=` | pour le recommender : artistes likés au MBID connu, jamais cherchés sur ListenBrainz ou il y a plus d'une semaine |
| PUT | `/api/v1/artists/{id}/similar` | pour le recommender : `{items: [{mbid, name, comment, score}]}` remplace les artistes proches d'un artiste liké |
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

## Hub en direct (`/api/v1/ws`)

Chaque app garde une WebSocket ouverte (jeton en `Authorization` ou `?token=`). Messages JSON avec un champ `type` :

- **Serveur → app** : `hello` (son `device_id` et les autres appareils en ligne, avec leur état), `presence` (un appareil arrive ou part), `state` (état de lecture d'un autre appareil), `command` (commande reçue d'un autre appareil), `changed` (`library`, `playlists`, `favorites` ou `hidden` : rafraîchir), `error`.
- **App → serveur** : `state` (son propre état de lecture, opaque pour le serveur), `command` (`target`, `action`, `args`).
- **Actions** : `play`, `pause`, `toggle`, `next`, `previous`, `seek {ms}`, `volume {value}`, `jump {index}`, `remove {index}`, `move {from, to}`, `shuffle {on}`, `repeat {mode}`, `load {file d'attente…}`, `transfer {to}` (l'appareil source envoie sa file à `to` puis se met en pause).

Le serveur garde en mémoire le dernier état de chaque appareil connecté et relaie ; rien n'est persisté.

## Paroles

Le serveur cherche, dans l'ordre : `morceau.lrc`, puis `morceau.txt` à côté du fichier audio, puis les paroles intégrées aux tags (`LYRICS`, `UNSYNCEDLYRICS`). Les fichiers LRC (`[mm:ss.xx]texte`, plusieurs horodatages par ligne, `[offset:]`) donnent des paroles synchronisées.
