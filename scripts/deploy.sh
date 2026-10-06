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
docker stack deploy --detach=false --with-registry-auth -c swarm/stack.nebula.yml nebula
./scripts/status.sh
