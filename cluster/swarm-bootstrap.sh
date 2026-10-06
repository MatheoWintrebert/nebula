#!/usr/bin/env bash
# Forme le cluster depuis le poste d'administration (alias SSH manager, worker1, worker2).
#   ./cluster/swarm-bootstrap.sh
set -euo pipefail
MANAGER_IP=10.96.2.239

ssh manager "docker swarm init --advertise-addr $MANAGER_IP"
TOKEN=$(ssh manager 'docker swarm join-token -q worker')
for w in worker1 worker2; do
  ssh "$w" "docker swarm join --advertise-addr \$(hostname -I | cut -d' ' -f1) --token $TOKEN $MANAGER_IP:2377"
done

ssh manager 'docker node update --label-add nebula.db=true worker1 &&
  docker node update --label-add nebula.bus=true worker2'

# Le reseau ingress par defaut herite du MTU 1500 : on le recree a 1300 avant tout service.
ssh manager 'yes | docker network rm ingress && sleep 3 &&
  docker network create --driver overlay --ingress \
    --opt com.docker.network.driver.mtu=1300 ingress'

ssh manager 'docker node ls'
