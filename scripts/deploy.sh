#!/usr/bin/env bash
# Deploie (ou met a jour) edge + nebula avec un tag d'image deja publie.
#   ./scripts/deploy.sh 1.0.0-a1b2c3d        (sur le manager)
# Ne construit rien : c'est l'image testee par la CI qui part en production.
set -euo pipefail
cd "$(dirname "$0")/.."
export TAG=${1:?usage: deploy.sh <tag>}
export REGISTRY=${REGISTRY:-ghcr.io/matheowintrebert}

docker network inspect edge_public >/dev/null 2>&1 ||
  docker network create --driver overlay --attachable \
    --opt com.docker.network.driver.mtu=1300 edge_public
./scripts/secrets-init.sh

docker stack deploy --detach=false -c swarm/stack.edge.yml edge
DEBUT=$(date +%s)
docker stack deploy --detach=true --with-registry-auth -c swarm/stack.nebula.yml nebula

# --detach=false verifie les services un par un (~30 s chacun) : on attend plutot qu'ils
# soient tous N/N ET qu'aucune mise a jour ne soit en cours (pendant un start-first, l'ancienne version affiche deja N/N).
etats() {
  docker service ls -q --filter label=com.docker.stack.namespace=nebula | xargs docker service inspect \
    --format '{{.Spec.Name}} {{if .UpdateStatus}}{{.UpdateStatus.State}} {{.UpdateStatus.StartedAt.Unix}}{{end}}'
}
pret() {
  docker service ls --filter label=com.docker.stack.namespace=nebula --format '{{.Replicas}}' |
    awk -F'[/ ]' '$1 + 0 != $2 + 0 { ko = 1 } END { exit ko }' &&
    ! etats | grep -qE ' (updating|rollback_started) '
}
for _ in $(seq 1 150); do pret && break; sleep 2; done
./scripts/status.sh
pret || { echo "ECHEC : services incomplets apres 5 min" >&2; exit 1; }
if etats | awk -v debut="$DEBUT" '$2 ~ /^rollback/ && $3 >= debut { print; ko = 1 } END { exit !ko }'; then
  echo "ECHEC : mise a jour annulee par Swarm (retour arriere)" >&2; exit 1
fi
