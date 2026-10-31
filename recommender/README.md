# recommender

Service de recommandations (Python), **phase 3 — non implémenté**.

Prévu :

1. Analyse audio (Essentia ou embeddings type CLAP), vecteurs stockés via `sqlite-vec`.
   Morceaux similaires, radio infinie.
2. Exploitation de l'historique (`plays`) : mixes quotidiens, morceaux oubliés.
3. Découverte externe via MusicBrainz / ListenBrainz (les `mbid` sont déjà stockés par le serveur).

Il tournera dans un conteneur séparé et lira la base SQLite du serveur
(lecture seule) ou passera par l'API.
