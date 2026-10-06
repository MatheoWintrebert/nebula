# Nebula - Procédures

Les cinq procédures exigées (section 9 du cahier des charges), dix lignes maximum chacune, exécutables par un tiers.

**Prérequis du poste** : alias SSH `manager`, `worker1`, `worker2` (ProxyJump `router`) ; dans `/etc/hosts` : `10.210.0.39 nebula.test admin.nebula.test` (IP WAN du routeur, qui redirige le port 80 vers le manager).
**Sur le manager**, `~/nebula` est un lien vers le checkout du runner (`~/actions-runner/_work/nebula/nebula`), mis à jour à chaque déploiement.

---

## 1. Déploiement initial

```bash
ssh manager docker node ls                       # 3 nœuds Ready/Active, manager Leader (sinon § 6)
git push origin main                             # Actions « build » : construit, scanne, publie
echo "$(cat VERSION)-$(git rev-parse --short=7 HEAD)"   # le tag publié (aussi dans le résumé du run)
gh workflow run deploy -f tag=<tag>              # ou GitHub > Actions > deploy > Run workflow
ssh manager "cd ~/nebula && make status"               # chaque service N/N, bon tag, bons nœuds
make smoke HOST=nebula.test                     # depuis le poste : tout OK
```

Direct sur le manager (secours, ou en soutenance car plus rapide : ~80 s contre ~170 s avec l'attente GitHub) : `ssh manager "cd ~/nebula && ./scripts/deploy.sh <tag>"`. Le script crée le réseau `edge_public` et les secrets manquants, déploie `edge` puis `nebula`, attend que tout soit N/N et échoue si Swarm a dû revenir en arrière.

## 2. Mise à jour d'un service

```bash
# terminal 2 : preuve de non-interruption (que des 200)
while :; do curl -s -o /dev/null -w '%{http_code}\n' http://nebula.test/api/comptes/health; sleep .2; done | uniq -c
git commit -am "…" && git push                   # build publie <VERSION>-<nouveau sha7>
gh workflow run deploy -f tag=<nouveau-tag>
ssh manager watch -n1 docker service ps nebula_comptes   # 1 replica à la fois, le nouveau sain avant l'arrêt de l'ancien
curl -s http://nebula.test/api/comptes/health   # "version" = nouveau tag
```

## 3. Retour arrière

```bash
# Automatique : une version jamais saine est annulée seule (failure_action: rollback, monitor 30 s)
ssh manager docker service inspect -f '{{.UpdateStatus.State}} {{.UpdateStatus.Message}}' nebula_comptes
ssh manager "time docker service rollback nebula_comptes"   # manuel, un service : spec précédente
gh workflow run deploy -f tag=<tag-précédent>    # manuel, toute la stack (tags : historique des runs build)
ssh manager "cd ~/nebula && make status"               # vérifier tag et N/N
```

## 4. Arrêt et redémarrage complets du cluster

```bash
ssh manager sudo poweroff   # 1. le manager d'abord : plus aucune reprogrammation pendant l'arrêt
ssh worker2 sudo poweroff   # 2. bus
ssh worker1 sudo poweroff   # 3. base en dernier (Postgres s'arrête proprement, 30 s de grâce)
# Redémarrage (Proxmox) : worker1, worker2, puis manager. Docker et le runner démarrent seuls.
ssh manager docker node ls                       # ~1 min : 3 nœuds Ready, manager Leader
ssh manager "cd ~/nebula && make status"               # tout N/N (db et bus : 1 à 2 min)
ssh manager "for s in comptes publications worker-medias; do docker service update -d --force nebula_\$s; done"  # si tout est sur un nœud
make smoke HOST=nebula.test && curl -s http://nebula.test/api/comptes/1   # données d'avant présentes
```

## 5. Sauvegarde et restauration des données

```bash
ssh manager "cd ~/nebula && make backup"               # job Swarm pg_dump -> manager:~/nebula-backups/nebula-<date>.dump
ssh manager ls -lh nebula-backups                # copie hors du nœud de la base
ssh manager "cd ~/nebula && make restore FILE=\$HOME/nebula-backups/<fichier>.dump"   # -> "restauration : Complete"
curl -s http://nebula.test/api/comptes/<id>     # la donnée sauvegardée est revenue
# Base perdue (volume ou worker1) : étiqueter un nœud nebula.db=true, redéployer (init.sql recrée le schéma), puis restaurer.
```

---

## 6. Reconstruire le cluster depuis zéro

```bash
# Proxmox : 3 VM Debian 13 (Cloud-Init) manager .239, worker1 .240, worker2 .241, passerelle 10.96.2.254
for h in manager worker1 worker2; do ssh $h 'bash -s' < cluster/install-docker.sh; done   # Docker 29.8.2, MTU, journaux
./cluster/swarm-bootstrap.sh                     # init, join, étiquettes, ingress MTU 1300, docker node ls
# Runner : GitHub > Settings > Actions > Runners > New (label nebula-manager) ; sudo ./svc.sh install && start
# Après le 1er déploiement : ssh manager ln -sfn ~/actions-runner/_work/nebula/nebula ~/nebula
# Secret de dépôt GHCR_PULL_TOKEN = PAT read:packages ; puis procédure 1
```

## 7. Ajouter un service (scénario 10, < 10 min)

1. Image : soit une image publique (ex. `traefik/whoami:v1.12.0`), soit un dossier `services/<nom>/` avec un `Dockerfile` (la CI le construit sans modification).
2. Ajouter un bloc dans `swarm/stack.nebula.yml` sans toucher aux autres :

```yaml
  notifications:
    image: traefik/whoami:v1.12.0          # ou ${REGISTRY:?}/nebula-notifications:${TAG:?}
    networks: [edge_public]                # + internal s'il parle à db/cache/bus
    deploy:
      <<: *stateless
      replicas: 2
      labels:
        - traefik.enable=true
        - traefik.http.services.notifications.loadbalancer.server.port=80
        - traefik.http.routers.notifications.rule=PathPrefix(`/api/notifications`)
        - traefik.http.routers.notifications.middlewares=strip-api@swarm,retry@swarm
```

3. `git push` puis `gh workflow run deploy -f tag=<tag>` → `curl http://nebula.test/api/notifications`.

## Diagnostic rapide

| Question | Commande (sur le manager) |
|---|---|
| Qui dirige, nœuds prêts ? | `docker node ls` |
| Quoi, quelle version, où, combien ? | `make status` |
| Pourquoi une tâche ne démarre pas ? | `docker service ps --no-trunc nebula_<svc>` |
| Journaux d'un service / d'une instance | `docker service logs -f nebula_<svc>` / `docker service logs <id-tâche>` |
| Messages en erreur du bus | `ssh worker2 'docker exec $(docker ps -qf name=nebula_bus) rabbitmqctl list_queues name messages'` |
| Mot de passe du tableau de bord | `cat ~/.nebula/admin-password` → `http://admin.nebula.test/dashboard/` (user `admin`) |
