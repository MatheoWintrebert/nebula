# Nebula - Vérification

Commandes à lancer depuis le poste, à la racine du dépôt, sur le cluster en service. Elles ne cassent rien. Les tests destructifs sont dans [Scénarios](scenarios.md).

Prérequis : ceux de [Procédures](procedures.md), plus `jq` et `docker`.

```bash
B=http://nebula.test/api
TAG=$(curl -s $B/comptes/health | jq -r .version)
```

## 1. Cluster

```bash
ssh manager docker node ls
ssh manager "docker node ls -q | xargs docker node inspect -f '{{.Description.Hostname}} {{.Spec.Labels}}'"
```
Attendu : 3 nœuds Ready, `worker1` avec `nebula.db`, `worker2` avec `nebula.bus`.

## 2. Application

```bash
curl -s $B/comptes/health; echo; curl -s $B/publications/health; echo
ID=$(curl -s -XPOST $B/comptes -H 'content-type: application/json' -d '{"pseudo":"verif-'$RANDOM'"}' | jq .id)
curl -s $B/comptes/$ID; echo
curl -s -o /dev/null -w '%{http_code}\n' $B/comptes/99999999                    # 404
P=$(curl -s -XPOST $B/publications -H 'content-type: application/json' -d "{\"auteur_id\":$ID,\"titre\":\"verif\"}" | jq .id)
curl -s -o /dev/null -w '%{http_code}\n' -XPOST $B/publications -H 'content-type: application/json' -d '{"auteur_id":99999999,"titre":"x"}'   # 400
for i in 1 2; do curl -s $B/fil | jq -c '{source, n:(.items|length)}'; done    # db puis cache
```

```bash
sleep 3; ssh manager "docker service logs --since 2m nebula_worker-medias 2>&1 | grep publication-$P.json"
ssh worker2 'docker exec $(docker ps -qf name=nebula_bus) rabbitmqctl -q list_queues name messages consumers'
```
Attendu : le worker a traité la publication, la file `publications` est vide.

## 3. Exposition et réseaux

```bash
for p in 80 2377 5432 5672 6379 8080 15672; do printf "%-6s" $p; curl -s -m2 -o /dev/null -w '%{http_code}\n' http://nebula.test:$p/; done
ssh manager "docker network inspect -f '{{.Name}} internal={{.Internal}} mtu={{index .Options \"com.docker.network.driver.mtu\"}}' nebula_internal edge_public ingress"
```
Attendu : seul 80 répond, `nebula_internal internal=true`, MTU 1300.

## 4. Placement et ressources

```bash
ssh manager "cd ~/nebula && make status"
ssh manager "docker service inspect -f '{{.Spec.Name}} {{.Spec.TaskTemplate.Placement.Constraints}} {{json .Spec.TaskTemplate.Resources.Limits}}' \$(docker service ls -q)"
```

## 5. Secrets

```bash
ssh manager docker secret ls
docker run --rm -v "$PWD:/repo:ro" ghcr.io/gitleaks/gitleaks:v8.30.1 git /repo --no-banner
grep -rnE 'PASSWORD: [^$]|://[^/ ]+:[^@ ]+@' swarm/ || echo "aucun mot de passe dans la stack"
```
Attendu : 7 secrets, `no leaks found`.

## 6. Images et livraison

```bash
ssh manager "docker service ls --format '{{.Name}} {{.Image}}'" | grep -c ':latest' || true   # 0
ssh manager "docker service inspect -f '{{.Spec.TaskTemplate.ContainerSpec.Image}}' nebula_comptes"
gh run list --limit 8
```
Attendu : pas de `latest`, image `<VERSION>-<sha7>@sha256:...`.

## 7. Mises à jour

```bash
ssh manager "for s in comptes publications worker-medias db; do echo \"\$s \$(docker service inspect -f '{{json .Spec.UpdateConfig}}' nebula_\$s)\"; done"
```
Attendu : start-first et rollback pour les services sans état, stop-first pour db.

## 8. Répartition

```bash
for i in $(seq 12); do curl -s $B/comptes/health | jq -r .host; done | sort | uniq -c
```
Attendu : 3 hostnames.

## 9. Logs et administration

```bash
ssh manager "docker service logs --tail 3 nebula_comptes"
curl -s -o /dev/null -w '%{http_code}\n' http://admin.nebula.test/dashboard/                # 401
ssh manager 'curl -s -o /dev/null -w "%{http_code}\n" -u admin:$(cat ~/.nebula/admin-password) -H "Host: admin.nebula.test" http://127.0.0.1/dashboard/'   # 200
```

## 10. Sauvegarde

```bash
ssh manager "cd ~/nebula && make backup"
```
Attendu : un fichier `.dump` non vide dans `~/nebula-backups`.

## 11. Test complet

```bash
make smoke HOST=nebula.test
```
Attendu : tout `OK`.
