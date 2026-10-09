#!/usr/bin/env bash
# Forme le cluster depuis le poste. Peut etre relance sans risque.
set -euo pipefail
MANAGER_IP=10.96.2.239

etat() { ssh "$1" "docker info --format '{{.Swarm.LocalNodeState}}'"; }

[ "$(etat manager)" = active ] || ssh manager "docker swarm init --advertise-addr $MANAGER_IP"
TOKEN=$(ssh manager 'docker swarm join-token -q worker')
for w in worker1 worker2; do
  [ "$(etat "$w")" = active ] ||
    ssh "$w" "docker swarm join --advertise-addr \$(hostname -I | cut -d' ' -f1) --token $TOKEN $MANAGER_IP:2377"
done

ssh manager 'docker node update --label-add nebula.db=true worker1 >/dev/null &&
  docker node update --label-add nebula.bus=true worker2 >/dev/null'

# ingress est a 1500 par defaut ; network rm rend la main avant la fin de la suppression
ssh manager 'set -e
  mtu=absent
  if docker network inspect ingress >/dev/null 2>&1; then
    mtu=$(docker network inspect ingress --format "{{index .Options \"com.docker.network.driver.mtu\"}}")
  fi
  if [ "$mtu" != 1300 ]; then
    [ "$mtu" = absent ] || yes | docker network rm ingress >/dev/null
    until ! docker network inspect ingress >/dev/null 2>&1; do sleep 1; done
    docker network create --driver overlay --ingress --opt com.docker.network.driver.mtu=1300 ingress >/dev/null
  fi
  until [ "$(docker network inspect ingress --format "{{index .Options \"com.docker.network.driver.mtu\"}}" 2>/dev/null)" = 1300 ]; do sleep 1; done
  echo "ingress mtu=1300"'

ssh manager 'docker node ls'
