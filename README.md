# Nebula : infrastructure Docker Swarm

Reseau social minimal (comptes, publications, worker-medias) deploye sur un
cluster Swarm de trois VM : 1 manager, 2 workers. Seul le port 80 du manager
est publie (Traefik).

```
cluster/   construction des VM et du cluster depuis zero
swarm/     stack.edge.yml (Traefik), stack.nebula.yml (7 services), config du bus
scripts/   deploy, secrets, status, smoke, sauvegarde et restauration
services/  code applicatif (fourni, quasi inchange)
.github/   build (push sur main) -> ghcr.io ; deploy (manuel, runner sur le manager)
```

Images : `ghcr.io/matheowintrebert/nebula-<service>:<VERSION>-<sha7>`.

```bash
make deploy TAG=1.0.0-a1b2c3d   # sur le manager (ou Actions > deploy)
make status                     # quoi, quelle version, ou, combien
make smoke HOST=nebula.local    # depuis le poste
```

Les secrets sont generes sur le manager par `scripts/secrets-init.sh` et ne
sont jamais dans le depot.
