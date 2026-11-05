# Feuille de route

État au 3 novembre 2026. Ce fichier rassemble trois choses : les phases du projet, les issues GitHub ouvertes et les écarts entre les maquettes (`design/mockups/`, résumées dans `design/HANDOFF.md`) et l'app. Les issues restent la source de vérité pour le détail : ce fichier sert de sommaire. À mettre à jour quand une issue est créée, fermée, ou qu'une phase avance.

## 1. Phases

Les phases 1 et 2 n'ont jamais été décrites dans le dépôt : leur contenu est reconstitué à partir de l'historique git. Seules les phases 2 bis et 3 sont nommées dans le code et les README.

| phase | contenu | état |
|---|---|---|
| 1 | Serveur Go + SQLite (scan, pochettes, recherche FTS5, auth, streaming, API REST v1), déploiement Docker sur le NAS, client Flutter macOS / Android (lecture, file d'attente, cache, réseau local / distant). | fait (31 oct.) |
| 2 | Hub WebSocket (synchro entre appareils, événements `changed`), paroles, filtres de recherche, téléchargements hors-ligne, refonte « terminal » d'après les maquettes, stats d'écoute. | fait (1er nov.) |
| 2 bis | Télécommande : les commandes reçues par WebSocket depuis un autre appareil passent par `PlaybackController` (`app/README.md`). | fait (`4ea4cb1`). Reste le bandeau « lecture sur… » du design : #17 |
| 3 | Service `recommender/` (Python + Essentia) : analyse audio, titres similaires et radio infinie (embeddings, vecteurs dans `sqlite-vec`), mix quotidiens tirés de l'historique, découverte via MusicBrainz / ListenBrainz. Voir `recommender/README.md`. | en cours. Fait : analyse audio classique (bpm, tonalité + Camelot, LUFS, énergie, dansant), table `track_analysis`, API `/analysis`, affichage dans l'app. Reste : genres / ambiance / acoustique (modèles TensorFlow d'Essentia), similarité, mix, découverte |

Ce qui attend la phase 3 dans l'app (commentaires « phase 3 » dans `home.dart`, `now_playing.dart`, `shell.dart`, `stats.dart`) :

- **Analyse audio** : fait dans le lecteur (bloc `$ analyse --piste`, enchaînement compatible), les listes de titres (bpm en pêche), la file d'attente desktop et le menu `···` des titres (« relancer l'analyse »). Restent : genres en %, ambiance et acoustique (#19), les filtres `bpm:` / `ton:` de la recherche (#18) et de la biblio (#24), le tempo des stats (#20), « relancer l'analyse » dans le menu `[···]` du lecteur (#15), « réinitialiser l'analyse audio » et l'état de l'analyse dans les réglages (#25 ; l'API existe : `GET/DELETE /analysis`).
- **Recommandations** : mix du jour, radar, radios d'artistes (#14), lecture auto en fin de file (#23), « lancer la radio » dans le menu `[···]` (#15).
- **Suivi des sorties** : nouvelles sorties à l'accueil (#14), artistes suivis dans la biblio (§3).
- **Message du jour** : les variantes qui dépendent de ces données (#13).

## 2. Issues ouvertes

### Bugs

| # | sujet |
|---|---|
| #1 | Activer / désactiver « aléatoire » coupe brièvement la lecture |
| #2 | Mobile : le retour depuis une recherche filtrée quitte l'onglet au lieu de revenir à son état initial |
| #4 | Coupure audio d'environ 1 s lors d'un changement de Wi-Fi |
| #27 | « Précédent » reprend la piste à un ancien point au lieu du début |

### Fonctionnalités et alignement sur le design

| # | sujet | dépend de la phase 3 |
|---|---|---|
| #3 | Menu contextuel au clic droit / appui long | non |
| #6 | Mobile : fermer le lecteur en glissant vers le bas | non |
| #12 | Écran des notifications et cloche | non. Livré par la PR #35 (type « titres ajoutés ») ; les autres types (scan terminé, sorties, mix prêts…) restent à faire. Fermer l'issue ou la réduire à ces types. |
| #13 | Message du jour : 15 variantes, P1 → P4 | en partie. Livré par les PR #30 et #33 ; restent les variantes analyse, mix, sorties et rétro |
| #14 | Accueil : mix du jour, nouvelles sorties, radios d'artistes | oui |
| #15 | Menu `[···]` du lecteur, archiver, retirer de la bibliothèque | en partie |
| #16 | Menu de tri des listes, mémorisé par liste | non |
| #17 | Multi-appareils : bandeau « lecture sur… [écouter ici] » | non |
| #18 | Recherche : préfixes (`bpm:>120`, `paroles:`…), raccourcis, surlignage | en partie |
| #19 | Analyse audio et bloc `$ analyse --piste` | oui. Livré : bpm, tonalité, énergie, dansant, LUFS, enchaînement compatible, bpm dans les listes ; restent genres / sous-genres en %, ambiance, acoustique (modèles ML) |
| #20 | Stats : graphe d'activité, heures par mois, tempo, rétro | en partie |
| #21 | Animations : onglets, défilement, panneau du bas, paroles | non |
| #22 | Vignettes de playlist : 1 ou 4 pochettes, ou image perso | non |
| #23 | Lecteur : en-tête centré, `[agrandir]` fixe, lecture auto | en partie |
| #24 | Bibliothèque et playlists : en-tête, filtres, tableau desktop | en partie |
| #25 | Réglages : sections et mise en page du design | en partie |

## 3. Écarts entre les maquettes et l'app

Par écran. « → #n » renvoie à l'issue qui couvre l'écart ; les lignes **sans issue** sont à trancher : créer une issue, ou décider de garder le comportement actuel et mettre à jour le design.

### Accueil (01, D1)

- Fait : en-tête `tty.fm $ accueil` avec cloche et engrenage, message du jour, écouté récemment (albums, artistes, playlists), ajouts récents par lot, deux colonnes et champ de recherche en desktop.
- Manque : mix du jour, nouvelles sorties, radios d'artistes → #14.
- Panneau « à suivre » de D1 : case carrée 24 px ou non, décision ouverte (HANDOFF §8) → #14.

### Lecteur (02, 02b, D2)

- En-tête centré, `[agrandir]` / `[réduire]` dans la barre du bas, lecture auto → #23.
- Menu `[···]` selon le design → #15.
- Bloc `$ analyse --piste` : fait, sauf genres en %, ambiance et acoustique (modèles ML) et le lien `[détails]` → #19. Chips de genre → #19.
- Fermer en glissant vers le bas → #6.
- **Sans issue** : le panneau `⚙ son` du lecteur propose un minuteur de veille et le choix de la qualité (`now_playing.dart`). Le design les exclut (HANDOFF §5 : « pas de minuteur de veille », « pas de réglage de qualité dans le lecteur »). Retirer, ou garder et mettre à jour le design.

### Bibliothèque et playlists (03, 03b, D3, D3b)

- En-tête de playlist, filtres défilants, tableau desktop, pages album / artiste → #24.
- Tri → #16. Vignettes → #22.
- **Sans issue** (vue d'ensemble 03 / D3) :
  - rangées de filtres `type:` (tout, playlists, albums, artistes, titres) et `bpm:` sur la vue d'ensemble ; l'app bascule les vues avec des liens `[…]`. Le filtre `bpm:` dépend de la phase 3 ;
  - section « artistes suivis » avec le point « nouvelle sortie » (dépend du suivi des sorties) ;
  - jauge « stockage hors-ligne `1.1 / 4 Go` » en bas de page ;
  - écran `bibliothèque › [archivés]`, pas encore dessiné (HANDOFF §8) → #15.

### Recherche (04, 04b, D4, D4b)

- Préfixes, raccourcis, surlignage, état « aucun résultat » → #18.
- **Sans issue** : historique des recherches (`↺ historique [effacer]`, avec le nombre de résultats et le type de chaque entrée) sur l'écran vide. L'app affiche seulement « parcourir ».
- Retour arrière depuis une recherche filtrée → #2.

### Stats (05, D5)

- Graphe d'activité, heures par mois, tempo, rétro annuelle → #20.
- **Sans issue** : « série actuelle : 9 j · record : 23 j » sous le graphe d'activité. Le serveur calcule déjà la série pour le message du jour (`moments.streak`, PR #33) ; on pourrait l'ajouter à #20.

### Réglages (06, D6)

- Sections et mise en page terminal → #25. Thèmes : fait (#11, fermée).
- Éléments des maquettes à ne pas oublier dans #25 : liste des dossiers de musique avec `[+ ajouter un dossier]`, scan automatique, interrupteur « analyse audio » (phase 3), volume égalisé, notifications par type (analyse terminée, mix prêts, nouvelles sorties, stats & rétro), « exporter les stats (.csv) », « vider le cache », « réinitialiser l'analyse audio ».

### Notifications (07, D7)

- Fait (PR #35). Les autres types de notifications → #12.

### Transverse

- Animations → #21. Clic droit / appui long → #3. Bandeau multi-appareils → #17.
- Boutons-icônes carrés 40×40 / 36×36, icônes pleines → #23 (le widget `SquareIconButton` existe ; l'appliquer partout).

## 4. Questions ouvertes du design

Reprises de `design/HANDOFF.md` §8 :

- État « aucun résultat » de la recherche (#18).
- Case carrée 24 px dans le panneau « à suivre » de D1 (#14).
- Pages album et artiste (#24).
- Écran `bibliothèque › [archivés]` (#15).
- Import d'un thème perso (VS Code `.json` / base16) : évoqué, non décidé, sans issue.
