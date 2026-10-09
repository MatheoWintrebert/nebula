#!/usr/bin/env bash
# Usage : ./scripts/db-restore.sh ~/nebula-backups/<fichier>.dump (ecrase les tables)
set -euo pipefail
SRC=$(realpath "${1:?usage: db-restore.sh <fichier.dump>}")
test -s "$SRC"

docker service create --name nebula-restore --mode replicated-job --detach=false -q \
  --network nebula_internal --constraint node.role==manager \
  --secret db_user --secret db_password --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$(dirname "$SRC"),dst=/backups,readonly" \
  postgres:18.6-alpine sh -c \
  'PGPASSWORD=$(cat /run/secrets/db_password) pg_restore -h db -U "$(cat /run/secrets/db_user)" -d nebula --clean --if-exists --single-transaction /backups/'"$(basename "$SRC")" \
  >/dev/null || true
ETAT=$(docker service ps nebula-restore --format '{{.CurrentState}}' | head -1)
docker service logs nebula-restore 2>&1 | tail -5
docker service rm nebula-restore >/dev/null
echo "restauration : $ETAT"
case $ETAT in Complete*) ;; *) exit 1 ;; esac
