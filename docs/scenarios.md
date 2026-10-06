# Nebula - Scénarios

Les dix vérifications de la section 12. La soutenance en joue quatre, tirées au sort, plus l'ajout d'un service. Les commandes `ssh manager …` se lancent depuis le poste ; voir [Procédures](procedures.md) pour les prérequis.

## Déroulé de la soutenance (10 min)

| Temps | Action | Référence |
|---|---|---|
| 2 min | `make clean && ./scripts/deploy.sh <tag>` sur le manager (~100 s) | scénario 3 |
| 3 min | deux scénarios tirés au sort | ci-dessous |
| 3 min | 8ᵉ service | procédure 7 |
| 2 min | « que casse cette ligne ? » | [Prédire l'effet d'une ligne](#prédire-leffet-dune-ligne) |

---

### 1. Les trois machines forment un seul cluster
```bash
ssh manager docker node ls
```
Preuve : 3 lignes `Ready / Active`, `manager` en `Leader`, même version 29.8.2.

### 2. Arrêt puis redémarrage complet
Procédure 4. Preuve : `docker node ls` (3 Ready), `make status` (tout N/N), `curl /api/comptes/<id créé avant l'arrêt>` → 200, `make smoke` OK.
Pendant l'arrêt : sans manager, plus de reprogrammation. Au démarrage, chaque démon Docker rejoue son état Swarm : le manager redevient leader (quorum 1/1), les workers se reconnectent sur 2377, et chaque tâche redémarre sur son nœud (db sur worker1 grâce à la contrainte, donc avec son volume).

### 3. Déploiement depuis zéro
```bash
ssh manager "cd ~/nebula && make clean && ./scripts/deploy.sh <tag>"   # ~100 s ; volumes conservés
make smoke                                          # depuis le poste
# Variante CI : gh workflow run deploy -f tag=<tag>  (~170 s, dont ~1 min d'attente de GitHub)
```

### 4. Contrôle de l'exposition
```bash
for p in 80 2377 5432 5672 6379 8080 8088 15672; do printf "%-6s" $p; curl -s -m2 -o /dev/null -w '%{http_code}\n' http://nebula.test:$p/; done   # 80 -> 404, le reste -> 000
ssh manager "docker service inspect edge_traefik --format '{{json .Endpoint.Ports}}'"   # seul service avec un port : 80, mode host
ssh manager "for h in 10.96.2.239 10.96.2.240 10.96.2.241; do for p in 5432 5672 6379; do timeout 1 bash -c \"</dev/tcp/\$h/\$p\" 2>/dev/null && echo \"\$h:\$p OUVERT\"; done; done; echo fin"
```
Preuve : seul le port 80 répond ; db, bus et cache ne répondent sur aucune IP de nœud. `nebula_internal` est `internal: true`.

### 5. Placement cohérent
```bash
ssh manager "cd ~/nebula && make status"
grep -n -A1 'constraints' swarm/stack.nebula.yml
```
Preuve : `nebula_db` sur worker1 (`node.labels.nebula.db == true`), `nebula_bus` sur worker2, aucun service sans état sur worker1 (`!= true`).

### 6. Montée en charge d'un service sans état
```bash
ssh manager docker service scale nebula_comptes=6
ssh manager docker service ps nebula_comptes --filter desired-state=running
for i in $(seq 20); do curl -s http://nebula.test/api/comptes/health | jq -r .host; done | sort | uniq -c
```
Preuve : 6 hostnames distincts dans les réponses, répartis entre manager et worker2. Retour : `docker service scale nebula_comptes=3`.

### 7. Mise à jour sans interruption perceptible
Procédure 2 avec la boucle `curl` en parallèle. Preuve : la boucle n'affiche que des `200`, et `/health` passe à la nouvelle version.

### 8. Version défectueuse puis retour arrière
```bash
gh workflow run defect -f tag=<tag>                  # publie nebula-comptes:<tag>-defect (sonde toujours en échec)
ssh manager "time docker service update --with-registry-auth --image ghcr.io/matheowintrebert/nebula-comptes:<tag>-defect nebula_comptes"
ssh manager docker service inspect -f '{{.UpdateStatus.State}}: {{.UpdateStatus.Message}}' nebula_comptes
```
Preuve : le premier replica défectueux ne devient jamais sain, Swarm revient seul à l'image précédente (`rollback_completed`), les 2 autres replicas servent pendant tout ce temps. Le `time` donne la durée.

### 9. Panne du plan de données
```bash
curl -s -XPOST http://nebula.test/api/comptes -H 'content-type: application/json' -d '{"pseudo":"avant-panne"}'
ssh worker1 'docker kill $(docker ps -qf name=nebula_db)'            # ou : ssh worker1 sudo reboot
ssh manager watch docker service ps nebula_db                         # nouvelle tâche, toujours sur worker1
curl -s http://nebula.test/api/comptes/<id>                          # la donnée est là (volume)
```
Si le volume est perdu : procédure 5 (restauration).

### 10. Ajout d'un service imprévu
Procédure 7.

---

## Prédire l'effet d'une ligne

| Ligne retirée | Effet |
|---|---|
| `constraints: [node.labels.nebula.db == true]` | db peut démarrer ailleurs, sur un volume vide : schéma réinitialisé, données « perdues » (restées sur worker1). |
| `com.docker.network.driver.mtu: "1300"` | réseau à 1500 sur un lien à 1350 : la santé passe, mais les grosses réponses (fil) se bloquent ou expirent. |
| `internal: true` | db, cache et bus restent non publiés, mais le réseau gagne une sortie vers l'extérieur ; l'isolation est plus faible. |
| `order: start-first` | l'ancien replica s'arrête avant que le nouveau soit sain : capacité réduite pendant la mise à jour, erreurs possibles. |
| `failure_action: rollback` | une image défectueuse met la mise à jour en pause (`paused`) au lieu de revenir en arrière. |
| `hostname: bus` | nom de nœud Erlang aléatoire à chaque démarrage : RabbitMQ ignore son volume, messages durables perdus. |
| `--with-registry-auth` | les workers ne peuvent pas tirer les images privées : tâches `No such image` sur worker2. |
| `traefik.http.routers.X.middlewares=strip-api…` | le service reçoit `/api/comptes` au lieu de `/comptes` → 404. |
| `secrets: [db_user, db_password]` (comptes) | `POSTGRES_PASSWORD_FILE` pointe vers un fichier absent : le conteneur sort au démarrage, rollback/redémarrages en boucle. |
| `restart_policy: { condition: any }` | `any` est la valeur par défaut, donc aucun changement : un « je ne sais pas » vaut mieux, puis vérifier. |
| `stop_grace_period: 30s` (db) | 10 s par défaut : Postgres risque un SIGKILL en plein checkpoint, puis une récupération (*crash recovery*) au démarrage. |

## Résultats mesurés

Répétition complète du 2026-10-06 sur le cluster réel, tag `1.0.0-884825c`.

| # | Résultat | Mesure |
|---|---|---|
| 1 | 3 nœuds Ready/Active, manager Leader, 29.8.2 partout | — |
| 2 | redémarrage des 3 VM (manager, worker2, worker1) : cluster reformé seul, db sur worker1, bus sur worker2, compte écrit avant présent, smoke OK, runner de nouveau en ligne, messages en erreur conservés | 3 nœuds Ready à **163 s**, tout N/N à **224 s** |
| 3 | `make clean` + `deploy.sh` + smoke, données conservées | clean 21 s + deploy ~80 s ; via workflow 170 s |
| 4 | seul 80 répond (404 Traefik) ; 5432/5672/6379/2377/8080/8088/15672 fermés depuis l'extérieur ; scan des 3 IP de nœuds : seul `10.96.2.239:80` ouvert | — |
| 5 | db → worker1, bus → worker2, aucun service sans état sur worker1 | — |
| 6 | `scale nebula_comptes=6` → 3 sur manager, 3 sur worker2 ; 30 appels = **5 par hostname** | — |
| 7 | mise à jour progressive de comptes + publications sous charge (GET santé, GET fil, POST publication toutes les 200 ms) | **636/636 réussies**, 86 s |
| 8 | image `-defect` : jamais saine, retour arrière automatique vers `1.0.0-884825c`, 147/147 requêtes OK pendant ce temps | retour arrière en **37 s** |
| 9 | `docker kill` de Postgres : nouvelle tâche sur worker1, compte écrit avant présent, écritures reprises | **12 s** |
| 10 | `traefik/whoami` routé sur `/api/notifications` (reçu en `/notifications`), 7 autres services intacts | **45 s** (pull compris) |
| Restauration | sauvegarde 12 Ko → `TRUNCATE` → 404 → restauration → compte et 677 publications revenus | restauration **7,7 s** |

Problèmes trouvés et corrigés pendant la répétition :
- RabbitMQ sans utilisateur : l'import de définitions désactive `default_user`.
- worker sans droit d'écriture sur `/data` (volume à root).
- 6 requêtes perdues sur 463 pendant une mise à jour, corrigé par le drain de 8 s + `dialTimeout`.
- `deploy.sh` trop lent (vérification séquentielle des services).
- `nebula.local` capturé par mDNS.
- `docker stack rm --detach=false` qui ne rend jamais la main.
