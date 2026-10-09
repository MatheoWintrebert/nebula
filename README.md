# Nebula

Réseau social simple (comptes, publications, worker-medias) déployé sur un cluster Docker Swarm de trois VM : 1 manager, 2 workers. Seul le port 80 du manager est ouvert (Traefik).

```
docs/      architecture, procédures, scénarios, vérification
cluster/   installation des VM et du cluster
swarm/     stacks Traefik et Nebula, config du bus
scripts/   deploy, secrets, status, smoke, sauvegarde, restauration
services/  code de l'application
.github/   build (push sur main) et deploy (manuel)
```

Images : `ghcr.io/matheowintrebert/nebula-<service>:<VERSION>-<sha7>`.

```bash
make deploy TAG=1.0.0-a1b2c3d   # sur le manager
make status                     # services, versions, nœuds
make smoke HOST=nebula.test     # depuis le poste
```

Les secrets sont créés sur le manager par `scripts/secrets-init.sh`, jamais dans le dépôt.
