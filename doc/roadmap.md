# Feuille de route

État au 11 novembre 2026. Ce fichier rassemble trois choses : les phases du projet, les issues GitHub ouvertes et les écarts entre les maquettes (`design/mockups/`, résumées dans `design/HANDOFF.md`) et l'app. Les issues restent la source de vérité pour le détail : ce fichier sert de sommaire. À mettre à jour quand une issue est créée, fermée, ou qu'une phase avance.

## 1. Phases

Les phases 1 et 2 n'ont jamais été décrites dans le dépôt : leur contenu est reconstitué à partir de l'historique git. Seules les phases 2 bis et 3 sont nommées dans le code et les README.

| phase | contenu | état |
|---|---|---|
| 1 | Serveur Go + SQLite (scan, pochettes, recherche FTS5, auth, streaming, API REST v1), déploiement Docker sur le NAS, client Flutter macOS / Android (lecture, file d'attente, cache, réseau local / distant). | fait (31 oct.) |
| 2 | Hub WebSocket (synchro entre appareils, événements `changed`), paroles, filtres de recherche, téléchargements hors-ligne, refonte « terminal » d'après les maquettes, stats d'écoute. | fait (1er nov.) |
| 2 bis | Télécommande : les commandes reçues par WebSocket depuis un autre appareil passent par `PlaybackController` (`app/README.md`). | fait (`4ea4cb1`). Reste le bandeau « lecture sur… » du design : #17 |
| 3 | Service `recommender/` (Python + Essentia) : analyse audio, titres similaires et radio infinie (embeddings, vecteurs dans `sqlite-vec`), mix quotidiens tirés de l'historique, découverte via MusicBrainz / ListenBrainz. Voir `recommender/README.md`. | fait (9 nov., PR 49 à 61). Analyse audio (bpm, tonalité + Camelot, LUFS, énergie, dansant ; genre et sous-genre en %, ambiance et acoustique avec les modèles TensorFlow d'Essentia), table `track_analysis`, API `/analysis`, affichage dans l'app ; similarité entre titres (embedding EffNet moyen envoyé avec l'analyse, table `sqlite-vec` `track_embeddings`, `GET /tracks/{id}/similar`) ; radio (`GET /radio` depuis un titre ou un artiste, avec dérive, diversité et repli sans embedding ; dans l'app : « lancer la radio », lecture auto, file marquée). Mix du jour, nouvelles sorties (MusicBrainz), artistes suivis, découverte (ListenBrainz) et radios d'artistes à l'accueil. Les suites sont rangées dans d'autres issues : notifications « nouvelles sorties » et « mix prêts » (#12), variantes du message du jour (#13), filtres `bpm:` / `ton:` de la biblio (#24), tuile radar (#14, en attente du design) |

Ce que la phase 3 a apporté à l'app, et ce qui en reste :

- **Analyse audio** : fait dans le lecteur (bloc `$ analyse --piste`, enchaînement compatible), les listes de titres (bpm en pêche), la file d'attente desktop, le menu `···` des titres et le menu `[···]` du lecteur (« relancer l'analyse »). Genre et sous-genre, ambiance et acoustique : calculés par le recommender et affichés dans le lecteur (sans les %), avec les chips de genre sous le titre et le lien `[détails]` (confiance de la tonalité, dynamique, analyseur et date ; acoustique sur téléphone). Les filtres `bpm:` / `ton:` existent dans la recherche (#18) : préfixes `bpm:>120`, `bpm:90-120`, `bpm:118`, `ton:8A`, `ton:am`, et puces `bpm` (tranches `<90 · 90–120 · 120–140 · >140`) et `ton`. Restent ceux de la biblio et des playlists (#24). Faits aussi : le tempo des stats (#20) et, dans les réglages, l'interrupteur « analyse audio » (pour tout le serveur, `PATCH /analysis`), l'état de l'analyse et « réinitialiser l'analyse audio » (#25).
- **Recommandations** : l'API des titres similaires (`GET /tracks/{id}/similar`, remplie au fil de la réanalyse `discogs-effnet-2`) et celle de la radio (`GET /radio`) existent, et l'app s'en sert : « lancer la radio » dans le menu `[···]` du lecteur et le menu `···` des titres (depuis le titre en cours : remplace la suite de la file et lance le premier titre de la radio, avec confirmation s'il reste des ajouts manuels), lecture auto en fin de file quand la répétition est off (réglage `lecture auto`, on par défaut), titres marqués « · radio » / « · ajouté par toi » dans la file et ligne `// ensuite : radio « … »`, nouveau lot quand il reste moins de 3 titres. Les mix du jour sont faits (calcul de nuit sur le serveur, tuiles à l'accueil). Les radios d'artistes à l'accueil sont faites. Restent la notification « mix prêts » (#12) et les variantes mix du message du jour (#13), qui peuvent se brancher sur `daily_mixes`. Le radar attend le design (#14).
- **Suivi des sorties** : nouvelles sorties à l'accueil faites (#14) : le recommender cherche chaque artiste d'album sur MusicBrainz (au plus une fois par semaine, une requête par seconde), le serveur compare les sorties à la bibliothèque (`GET /releases`) et l'accueil affiche « ● nouvelles sorties », `[✓]` quand l'album est dans la biblio. Lien `[tout]` fait (liste complète des 90 derniers jours et des sorties à venir) ; `[+]` ouvre la sortie sur MusicBrainz. Reste la notification « nouvelles sorties » (#12). Découverte ListenBrainz : faite (« ◇ à découvrir // hors de ta biblio » à l'accueil : les artistes proches des artistes likés que la biblio n'a pas, « // proche de sia, adele · barbadian r&b/pop singer » ; rien à lire ici, une liste à chercher ailleurs ; un appui ouvre la page de l'artiste sur ListenBrainz). Artistes suivis : faits. Suivre un artiste, c'est le liker (♥ sur sa fiche) : un seul geste, puisque les maquettes n'ont pas de « like » d'artiste et que la page artiste n'est pas dessinée. Biblio « ● artistes suivis [N] ▾ » : puces avec « • » rouge pour une sortie de moins de 30 jours ou à venir absente de la biblio, quatre puces et « +N » repliées, « // ♥ un artiste pour suivre ses sorties » quand il n'y en a aucun (`GET /follows`). Pas de suivi d'office des plus écoutés : la décision est laissée à l'utilisatrice.
- **Message du jour** : les variantes qui dépendent de ces données (#13).

## 2. Issues ouvertes

### Bugs

| # | sujet |
|---|---|
| #4 | Coupure audio d'environ 1 s lors d'un changement de Wi-Fi |
| #27 | « Précédent » reprend la piste à un ancien point au lieu du début |

### Fonctionnalités et alignement sur le design

| # | sujet | dépend de la phase 3 |
|---|---|---|
| #3 | Menu contextuel au clic droit / appui long | non |
| #6 | Mobile : fermer le lecteur en glissant vers le bas | non |
| #12 | Écran des notifications et cloche | non. Livré par la PR #35 (type « titres ajoutés ») ; les autres types (scan terminé, sorties, mix prêts…) restent à faire. Fermer l'issue ou la réduire à ces types. |
| #13 | Message du jour : 15 variantes, P1 → P4 | en partie. Livré par les PR #30 et #33 ; restent les variantes analyse, mix, sorties et rétro |
| #14 | Accueil : tuile radar et panneau « à suivre » (desktop), en attente du design ; le reste est livré (PR 55, 56, 60, 61) | non |
| #15 | Menu `[···]` du lecteur, archiver, retirer de la bibliothèque | en partie |
| #16 | Menu de tri des listes, mémorisé par liste | non |
| #17 | Multi-appareils : bandeau « lecture sur… [écouter ici] » | non |
| #18 | Recherche : préfixes (`bpm:>120`, `paroles:`…), raccourcis, surlignage | en partie |
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
- Mix du jour : faits (`✦ tes mix du jour // générés selon tes écoutes`, tuiles 140 px `mix_01`… défilant de côté, `// dance-pop · calme · sia, tove lo…` dessous, un appui lance le mix). Calcul côté serveur chaque nuit (`daily_mixes`, `GET /mixes`). Pas encore : une page pour voir un mix avant de le lancer. Tuile `radar` (« // 30 découvertes, chaque lundi ») : laissée de côté le 9 nov., aucun document ne dit ce qu'elle contient (les découvertes ListenBrainz ne sont pas dans la biblio, donc rien à lire) ; question à poser au design → #14.
- Nouvelles sorties : faites (4 au plus, vignette générée faute de pochette, `[✓]` vert quand la biblio a l'album ; un appui ouvre l'album, sinon l'artiste). `[tout]` ouvre la liste complète (`ls ~/sorties`, `GET /releases`), aussi en desktop où la maquette montre un compteur `[2]`. `[+]` sur une sortie absente de la biblio ouvre sa page MusicBrainz (décidé le 9 nov. ; `url_launcher`).
- Radios d'artistes : faites (`◉ radios d'artistes`, pochettes rondes de 104 px défilant de côté, nom dessous ; un appui lance la radio de l'artiste). Les artistes likés d'abord, puis les plus écoutés des 28 derniers jours, 8 au plus (`artist_radios` dans `GET /home`).
- Panneau « à suivre » de D1 : case carrée 24 px ou non, décision ouverte (HANDOFF §8), pas prioritaire (le desktop passe après le mobile) → #14.

### Lecteur (02, 02b, D2)

- En-tête centré, `[agrandir]` / `[réduire]` dans la barre du bas → #23. Lecture auto : fait.
- Menu `[···]` : fait (02b, D2), avec aller à l'album / à l'artiste (⌥A / ⌥R), lire sur…, relancer l'analyse, archiver et lancer la radio. Manquent égaliseur, infos du fichier, modifier les tags et retirer de la bibliothèque → #15.
- Bloc `$ analyse --piste` : fait, avec genre et sous-genre (sans les % de la maquette : ce sont des parts de la somme des activations des 400 styles, qui se lisent à tort comme une confiance), ambiance et acoustique (modèles ML) et le lien `[détails]`. La maquette ne dit pas ce qu'il ouvre : il déplie la confiance de la tonalité, la dynamique (LU), l'analyseur et sa date, et sur téléphone l'acoustique, absente de 02 mais présente dans D2. Chips de genre sous le titre : faites. D'abord le genre du tag du fichier (mauve), puis le style entendu par l'analyse (rose, ex. « dance-pop »), puis le bpm ; sans tag, le genre et le style calculés. Le mini-graphe ne fait que décorer. Choix fait après comparaison sur la bibliothèque : le genre du modèle diffère souvent du tag sans être faux (Discogs range la pop sous des styles électro ou rock), et aucune autre façon d'agréger les 400 styles ne fait mieux partout. L'ambiance vient de cinq classifieurs (joyeux, mélancolique, calme, agressif, festif) : « nocturne » de la maquette n'existe pas parmi les modèles d'Essentia.
- Fermer en glissant vers le bas → #6.
- **Sans issue** : le panneau `⚙ son` du lecteur propose un minuteur de veille et le choix de la qualité (`now_playing.dart`). Le design les exclut (HANDOFF §5 : « pas de minuteur de veille », « pas de réglage de qualité dans le lecteur »). Retirer, ou garder et mettre à jour le design.

### Bibliothèque et playlists (03, 03b, D3, D3b)

- En-tête de playlist, filtres défilants, tableau desktop, pages album / artiste → #24.
- Tri → #16. Vignettes → #22.
- **Sans issue** (vue d'ensemble 03 / D3) :
  - rangées de filtres `type:` (tout, playlists, albums, artistes, titres) et `bpm:` sur la vue d'ensemble ; l'app bascule les vues avec des liens `[…]`. Le bpm de chaque titre existe depuis l'analyse audio : reste le filtre lui-même ;
  - jauge « stockage hors-ligne `1.1 / 4 Go` » en bas de page ;
  - écran `bibliothèque › [archivés]`, pas encore dessiné (HANDOFF §8) → #15.
  - « archiver » existe (menus `···` des titres et `[···]` du lecteur, toast « annuler » 5 s), mais pas au sens de la spec : le titre reste visible, grisé et barré, dans son album, ses playlists et la recherche, et n'est simplement plus jamais mis en file (table `hidden_tracks`, `GET/PUT/DELETE /hidden`). Le réglage « masquer les titres archivés » (`[off] [on]`, local à l'appareil) les retire des albums et retire de la biblio et des fiches artiste les albums entièrement archivés ; ils restent dans `titres`, les playlists, l'accueil et la recherche. La spec le retire de la biblio, des recos et de la recherche. À accorder avec #15.

### Recherche (04, 04b, D4, D4b)

- Préfixes `bpm:` et `ton:` : faits, avec les puces `bpm` (tranches) et `ton` dans la rangée de filtres. Restent les autres préfixes (`paroles:`, `artiste:`, `album:`, `genre:`, `ajouté:`), les raccourcis sous le champ, le surlignage et l'état « aucun résultat » → #18.
- **Sans issue** : historique des recherches (`↺ historique [effacer]`, avec le nombre de résultats et le type de chaque entrée) sur l'écran vide. L'app affiche seulement « parcourir ».
- Retour arrière depuis une recherche filtrée : fait (#2). Le premier retour vide la requête et les filtres, le suivant ramène à l'accueil.

### Stats (05, D5)

- Tempo : fait (`∿ tempo`, tranches `< 80 · 80–100 · 100–120 · 120–140 · > 140` en part du temps d'écoute des titres analysés, bpm moyen et écart avec la période précédente, le + rapide / le + lent, matin 5–12 h contre soir 18–24 h).
- Graphe d'activité, heures par mois, rétro annuelle → #20.
- **Sans issue** : « série actuelle : 9 j · record : 23 j » sous le graphe d'activité. Le serveur calcule déjà la série pour le message du jour (`moments.streak`, PR #33) ; on pourrait l'ajouter à #20.

### Réglages (06, D6)

- Sections et mise en page terminal → #25. Thèmes : fait (#11, fermée).
- Éléments des maquettes à ne pas oublier dans #25 : liste des dossiers de musique avec `[+ ajouter un dossier]`, scan automatique, volume égalisé, notifications par type (analyse terminée, mix prêts, nouvelles sorties, stats & rétro), « exporter les stats (.csv) », « vider le cache ». Faits : l'interrupteur « analyse audio » avec l'état de l'analyse sous lui (`// 340 / 345 titres analysés · 3 en cours`), et « réinitialiser l'analyse audio » (avec confirmation), encore en `ListTile` en attendant la mise en page terminal.

### Notifications (07, D7)

- Fait (PR #35). Les autres types de notifications → #12.

### Transverse

- Animations → #21. Clic droit / appui long → #3. Bandeau multi-appareils → #17.
- CI : le job `docker` construit les images du serveur et du recommender à chaque PR, démarre le serveur sur une biblio vide jusqu'à son healthcheck et vérifie que le recommender importe Essentia (casse de la PR 49). Fait.
- Boutons-icônes carrés 40×40 / 36×36, icônes pleines → #23 (le widget `SquareIconButton` existe ; l'appliquer partout).

## 4. Questions ouvertes du design

Reprises de `design/HANDOFF.md` §8 :

- État « aucun résultat » de la recherche (#18).
- Case carrée 24 px dans le panneau « à suivre » de D1 (#14).
- Pages album et artiste (#24).
- Écran `bibliothèque › [archivés]` (#15).
- Import d'un thème perso (VS Code `.json` / base16) : évoqué, non décidé, sans issue.
