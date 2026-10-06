#!/usr/bin/env bash
# Sauvegarde logique de la base vers le manager (hors du noeud de la base).
#   ./scripts/db-backup.sh            -> ~/nebula-backups/nebula-<date>.dump
set -euo pipefail
DIR=${BACKUP_DIR:-$HOME/nebula-backups}
FICHIER=nebula-$(date +%Y%m%d-%H%M%S).dump
mkdir -p "$DIR"

docker service create --name nebula-backup --mode replicated-job --detach=false -q \
  --network nebula_internal --constraint node.role==manager \
  --secret db_user --secret db_password --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$DIR,dst=/backups" \
  postgres:18.6-alpine sh -c \
  'PGPASSWORD=$(cat /run/secrets/db_password) pg_dump -h db -U "$(cat /run/secrets/db_user)" -d nebula -Fc -f /backups/'"$FICHIER" \
  >/dev/null || true
docker service logs nebula-backup 2>&1 | tail -5
docker service rm nebula-backup >/dev/null

test -s "$DIR/$FICHIER" || { echo "ECHEC : sauvegarde absente ou vide" >&2; exit 1; }
ls -lh "$DIR/$FICHIER"
