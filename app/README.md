# Client selfstream (Flutter)

Application native pour **macOS** et **Android**. Windows et iOS sont prévus pour plus tard : le code est commun, seules les intégrations système restent à brancher.

## Prérequis (Mac)

- Flutter (stable) : `brew install --cask flutter`
- **macOS** : Xcode + CocoaPods (`brew install cocoapods`)
- **Android** : SDK Android (via Android Studio, ou `~/Library/Android/sdk`) et un JDK 17 ou plus. Pour indiquer le JDK à Flutter :
  ```bash
  brew install openjdk@21
  flutter config --jdk-dir /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
  ```

## Lancer en développement

```bash
cd app
flutter pub get
flutter run -d macos              # ou : flutter run -d <id Android> (voir flutter devices)
```

Au premier lancement, renseigner :
- **Adresse du serveur** : l'adresse Tailscale du NAS, par exemple `nas.<tailnet>.ts.net:4533`. Elle sert partout.
- **Adresse locale** (optionnelle) : par exemple `192.168.1.20:4533`. Si elle répond (sondage d'environ 600 ms sur Wi-Fi ou Ethernet), l'app l'utilise en priorité et lit les fichiers originaux.

Depuis un émulateur Android, le Mac s'appelle `10.0.2.2`.

**Hot reload** : dans le terminal de `flutter run`, `r` recharge l'interface en moins d'une seconde sans perdre l'état (la lecture continue). On peut aussi le déclencher de l'extérieur : `flutter run -d macos --pid-file /tmp/flutter.pid`, puis `kill -USR1 $(cat /tmp/flutter.pid)`. **Éviter le hot restart (`R`)** : media_kit/mpv plante quand le lecteur est détruit en plein chargement. Pour un changement dans `main()` ou dans un provider initialisé au démarrage, relancer `flutter run` (environ 15 s). Le mode debug partage la session et le cache avec l'app installée.

## Builds

### macOS

```bash
flutter build macos --release
cp -R build/macos/Build/Products/Release/selfstream.app /Applications/
```

L'app est signée « ad hoc » : elle tourne sur le Mac qui l'a construite. Pour un autre Mac : clic droit → Ouvrir la première fois, ou signature avec un compte développeur Apple.

### Android

```bash
flutter build apk --release --split-per-abi
# téléphone récent : build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (~27 Mo)
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

On peut aussi copier l'APK sur le téléphone et l'ouvrir, en autorisant l'installation depuis cette source. L'APK est signé avec la clé de debug : suffisant pour un usage personnel. Une clé dédiée (`key.properties`) ne sera utile que pour une distribution.

## Tests

```bash
flutter test                         # tests unitaires (PlaybackController avec un faux moteur)
flutter analyze
```

**Test de bout en bout** : il lance la vraie app contre un serveur, se connecte, navigue, lit (média réel), passe au suivant, crée des playlists dans des dossiers, vérifie l'historique côté serveur et enregistre des captures.

```bash
# terminal 1 : serveur de développement avec une petite bibliothèque
tools/demo-library.sh            # génère data/dev-music
cd server && make build && SELFSTREAM_MUSIC_DIR=../data/dev-music SELFSTREAM_DATA_DIR=../data/dev-data \
  SELFSTREAM_ADMIN_PASSWORD=devpass SELFSTREAM_LISTEN=127.0.0.1:4533 ./bin/selfstream
# terminal 2
cd app && flutter test integration_test -d macos
cd app && flutter test integration_test -d emulator-5554 --dart-define=SERVER=10.0.2.2:4533
```

Le test s'appuie sur la bibliothèque de démo générée par `tools/demo-library.sh`.

## Architecture

```
lib/
  app_info.dart          nom de l'app (titre de travail, centralisé)
  core/                  réglages, session/jeton, choix LAN/distant, client HTTP, cache JSON
  data/                  modèles + LibraryRepository (cache d'abord, puis serveur)
  playback/
    playback_controller.dart   état de lecture unique : file, aléatoire, répétition, historique
    audio_engine.dart          interface du moteur
    media_kit_engine.dart      implémentation media_kit/libmpv (gapless, préchargement)
    system_audio.dart          pont audio_service (écran de verrouillage, casque, Now Playing)
    play_reporter.dart         envoi groupé des écoutes, persistant hors ligne
  state/                 providers Riverpod (lecture et mutations)
  ui/                    écrans et widgets : uniquement de l'affichage
```

**Principes :**
- **L'UI ne contient pas de logique.** Elle lit des providers et appelle `PlaybackController` ou `PlaylistActions`. Refaire le design, c'est changer `ui/` (et le thème dans `ui/app.dart`).
- **`PlaybackController` est le seul point d'entrée de la lecture.** Les boutons de l'UI, les contrôles système et les boutons du casque y passent tous. En phase 2 bis, les commandes reçues par WebSocket depuis d'autres appareils appelleront les mêmes méthodes.
- **Affichage instantané** : chaque écran affiche d'abord la dernière réponse connue (fichiers JSON dans le dossier support de l'app), puis la met à jour. Les listes complètes (artistes, albums, titres) sont chargées en une fois, ce qui suffit pour environ 5 000 titres.
- **Qualité** : original sur le réseau local, Opus 192 kb/s à distance en Wi-Fi, Opus 128 kb/s sur réseau mobile. Ces valeurs se règlent dans Réglages. Changer de réseau en cours de lecture reconstruit les URL et reprend au même endroit.
- **Historique** : une écoute compte comme passée (skip) si l'utilisateur change de morceau avant la moitié (plafonnée à 4 min). Les écoutes partent par lots ; hors ligne, elles sont conservées et renvoyées plus tard.
- **File d'attente** : elle est sauvegardée et restaurée (en pause, à la même position) au redémarrage de l'app.

## État

| | macOS | Android |
|---|---|---|
| Connexion, navigation, recherche, playlists | testé (e2e) | testé (e2e, émulateur) |
| Lecture, suivant, enchaînement automatique, historique | testé (e2e) | testé (e2e, émulateur) |
| Contrôles système (Now Playing / notification, écran de verrouillage) | branché, non vérifié à l'œil | branché, non vérifié à l'œil |
| Boutons du casque Bluetooth | — | branché via audio_service, à vérifier sur le téléphone |
| Lecture en arrière-plan, écran éteint | n/a | service configuré, à vérifier sur le téléphone |

**Windows (plus tard)** : la lecture media_kit fonctionne telle quelle. Il restera à brancher les touches multimédia et SMTC, par exemple avec `smtc_windows`, sur le même `PlaybackController`.
