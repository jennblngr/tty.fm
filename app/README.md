# Client tty.fm (Flutter)

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

### Releases automatiques (GitHub Actions)

Le workflow `.github/workflows/release.yml` construit l'APK Android et l'app macOS pour chaque tag `v*`, puis publie une Release GitHub avec :
- `ttyfm-<version>-arm64-v8a.apk` (et les APK `armeabi-v7a` et `x86_64`) ;
- `ttyfm-<version>-macos.zip`.

Publier une version :

```bash
# 1. mettre à jour `version:` dans app/pubspec.yaml (ex. 1.0.1+10001), committer, pousser
git tag v1.0.1
git push origin v1.0.1
```

Le workflow échoue si `version:` dans `pubspec.yaml` ne correspond pas au tag. Le numéro de build (le `versionCode` Android) est calculé à partir du tag : `1.2.3` donne `10203`. Il augmente donc à chaque version, sinon Android refuserait la mise à jour.

### Android : clé de signature (à faire une fois)

Les APK de la Release sont signés avec une clé dédiée, pas avec la clé de debug du Mac. Android refuse d'installer une mise à jour signée avec une autre clé.

1. Utiliser une clé existante (plusieurs apps peuvent partager la même clé), ou en générer une nouvelle, hors du dépôt, qui ne demande que le mot de passe :
   ```bash
   keytool -genkeypair -v -keystore <dossier>/ttyfm-release.jks -alias ttyfm -keyalg RSA -keysize 4096 -validity 36500 -dname "CN=tty.fm"
   ```
   **En garder une copie de sauvegarde** (gestionnaire de mots de passe, par exemple) : sans ce fichier, on ne peut plus publier de mise à jour installable par-dessus.
2. Ajouter les secrets du dépôt (GitHub → Settings → Secrets and variables → Actions) :
   - `KEYSTORE_BASE64` : le résultat de `base64 -i <dossier>/<clé>.jks | pbcopy` ;
   - `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.

   Les secrets sont propres à chaque dépôt et ne peuvent pas être relus : il faut les recréer ici à partir du gestionnaire de mots de passe.
3. Pour signer aussi les builds faits sur le Mac avec cette clé, créer `android/key.properties` (ignoré par git) :
   ```properties
   storeFile=<chemin absolu>/<clé>.jks
   storePassword=...
   keyAlias=<alias>
   keyPassword=...
   ```
   Sans ce fichier, `flutter build apk --release` signe avec la clé de debug, comme avant.
4. Sur le téléphone, **désinstaller une fois** l'app signée avec la clé de debug, puis installer l'APK de la Release. Il faudra se reconnecter, et les téléchargements hors ligne seront perdus.

### Android : mises à jour avec Obtainium

[Obtainium](https://github.com/ImranR98/Obtainium) installe les APK des Releases GitHub et prévient des nouvelles versions.

1. Si le dépôt est privé : créer un jeton GitHub *fine-grained* en lecture seule, limité à ce dépôt (permission *Contents: Read-only*), puis le renseigner dans Obtainium → Réglages → GitHub (*Personal Access Token*).
2. Obtainium → Ajouter une app → `https://github.com/jennblngr/tty.fm`.
3. Dans les options de l'app, filtre des APK (*Filter APKs by regular expression*) : `arm64-v8a`.
4. Installer. Obtainium vérifie ensuite les nouvelles Releases tout seul.

### Android : APK de test à la demande (« tty.fm (preview) »)

Pour essayer une branche sur le téléphone sans publier de version, le workflow `.github/workflows/preview.yml` construit un APK quand on le lance à la main : GitHub → Actions → **preview** → *Run workflow*, puis choisir la branche (`main` par défaut). Compter environ 6 minutes.

