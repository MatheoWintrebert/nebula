#!/usr/bin/env bash
set -euo pipefail
docker service ls --format 'table {{.Name}}\t{{.Replicas}}\t{{.Image}}'
echo
docker stack ps nebula --filter desired-state=running \
  --format 'table {{.Name}}\t{{.Node}}\t{{.CurrentState}}\t{{.Image}}'
