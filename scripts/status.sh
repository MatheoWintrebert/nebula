#!/usr/bin/env bash
# Ce qui tourne, en quelle version, sur quelle machine, en combien d'instances.
set -euo pipefail
docker service ls --format 'table {{.Name}}\t{{.Replicas}}\t{{.Image}}'
echo
docker stack ps nebula --filter desired-state=running \
  --format 'table {{.Name}}\t{{.Node}}\t{{.CurrentState}}\t{{.Image}}'