- L'APK est joint au run comme artefact (`ttyfm-<version>-preview.<n° du run>-arm64-v8a`), gardé 14 jours : le télécharger en bas de la page du run (connecté à GitHub), dézipper, installer.
- L'app s'appelle **tty.fm (preview)** (`fm.tty.app.preview`) : elle s'installe à côté de l'app normale et de l'app de debug du Mac (`fm.tty.app.dev`), avec sa propre session et son propre cache.
- C'est un build `profile` (rapide, comme une release, mais avec les outils de mesure), arm64 seulement. Il est signé avec la clé de release et son numéro de build est celui du run : chaque nouvel APK s'installe par-dessus le précédent sans désinstaller.

Le workflow doit être sur `main` pour apparaître dans l'onglet Actions ; il peut ensuite construire n'importe quelle branche. Un build `profile` fait sur le Mac (`flutter build apk --profile`) est signé avec la clé de `android/key.properties` si elle existe, sinon avec la clé de debug.

### macOS : mise à jour avec `tools/update-mac.sh`

```bash
tools/update-mac.sh
```

Le script récupère la dernière Release, quitte l'app si elle tourne, remplace `/Applications/tty.fm.app`, retire la quarantaine (l'app n'est ni signée ni notarisée par Apple) et affiche la version installée. Il ne fait rien si la version installée est déjà la dernière.

Il utilise `gh` s'il est installé et connecté (`gh auth login`). Sinon, il passe par l'API GitHub avec curl ; si le dépôt est privé, lui donner un jeton en lecture seule : `GITHUB_TOKEN=... tools/update-mac.sh`.

### Builds à la main

#### macOS

```bash
flutter build macos --release
cp -R build/macos/Build/Products/Release/tty.fm.app /Applications/
```

L'app est signée « ad hoc » : elle tourne sur le Mac qui l'a construite. Pour un autre Mac : clic droit → Ouvrir la première fois, ou signature avec un compte développeur Apple.

#### Android

```bash
flutter build apk --release --split-per-abi
# téléphone récent : build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (~27 Mo)
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

On peut aussi copier l'APK sur le téléphone et l'ouvrir, en autorisant l'installation depuis cette source. L'APK est signé avec la clé de `android/key.properties` si le fichier existe, sinon avec la clé de debug. Une fois l'app de la Release installée, un APK signé avec la clé de debug ne s'installe plus par-dessus.

## Tests

```bash
flutter test                         # tests unitaires (PlaybackController avec un faux moteur)
flutter analyze
```

**Test de bout en bout** : il lance la vraie app contre un serveur, se connecte, navigue, lit (média réel), passe au suivant, crée des playlists dans des dossiers, vérifie l'historique côté serveur et enregistre des captures.

```bash
# terminal 1 : serveur de développement avec une petite bibliothèque
tools/demo-library.sh            # génère data/dev-music
cd server && make build && TTYFM_MUSIC_DIR=../data/dev-music TTYFM_DATA_DIR=../data/dev-data \
  TTYFM_ADMIN_PASSWORD=devpass TTYFM_LISTEN=127.0.0.1:4533 ./bin/ttyfm
