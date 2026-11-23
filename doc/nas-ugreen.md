# Installation sur un NAS UGREEN (UGOS Pro)

L'installation de référence du projet : un NAS UGREEN DXP2800 sous UGOS Pro, des images Docker construites sur un Mac Apple Silicon puis envoyées par SSH, et un accès distant par Tailscale. Pour une installation Docker Compose générique, voir [installation.md](installation.md) ; la configuration et le comportement du scan y sont décrits.

Prérequis : Docker activé dans UGOS Pro, SSH activé (Panneau de configuration → Terminal → SSH, puis **Appliquer**). Les commandes ci-dessous se lancent depuis le Terminal du Mac ; remplacer `user` et `nas` par le compte UGOS et l'adresse du NAS.

## Première installation

1. **Accès sans mot de passe** (une fois) :
   ```bash
   ssh-copy-id user@nas                                   # demande le mot de passe UGOS
   ssh -t user@nas 'sudo usermod -aG docker user'         # Docker sans sudo
   ```
   Une mise à jour d'UGOS peut retirer le compte du groupe `docker` ; il suffit alors de relancer la deuxième commande.

2. **Construire les images sur le Mac** (Apple Silicon, émulation x86_64 via Colima + Rosetta, environ 3 min) et les envoyer :
   ```bash
   colima start --vm-type vz --vz-rosetta --cpu 4 --memory 4   # une fois par session
   docker build --platform linux/amd64 --build-arg VERSION=$(git describe --always) -t ttyfm:latest server/
   docker build --platform linux/amd64 --build-arg VERSION=$(git describe --always) -t ttyfm-recommender:latest recommender/
   docker save ttyfm:latest ttyfm-recommender:latest | gzip | ssh user@nas 'gunzip | docker load'
   ```
   La seconde image est le service d'analyse et de recommandations ([recommender/README.md](../recommender/README.md)). Il tourne à côté du serveur et peut être arrêté à part (`docker compose stop recommender`).
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
   Le projet apparaît aussi dans l'application Docker de UGOS Pro. Le premier scan démarre automatiquement ; le log affiche `scan done … seen=… added=…`. Les fichiers copiés ensuite dans le dossier musique (par SMB depuis le Mac, par exemple) sont détectés une dizaine de secondes après la fin de la copie. Sur le NAS, la surveillance fsnotify fonctionne normalement.

5. **Vérifier** : `curl http://nas:4533/api/v1/health` doit répondre `{"status":"ok",…}`.

## Accès distant (Tailscale)

Tailscale tourne sur le NAS (paquet UGOS ou conteneur `tailscale/tailscale` en `network_mode: host`) et sur les clients. Dans l'application, utiliser l'adresse Tailscale du NAS (`100.x.y.z:4533` ou `nas.<tailnet>.ts.net:4533`) comme adresse du serveur, et l'adresse du NAS sur le réseau local comme adresse locale. Ne pas ouvrir le port 4533 sur Internet.

## Mise à jour

`tools/deploy-nas.sh` fait tout depuis le Mac. Il construit l'image, l'envoie, sauvegarde la base (serveur arrêté quelques secondes, dans `/volume1/docker/ttyfm/backups`, 5 copies gardées), relance le service et attend que `/health` annonce la nouvelle version. Une fois : copier `.deploy.env.example` en `.deploy.env` (ignoré par git) et y mettre `TTYFM_NAS=user@nas`.

```bash
tools/deploy-nas.sh                  # le serveur (par défaut)
tools/deploy-nas.sh recommender      # le service d'analyse
tools/deploy-nas.sh all --compose    # les deux, et le docker-compose.yml du dépôt
```

Les migrations de la base s'appliquent au démarrage du serveur. À la main : refaire l'étape 2, puis `ssh user@nas 'cd /volume1/docker/ttyfm && docker compose up -d'`.
