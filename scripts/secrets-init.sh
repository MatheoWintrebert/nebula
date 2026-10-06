#!/usr/bin/env bash
# Cree les secrets Swarm manquants avec des valeurs aleatoires. Idempotent.
# A lancer sur le manager. Aucune valeur n'est ecrite dans le depot.
set -euo pipefail

existe() { docker secret inspect "$1" >/dev/null 2>&1; }
cree() { printf '%s' "$2" | docker secret create "$1" - >/dev/null; echo "secret $1 cree"; }
alea() { openssl rand -hex 24; }

# Chaque groupe partage une meme valeur : on le cree en entier ou pas du tout.
groupe() {
  local present=0 total=$#
  for s in "$@"; do existe "$s" && present=$((present + 1)); done
  if [ "$present" -ne 0 ] && [ "$present" -ne "$total" ]; then
    echo "groupe incoherent ($*) : supprimez ces secrets (stack arretee) puis relancez" >&2; exit 1
  fi
  [ "$present" -eq 0 ]
}

if groupe db_user db_password; then
  cree db_user nebula
  cree db_password "$(alea)"
fi

if groupe redis_conf redis_url; then
  pw=$(alea)
  cree redis_conf "$(printf 'requirepass %s\nsave ""\nappendonly no\nmaxmemory 64mb\nmaxmemory-policy allkeys-lru\n' "$pw")"
  cree redis_url "redis://:$pw@cache:6379"
fi

if groupe rabbitmq_credentials amqp_url; then
  pw=$(alea)
  cree rabbitmq_credentials "$(printf 'default_user = nebula\ndefault_pass = %s\n' "$pw")"
  cree amqp_url "amqp://nebula:$pw@bus:5672"
fi

if groupe traefik_users; then
  pw=$(alea)
  cree traefik_users "admin:$(openssl passwd -apr1 "$pw")"
  install -d -m 700 ~/.nebula
  ( umask 077; printf '%s\n' "$pw" > ~/.nebula/admin-password )
  echo "mot de passe du tableau de bord (utilisateur admin) : ~/.nebula/admin-password"
fi
