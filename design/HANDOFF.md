# tty.fm — handoff design

Ce dossier contient tout le design de l'app, exporté depuis le canvas de maquettes. Commence ici : ce fichier résume les écrans, les tokens, les règles et les décisions prises. Les maquettes (`mockups/`) font foi en cas de doute sur un détail visuel.

> Contexte technique : client **Flutter** (`app/`), serveur **Go** (`server/`). Les pages spec contiennent parfois des extraits CSS/React : ce sont des **références de comportement**, à traduire en widgets Flutter (voir « Correspondances Flutter » plus bas).

---

## 1. Contenu du dossier

```
design/
  HANDOFF.md            ← ce fichier
  mockups/              ← une maquette par écran (.dc.html) + canvas.json (index du canvas)
  covers/               ← pochettes fictives (SVG) utilisées dans les maquettes
```

Les `.dc.html` sont du HTML avec styles inline + un petit bloc `class Component extends DCLogic { renderVals() {…} }` qui fournit les données et l'état (les `{{trous}}` du template). `<sc-for list="{{x}}" as="i">` = boucle, `<sc-if value="{{x}}">` = condition. Le runtime de l'outil de design (`support.js`) n'est pas inclus : les fichiers se **lisent** très bien, mais ne s'ouvrent pas tels quels dans un navigateur avec leur interactivité.

Les deux fichiers `tty.fm — app de streaming musical*.html` déjà présents dans `design/` sont d'anciens exports figés : se fier à `mockups/`.

---

## 2. Écrans

Largeurs de référence : mobile **390 px**, desktop **1440 px**.

### Mobile

