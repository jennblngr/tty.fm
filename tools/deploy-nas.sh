#!/usr/bin/env bash
# Builds the Docker images on this Mac and deploys them to the NAS:
# build (linux/amd64), send over ssh, back up the database, restart, then
# wait until /health reports the new version.
#
#   tools/deploy-nas.sh                  # the server only (default)
#   tools/deploy-nas.sh recommender      # the analysis service only
#   tools/deploy-nas.sh all              # both
#   tools/deploy-nas.sh --compose …      # also push docker-compose.yml
#
# Settings come from the environment or from .deploy.env at the repo root
# (git-ignored), see .deploy.env.example:
#   TTYFM_NAS       ssh target, user@host          (required)
#   TTYFM_NAS_DIR   install folder on the NAS      (/volume1/docker/ttyfm)
#   TTYFM_NAS_PORT  server port                    (4533)
#   TTYFM_BACKUPS   database backups to keep       (5)
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
[ -f .deploy.env ] && . ./.deploy.env

: "${TTYFM_NAS:?set TTYFM_NAS=user@host (environment or .deploy.env)}"
dir=${TTYFM_NAS_DIR:-/volume1/docker/ttyfm}
port=${TTYFM_NAS_PORT:-4533}
keep=${TTYFM_BACKUPS:-5}
host=${TTYFM_NAS#*@}

say() { printf '\033[32m$\033[0m %s\n' "$*"; }
die() {
  printf '\033[31merror:\033[0m %s\n' "$*" >&2
  exit 1
}
nas() { ssh -o BatchMode=yes -o ConnectTimeout=10 -o LogLevel=ERROR "$TTYFM_NAS" "$@"; }

compose=false
target=server
for arg in "$@"; do
  case $arg in
    --compose) compose=true ;;
    server | recommender | all) target=$arg ;;
    -h | --help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "unknown argument: $arg (server, recommender, all, --compose)" ;;
  esac
done
case $target in
  server) services=(server) ;;
  recommender) services=(recommender) ;;
  all) services=(server recommender) ;;
esac

version=$(git describe --always --dirty)
[[ $version == *-dirty ]] && printf '\033[33mwarning:\033[0m uncommitted changes: deploying %s\n' "$version"

say "checking the NAS ($TTYFM_NAS)"
nas "test -f '$dir/docker-compose.yml'" || die "no docker-compose.yml in $dir on the NAS (see README, step 3)"

if ! colima status >/dev/null 2>&1; then
  say "starting colima"
  colima start --vm-type vz --vz-rosetta --cpu 4 --memory 4
fi

images=()
for s in "${services[@]}"; do
  image=ttyfm; [ "$s" = recommender ] && image=ttyfm-recommender
  say "building $image:latest ($version)"
  docker build --platform linux/amd64 --build-arg "VERSION=$version" -t "$image:latest" "$s/"
  images+=("$image:latest")
done

say "sending ${images[*]}"
docker save "${images[@]}" | gzip | nas 'gunzip | docker load'

if $compose; then
  say "updating docker-compose.yml"
  # The NAS has no sources: drop the build sections (README, step 3).
  sed '/^    build:/,/^        VERSION/d' docker-compose.yml | nas "cat > '$dir/docker-compose.yml'"
fi

if [[ " ${services[*]} " == *" server "* ]]; then
  # SQLite runs in WAL mode: copy the database with the server stopped so
  # the three files agree. Keeps the last $keep copies.
  stamp=$(date +%Y%m%d-%H%M%S)
  say "backing up the database (backups/$stamp)"
  nas "set -e; cd '$dir'; docker compose stop server >/dev/null 2>&1
       mkdir -p backups/$stamp
       for f in data/ttyfm.db data/ttyfm.db-wal data/ttyfm.db-shm; do [ -f \$f ] && cp -p \$f backups/$stamp/; done
       ls -1d backups/*/ | sort | head -n -$keep | xargs -r rm -rf"
fi

say "restarting ${services[*]}"
nas "cd '$dir' && docker compose up -d ${services[*]}"

if [[ " ${services[*]} " == *" server "* ]]; then
  say "waiting for version $version"
  got=
  for _ in $(seq 1 30); do
    got=$(curl -fsS -m 3 "http://$host:$port/api/v1/health" 2>/dev/null | sed -n 's/.*"version":"\([^"]*\)".*/\1/p') || true
    [ "$got" = "$version" ] && break
    sleep 2
  done
  if [ "$got" != "$version" ]; then
    nas "cd '$dir' && docker compose logs --tail 30 server" >&2 || true
    die "the server answers ${got:-nothing}, expected $version (backup in $dir/backups)"
  fi
fi

# docker load leaves the previous image untagged: drop those (~550 MB each).
nas 'docker image prune -f >/dev/null'

nas "cd '$dir' && docker compose ps --format '{{.Service}}: {{.Status}}' && docker compose logs --tail 5 ${services[*]}"
say "deployed $version"