# terminal 2
cd app && flutter test integration_test -d macos
cd app && flutter test integration_test -d emulator-5554 --dart-define=SERVER=10.0.2.2:4533
```

Le test s'appuie sur la bibliothèque de démo générée par `tools/demo-library.sh`.

## Architecture

```
lib/
  app_info.dart          nom de l'app (titre de travail, centralisé)
  core/                  réglages, session/jeton, choix LAN/distant, client HTTP, cache JSON,
                         connexion en direct au hub (live.dart)
  data/                  modèles + LibraryRepository (cache d'abord, puis serveur)
  playback/
    playback_controller.dart   état de lecture unique : file, aléatoire, répétition, historique
    audio_engine.dart          interface du moteur
    media_kit_engine.dart      implémentation media_kit/libmpv (gapless, préchargement)
    system_audio.dart          pont audio_service (écran de verrouillage, casque, Now Playing)
    play_reporter.dart         envoi groupé des écoutes, persistant hors ligne
  offline/downloads.dart téléchargements hors ligne (albums, playlists, favoris), synchronisés
  state/                 providers Riverpod (lecture, mutations, recherche, appareils distants)
  ui/                    écrans et widgets : uniquement de l'affichage
```

**Principes :**
- **L'UI ne contient pas de logique.** Elle lit des providers et appelle `PlaybackController` ou `PlaylistActions`. Refaire le design, c'est changer `ui/` (et le thème dans `ui/app.dart`).
- **`PlaybackController` est le seul point d'entrée de la lecture.** Les boutons de l'UI, les contrôles système et les boutons du casque y passent tous. Depuis la phase 2 bis, les commandes reçues par WebSocket depuis d'autres appareils appellent les mêmes méthodes.
- **Affichage instantané** : chaque écran affiche d'abord la dernière réponse connue (fichiers JSON dans le dossier support de l'app), puis la met à jour. Les listes complètes (artistes, albums, titres) sont chargées en une fois, ce qui suffit pour environ 5 000 titres.
- **Qualité** : original sur le réseau local, Opus 192 kb/s à distance en Wi-Fi, Opus 128 kb/s sur réseau mobile. Ces valeurs se règlent dans Réglages. Changer de réseau en cours de lecture reconstruit les URL et reprend au même endroit.
- **Historique** : une écoute compte comme passée (skip) si l'utilisateur change de morceau avant la moitié (plafonnée à 4 min). Les écoutes partent par lots ; hors ligne, elles sont conservées et renvoyées plus tard.
- **File d'attente** : elle est sauvegardée et restaurée (en pause, à la même position) au redémarrage de l'app.
- **En direct** (`core/live.dart`, `state/remote.dart`) : une WebSocket vers le serveur. L'app publie son état de lecture, exécute les commandes reçues via `PlaybackController` (mêmes méthodes que les boutons) et rafraîchit bibliothèque, playlists et favoris quand un autre appareil ou un scan les modifie. Le bouton « Appareils » liste les autres appareils : les contrôler, ou transférer la lecture (« Écouter ici », « Envoyer vers… »).
- **Hors ligne** (`offline/downloads.dart`) : ⤓ sur un album, une playlist ou les favoris. Les fichiers vont dans le dossier support de l'app, en Opus 192 kb/s sur téléphone et en original sur ordinateur par défaut (réglable, Wi-Fi uniquement par défaut sur téléphone). La lecture utilise la copie locale si elle existe. Les playlists et favoris téléchargés suivent les modifications faites ailleurs. L'onglet « Hors ligne » fonctionne sans réseau.
- **Paroles** : bouton dans le lecteur plein écran ; les paroles synchronisées suivent la lecture (toucher une ligne y saute).
- **Recherche avancée** : filtres genre, période (décennies) et format, avec ou sans texte.

## État

| | macOS | Android |
|---|---|---|
| Connexion, navigation, recherche, playlists | testé (e2e) | testé (e2e, émulateur) |
| Lecture, suivant, enchaînement automatique, historique | testé (e2e) | testé (e2e, émulateur) |
| Contrôles système (Now Playing / notification, écran de verrouillage) | branché, non vérifié à l'œil | branché, non vérifié à l'œil |
| Boutons du casque Bluetooth | — | branché via audio_service, à vérifier sur le téléphone |
| Synchro en direct, contrôle à distance, transfert | testé (sonde contre le NAS) | testé (e2e, émulateur) |
| Téléchargement hors ligne, lecture locale | — | testé (e2e, émulateur) |
| Paroles, filtres de recherche | — | testé (e2e, émulateur) |
| Lecture en arrière-plan, écran éteint | n/a | service configuré, à vérifier sur le téléphone |

**Windows (plus tard)** : la lecture media_kit fonctionne telle quelle. Il restera à brancher les touches multimédia et SMTC, par exemple avec `smtc_windows`, sur le même `PlaybackController`.
