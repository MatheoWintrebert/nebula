SHELL := /bin/bash
HOST  ?= nebula.test

.DEFAULT_GOAL := help
.PHONY: help dev dev-down deploy status smoke backup restore clean

help: ## Affiche cette aide
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[1m%-10s\033[0m %s\n",$$1,$$2}'

dev: ## Lance les 7 services en local, hors Swarm (mot de passe jetable)
	DEV_PASSWORD=$${DEV_PASSWORD:-$$(openssl rand -hex 12)} docker compose -f compose.dev.yml up --build -d
dev-down: ## Arrete l'environnement local
	DEV_PASSWORD=x docker compose -f compose.dev.yml down -v
deploy: ## [manager] Deploie un tag publie : make deploy TAG=1.0.0-a1b2c3d
	./scripts/deploy.sh $(TAG)
status: ## [manager] Services, versions, machines, replicas
	./scripts/status.sh
smoke: ## Verifie la chaine complete depuis le poste
	./scripts/smoke.sh $(HOST)
backup: ## [manager] Sauvegarde la base dans ~/nebula-backups
	./scripts/db-backup.sh
restore: ## [manager] Restaure : make restore FILE=~/nebula-backups/x.dump
	./scripts/db-restore.sh $(FILE)
clean: ## [manager] Retire la stack nebula (volumes conserves)
	docker stack rm nebula && until ! docker network inspect nebula_internal >/dev/null 2>&1; do sleep 1; done
