# Nebula - Procédures

Prérequis sur le poste : alias SSH `manager`, `worker1`, `worker2` (ProxyJump `router`) et dans `/etc/hosts` : `10.210.0.39 nebula.test admin.nebula.test`.

Sur le manager, `~/nebula` pointe vers le dossier du runner (`~/actions-runner/_work/nebula/nebula`).

## 1. Déploiement initial

```bash
ssh manager docker node ls                       # 3 nœuds Ready
git push origin main                             # build et publication des images
echo "$(cat VERSION)-$(git rev-parse --short=7 HEAD)"   # tag publié
gh workflow run deploy -f tag=<tag>
ssh manager "cd ~/nebula && make status"
make smoke HOST=nebula.test
```

Sans GitHub : `ssh manager "cd ~/nebula && ./scripts/deploy.sh <tag>"`.

## 2. Mise à jour d'un service

```bash
# dans un autre terminal : ne doit afficher que des 200
while :; do curl -s -o /dev/null -w '%{http_code}\n' http://nebula.test/api/comptes/health; sleep .2; done | uniq -c
git commit -am "..." && git push
gh workflow run deploy -f tag=<nouveau-tag>
ssh manager watch -n1 docker service ps nebula_comptes
curl -s http://nebula.test/api/comptes/health    # nouvelle version
```

## 3. Retour arrière

```bash
# automatique si la nouvelle version n'est jamais saine
ssh manager docker service inspect -f '{{.UpdateStatus.State}} {{.UpdateStatus.Message}}' nebula_comptes
ssh manager docker service rollback nebula_comptes   # un service
gh workflow run deploy -f tag=<tag-précédent>        # toute la stack
ssh manager "cd ~/nebula && make status"
```

## 4. Arrêt et redémarrage du cluster

```bash
ssh manager sudo poweroff
ssh worker2 sudo poweroff
ssh worker1 sudo poweroff
# redémarrer dans Proxmox : worker1, worker2, puis manager
ssh manager docker node ls
ssh manager "cd ~/nebula && make status"
ssh manager "for s in comptes publications worker-medias; do docker service update -d --force nebula_\$s; done"  # rééquilibrer
make smoke HOST=nebula.test
```

## 5. Sauvegarde et restauration

```bash
ssh manager "cd ~/nebula && make backup"         # ~/nebula-backups/nebula-<date>.dump
ssh manager ls -lh nebula-backups
ssh manager "cd ~/nebula && make restore FILE=\$HOME/nebula-backups/<fichier>.dump"
curl -s http://nebula.test/api/comptes/<id>
```

Si worker1 est perdu : mettre le label `nebula.db=true` sur un autre nœud, redéployer, puis restaurer.

## 6. Reconstruire le cluster

```bash
# Proxmox : 3 VM Debian 13, .239, .240, .241, passerelle 10.96.2.254
for h in manager worker1 worker2; do ssh $h 'bash -s' < cluster/install-docker.sh; done
./cluster/swarm-bootstrap.sh
# runner : GitHub > Settings > Actions > Runners > New (label nebula-manager), puis sudo ./svc.sh install && sudo ./svc.sh start
# après le premier déploiement : ssh manager ln -sfn ~/actions-runner/_work/nebula/nebula ~/nebula
# secret GHCR_PULL_TOKEN (PAT read:packages), puis procédure 1
```

## 7. Ajouter un service

Ajouter un bloc dans `swarm/stack.nebula.yml` :

```yaml
  notifications:
    image: traefik/whoami:v1.12.0
    networks: [edge_public]
    deploy:
      <<: *stateless
      replicas: 2
      labels:
        - traefik.enable=true
        - traefik.http.services.notifications.loadbalancer.server.port=80
        - traefik.http.routers.notifications.rule=PathPrefix(`/api/notifications`)
        - traefik.http.routers.notifications.middlewares=strip-api@swarm,retry@swarm
```

Puis `git push`, `gh workflow run deploy -f tag=<tag>` et `curl http://nebula.test/api/notifications`.

Pour une image maison, créer `services/<nom>/` avec un `Dockerfile` : la CI le construit.

## Commandes utiles (sur le manager)

| Besoin | Commande |
|---|---|
| État des nœuds | `docker node ls` |
| Services et versions | `make status` |
| Tâche qui ne démarre pas | `docker service ps --no-trunc nebula_<svc>` |
| Logs | `docker service logs -f nebula_<svc>` |
| Files du bus | `ssh worker2 'docker exec $(docker ps -qf name=nebula_bus) rabbitmqctl list_queues name messages'` |
| Mot de passe admin | `cat ~/.nebula/admin-password` |