| id | écran | fichier |
|---|---|---|
| 01 | accueil | `Main.dc.html` |
| 02 | lecteur plein écran | `Lecteur.dc.html` |
| 02b | lecteur, menu [···] ouvert (panneau du bas) | `Lecteur-Menu.dc.html` |
| 03 | bibliothèque (vue d'ensemble) | `Bibliotheque.dc.html` |
| 03b | playlist « titres likés » | `Playlist.dc.html` |
| 04 | recherche (vide : historique + parcourir) | `Recherche.dc.html` |
| 04b | résultats de recherche (« nova ») | `Recherche-Resultats.dc.html` |
| 05 | stats | `Profil.dc.html` |
| 06 | réglages | `Reglages.dc.html` |
| 07 | notifications | `Notifications.dc.html` |

### Desktop

| id | écran | fichier |
|---|---|---|
| D1 | accueil | `Desktop-Accueil.dc.html` |
| D2 | lecteur (avec menu [···] déroulant ouvert par défaut) | `Desktop-Lecteur.dc.html` |
| D3 | bibliothèque (vue d'ensemble) | `Desktop-Biblio.dc.html` |
| D3b | playlist « titres likés » (tableau + filtre bpm) | `Desktop-Bibliotheque.dc.html` |
| D4 | recherche (vide) | `Desktop-Recherche.dc.html` |
| D4b | résultats de recherche | `Desktop-Recherche-Resultats.dc.html` |
| D5 | stats | `Desktop-Stats.dc.html` |
| D6 | réglages | `Desktop-Reglages.dc.html` |
| D7 | notifications | `Desktop-Notifications.dc.html` |

### Pages spec (règles détaillées, à lire avant d'implémenter la fonctionnalité concernée)

| spec | fichier |
|---|---|
| en-tête de l'accueil : 15 variantes de message, priorités P1→P4 | `Entete-Variantes.dc.html` |
| vignettes de playlist (1 ou 4 pochettes, image perso) | `Vignettes-Playlists.dc.html` |
| lecture multi-appareils (un seul appareil joue, télécommande, icônes) | `Multi-Appareils.dc.html` |
| mini-graphes SVG (style musical, jauges, volume, eq) | `Mini-Graphes.dc.html` |
| menus contextuels (01 : [···] du lecteur, 02 : tri) | `Menus-Contextuels.dc.html` |
| animation 01-02 : menu de navigation (barre + couleur qui balaie le texte) | `Animations.dc.html` |
| animation 03 : défilement artiste + album trop longs | `Animation-Defilement.dc.html` |
| animation 04 : ouverture du panneau du bas | `Animation-Panneau.dc.html` |
| animation 05 : défilement des paroles synchronisées | `Animation-Paroles.dc.html` |

---

## 3. Tokens

### Couleurs (thème par défaut : Catppuccin Mocha)

| rôle | hex |
|---|---|
| fond | `#1E1E2E` |
| fond secondaire (barres latérales, panneaux desktop) | `#1A1A28` / `#181825` |
| surface (cartes, mini-lecteur, chips) | `#2A2A3C` |
| surface carte spec | `#232334` |
| ligne / séparateur | `#34344A` |
| case vide (jauges, graphes) | `#45475A` |
| texte | `#E2E2EE` |
| texte grisé / commentaires `//` | `#9091AB` |
| texte éteint (lignes passées, compteurs) | `#6C6C8A` |
| vert (actif, action principale) | `#A6E3A1` |
| violet (titres de section, `$`) | `#CBA6F7` |
| pêche (bpm, tempo) | `#FAB387` |
| bleu (titre en cours, liens titres) | `#89B4FA` |
| turquoise | `#94E2D5` |
| rose | `#F5A3C7` |
| jaune (surlignage de recherche) | `#F9E2AF` |
| rouge (like, actions destructives) | `#F38BA8` |

Fonds teintés utilisés pour les tuiles/badges : `#3D2633` (rose), `#3D2E26` (pêche), `#2E2840` (violet), `#263A34` (turquoise), `#3A3526` (jaune), `#23324A` (bleu), `#26332B` (vert, aussi le bandeau « lecture sur… »).

Les couleurs d'accent viennent du **thème** : l'utilisateur ne choisit plus de couleur d'accent séparément (voir §5 Thèmes).

### Typographie

- **JetBrains Mono** partout (400 / 500 / 700). Taille de base 13 px, interligne 1.5.
- Titres d'écran 15 px (desktop) / titres de lecteur 18–22 px.
- Style « terminal » : `$` devant les commandes et titres, `//` pour les commentaires/sous-titres, `[crochets]` pour les boutons texte, `>` pour l'élément actif.

### Espacements

Échelle unique : **2 · 4 · 8 · 12 · 16 · 24 · 32 · 48 · 64**. Arrondir à la valeur la plus proche (égalité → au-dessus). Rayons : 6 (pochettes, boutons, tuiles), 8 (cartes, grandes pochettes), 16 (panneau du bas). Les maquettes mettent encore 4 aux petites pochettes : c'est 6 qui fait foi.

### Icônes

Icônes **pleines** (pas en contour), sauf aléatoire / répéter qui sont des traits épais (2.4). Les boutons-icônes ont un conteneur **carré** (40×40 sur mobile, 36×36 sur desktop).

---

## 4. Règles transverses

1. **Mini-graphes** : jamais les caractères `▁▂▃▄▅▆▇█░` (la police de secours les décale). Toujours dessinés : barres de 7 unités + 1 d'espace, hauteur en huitièmes, largeur 0.6em par barre, hauteur 0.75em, couleur du texte. Jauges = cases pleines (couleur) + vides (`#45475A`). Détails : `Mini-Graphes.dc.html`.
2. **Listes de titres** (file d'attente, playlist, résultats, tableau) : une case carrée de 24 px à gauche contient soit le numéro (gris), soit l'icône play 18 px (vert) pour le titre en cours → aucun décalage horizontal. Puis pochette 40 px, titre / `// artiste · album`, bpm en pêche.
3. **Mini-lecteur mobile** (bas de l'accueil) : pause à gauche, pochette + titre (ouvre 02), cœur plein, précédent / suivant. Padding 8/12/12.
4. **Bouton agrandir / réduire (desktop)** : toujours au même endroit, dans la barre de lecteur en bas, juste à gauche du volume. `[agrandir]` partout sauf sur D2 où il devient `[réduire]` (vert). Largeur fixe 10ch.
5. **Multi-appareils** : un seul appareil joue. Si la lecture est ailleurs, un bandeau vert « lecture sur … [écouter ici] » s'ajoute **au-dessus** du lecteur (mobile : au-dessus du mini-lecteur ; desktop : au-dessus de la barre, aligné à droite). Les boutons ne bougent jamais. Icônes : ordinateur / téléphone / tablette / enceinte. Détails : `Multi-Appareils.dc.html`.
6. **En-têtes mobiles avec [fermer]** (02, 06, 07…) : grille 3 colonnes `1fr auto 1fr`, titre centré sur l'écran, pas de trait sous l'en-tête.
7. **Rangées de filtres mobiles** : ne passent jamais à la ligne, défilent au doigt jusqu'au bord droit de l'écran, sans barre de défilement visible. Libellé fixe à gauche (`type:`, `bpm:`).
8. **Recherche** : un seul champ qui cherche partout (titres, artistes, albums, paroles). Raccourcis sous le champ : `paroles:` `artiste:` `album:` `genre:` `bpm ▾` `ton:` `ajouté ▾` (insèrent le préfixe). Syntaxe : `bpm:>120`, `ajouté:<30j`, combinables. Le texte trouvé est surligné en `#F9E2AF`, y compris au milieu d'un mot.
9. **Tranches de tempo** : `<90 · 90–120 · 120–140 · >140` (biblio, playlist, filtre bpm de la recherche).
10. **Tri** : `tri : [récent ▾]` → menu (mobile : panneau du bas ; desktop : menu déroulant). Un seul tri actif ●, sens ↓/↑ réglé à part, épinglés toujours en haut, choix mémorisé par liste. Détails : `Menus-Contextuels.dc.html` fiche 02.
11. **Menus contextuels** : uniquement les actions absentes de l'écran ; groupes séparés par un trait (naviguer › régler › fichier › bibliothèque) ; destructif en bas, en rouge, avec confirmation. Mobile = panneau du bas, desktop = menu déroulant sous [···].
12. **Pas de barre de défilement horizontale** sur aucun écran mobile.

---

## 5. Décisions produit

- **App locale** (serveur perso + clients). Pas de comptes partagés, donc : pas de profil social, pas de partage, **pas de playlists collaboratives**, pas de podcasts.
- **Recommandations** : oui (mix du jour, radios d'artistes, « à découvrir »). Nouvelles sorties : gardées « dans le doute ».
- **Accueil** (ordre) : écouté récemment · ajouts récents · tes mix du jour · nouvelles sorties · radios d'artistes. En-tête : `tty.fm $ accueil` + cloche (notifications) + engrenage (réglages), puis une ligne `// message du jour` sur toute la largeur.
- **Lecteur** :
  - menu [···] = aller à l'album · aller à l'artiste · lancer la radio | égaliseur › · lire sur… › | infos du fichier · modifier les tags · relancer l'analyse | archiver · retirer de la bibliothèque. **Exclus** : actions de file d'attente, ajout en playlist (déjà dans l'interface), minuterie, vitesse, « masquer des recos ».
  - **archiver** = masquer sans supprimer (hors biblio, recos, mix, recherche ; fichier et stats conservés ; réversible via bibliothèque › [archivés] ; toast « annuler » 5 s, pas de confirmation).
  - **retirer** = confirmation, case « supprimer aussi le fichier du disque » décochée par défaut.
  - Sous la progression : seulement la qualité (`// ogg 320 kbps`). Le fondu n'est pas rappelé.
  - **Lecture auto** : plus de bouton dans le lecteur. À la fin de la file, si la répétition est sur off, l'app enchaîne automatiquement sur des titres similaires (`// ensuite : radio « nova kid »`). L'option existe dans les réglages, **on** par défaut.
  - Pas de minuteur de veille. Pas de réglage de qualité dans le lecteur (réglages globaux uniquement).
- **Analyse audio** (calculée depuis le fichier) : genre + sous-genre en %, bpm, tonalité (notation Camelot, ex. 8A), ambiance, énergie, dansant, acoustique, LUFS, format. Affichée dans le lecteur (`$ analyse --piste`) + « enchaînement compatible » (bpm/ton proches).
- **Stats** : temps d'écoute par jour de la semaine, **graphe d'activité** façon contribution (1 case = 1 jour, 5 niveaux de bleu ; mobile 26 semaines, desktop 52), **heures par mois** (12 barres, record en vert), top artistes, tempo, temps forts, rétro annuelle le 1er décembre.
- **Réglages** :
  - lecture : fondu enchaîné, lecture auto ; son : qualité, normalisation, égaliseur (préréglages) ; bibliothèque : scan des dossiers (`4 812 titres · 38 Go` / `// scan il y a 2 h` sur deux lignes, [rescanner]) ; notifications ; données.
  - **Apparence / thèmes** : `suivre le système [off/on]`. On (défaut) → un thème sombre (« ✓ nuit ») + un thème clair (« ✓ jour »), bascule selon le système. Off → un seul thème.
    - sombres : catppuccin mocha (défaut), dracula, nord, gruvbox dark, tokyo night, rosé pine, one dark
    - clairs : catppuccin latte (défaut jour), solarized light, gruvbox light, rosé pine dawn, one light
    - Palettes embarquées dans l'app (fonctionne hors-ligne). Vérifier la licence de chaque thème (la plupart MIT) et créditer dans « à propos ». Pas de couleur d'accent séparée, pas d'option « égaliseur animé ».
  - taille du texte : petit / normal / grand.

---

## 6. Animations (durées et courbes)

| animation | durée | courbe | notes |
|---|---|---|---|
| changement d'onglet (barre + couleur qui traverse les lettres) | 360 ms | `cubic-bezier(0.65, 0, 0.35, 1)` | horizontal sur mobile, **vertical** sur desktop |
| défilement artiste + album trop longs | ≈ 40 px/s, linéaire | — | seulement si ça dépasse ; pause 15 % au début ; écart 48 px ; fondu 16 px aux bords |
| panneau du bas : ouverture | 320 ms | `cubic-bezier(0.32, 0.72, 0, 1)` | fond 0 → 72 % ; glisser vers le bas pour fermer (> 30 % ou geste rapide) |
| panneau du bas : fermeture | 220 ms | `cubic-bezier(0.4, 0, 1, 1)` | |
| menu déroulant desktop | 120 ms | — | fondu + 4 px |
| paroles synchronisées | 480 ms, déclenché 120 ms avant la ligne | `cubic-bezier(0.22, 1, 0.36, 1)` | ligne active sur la 3ᵉ des 7 visibles ; hauteur de ligne fixe (32 mobile / 40 desktop), taille via scale 0.87 → 1 ; suivi auto suspendu 4 s après un défilement manuel |

Avec « mouvement réduit » activé : pas de glissement, simples fondus de 120 ms.

---

## 7. Correspondances Flutter (suggestions)

| élément du design | piste Flutter |
|---|---|
| mini-graphe / jauge | `CustomPainter` (barres 7+1 unités, hauteur en 1/8), taille liée au `TextStyle` courant |
| panneau du bas (menus, tri) | `showModalBottomSheet` avec poignée, `barrierColor` à 72 %, courbes ci-dessus |
| menu déroulant desktop | `MenuAnchor` / `PopupMenuButton` |
| défilement artiste + album | widget marquee maison (`AnimationController` + `ShaderMask` pour les fondus) |
| paroles synchronisées | `ListView` à hauteur d'item fixe + `ScrollController.animateTo` |
| changement d'onglet | `AnimatedPositioned` pour la barre + `ShaderMask` dégradé 3 bandes pour le texte |
| graphe d'activité | `GridView` 7 lignes ou `CustomPainter` |
| thèmes | `ThemeExtension` avec les 13 couleurs du tableau §3, une instance par thème ; `ThemeMode.system` quand « suivre le système » est on |
| rangées de filtres qui défilent | `SingleChildScrollView(scrollDirection: Axis.horizontal)` sans scrollbar, padding droit 16 |
| case numéro / play | `SizedBox.square(dimension: 24)` centré |

---

## 8. Ce qui reste ouvert

- État « aucun résultat » de la recherche (pas encore dessiné).
- Panneau « à suivre » de D1 : passer ou non à la case carrée 24 px des autres listes.
- Page album / page artiste (accessibles depuis le menu [···]) : pas encore dessinées, reprendre la structure de 03b / D3b.
- Écran `bibliothèque › [archivés]`.
- Import d'un thème perso (VS Code `.json` / base16) : évoqué, non décidé.
