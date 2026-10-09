# Nebula - Scénarios

Les dix vérifications de la section 12. Prérequis : voir [Procédures](procedures.md).

## 1. Un seul cluster

```bash
ssh manager docker node ls
```
Attendu : 3 nœuds `Ready`, `manager` Leader.

## 2. Arrêt et redémarrage

Procédure 4. Attendu : 3 nœuds Ready, tout N/N, un compte créé avant l'arrêt est toujours là.

## 3. Déploiement depuis zéro

```bash
ssh manager "cd ~/nebula && make clean && ./scripts/deploy.sh <tag>"
make smoke
```

## 4. Exposition

```bash
for p in 80 2377 5432 5672 6379 8080 8088 15672; do printf "%-6s" $p; curl -s -m2 -o /dev/null -w '%{http_code}\n' http://nebula.test:$p/; done
ssh manager "docker service inspect edge_traefik --format '{{json .Endpoint.Ports}}'"
```
Attendu : seul le port 80 répond.

## 5. Placement

```bash
ssh manager "cd ~/nebula && make status"
grep -n -A1 'constraints' swarm/stack.nebula.yml
```
Attendu : db sur worker1, bus sur worker2, rien d'autre sur worker1.

## 6. Montée en charge

```bash
ssh manager docker service scale nebula_comptes=6
for i in $(seq 20); do curl -s http://nebula.test/api/comptes/health | jq -r .host; done | sort | uniq -c
ssh manager docker service scale nebula_comptes=3
```
Attendu : 6 hostnames différents.

## 7. Mise à jour sans coupure

Procédure 2. Attendu : que des `200` pendant la mise à jour.

## 8. Version défectueuse

```bash
gh workflow run defect -f tag=<tag>
ssh manager "time docker service update --with-registry-auth --image ghcr.io/matheowintrebert/nebula-comptes:<tag>-defect nebula_comptes"
ssh manager docker service inspect -f '{{.UpdateStatus.State}}' nebula_comptes
```
Attendu : `rollback_completed`, le service reste disponible.

## 9. Panne de la base

```bash
ssh worker1 'docker kill $(docker ps -qf name=nebula_db)'
ssh manager watch docker service ps nebula_db
curl -s http://nebula.test/api/comptes/<id>
```
Attendu : la base redémarre sur worker1 avec ses données.

## 10. Nouveau service

Procédure 7.

## Effet d'une ligne retirée

| Ligne | Effet |
|---|---|
| `constraints: [node.labels.nebula.db == true]` | db peut démarrer ailleurs, sur un volume vide. |
| `com.docker.network.driver.mtu: "1300"` | les grosses réponses bloquent. |
| `internal: true` | le réseau interne peut sortir du cluster. |
| `order: start-first` | l'ancien replica s'arrête avant que le nouveau soit prêt. |
| `failure_action: rollback` | une mauvaise image met la mise à jour en pause. |
| `hostname: bus` | RabbitMQ ignore son volume au redémarrage. |
| `--with-registry-auth` | les workers ne peuvent pas tirer les images privées. |
| `middlewares=strip-api...` | le service reçoit `/api/comptes` et renvoie 404. |
| `secrets: [db_user, db_password]` | le conteneur ne démarre pas. |
| `restart_policy: { condition: any }` | rien, c'est la valeur par défaut. |
| `stop_grace_period: 30s` (db) | Postgres peut être tué avant la fin de son arrêt. |

## Résultats (2026-10-06, tag `1.0.0-884825c`)

| # | Résultat |
|---|---|
| 1 | 3 nœuds Ready |
| 2 | cluster revenu seul, données présentes : Ready en 163 s, tout N/N en 224 s |
| 3 | clean 21 s + deploy 80 s (170 s via GitHub) |
| 4 | seul le port 80 est ouvert |
| 5 | placement correct |
| 6 | 6 replicas, 5 appels par hostname sur 30 |
| 7 | 636/636 requêtes OK en 86 s |
| 8 | retour arrière en 37 s, 147/147 requêtes OK |
| 9 | base revenue en 12 s |
| 10 | service ajouté en 45 s |
| Reconstruction | cluster refait depuis zéro, données restaurées, deploy 282 s |
| Restauration | 7,7 s |
