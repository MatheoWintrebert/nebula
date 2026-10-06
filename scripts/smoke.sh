#!/usr/bin/env bash
# Verifie la chaine complete : edge -> comptes -> publications -> bus -> worker.
#   ./scripts/smoke.sh [hote]        (defaut : nebula.local)
set -euo pipefail
B="http://${1:-nebula.local}/api"
ok=0

t() { printf '  %-40s' "$1"; shift; if "$@" >/dev/null 2>&1; then echo OK; else echo ECHEC; ok=1; fi; }

echo "== chaine applicative sur $B"
t "sante comptes"           curl -fsS "$B/comptes/health"
t "sante publications"      curl -fsS "$B/publications/health"
ID=$(curl -fsS -X POST "$B/comptes" -H 'content-type: application/json' \
  -d '{"pseudo":"smoke-'"$RANDOM$RANDOM"'"}' | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
t "creation d'un compte"    test -n "$ID"
t "lecture du compte"       curl -fsS "$B/comptes/$ID"
t "publication (auteur $ID)" curl -fsS -X POST "$B/publications" -H 'content-type: application/json' \
  -d '{"auteur_id":'"${ID:-0}"',"titre":"smoke"}'
t "auteur inconnu refuse"   sh -c "! curl -fsS -X POST '$B/publications' -H 'content-type: application/json' -d '{\"auteur_id\":999999,\"titre\":\"x\"}'"
t "lecture du fil"          curl -fsS "$B/fil"

echo
echo "== cache (la 2e lecture doit venir du cache)"
for _ in 1 2; do curl -fsS "$B/fil" | sed -n 's/.*"source":"\([^"]*\)".*/  source : \1/p'; done

echo
echo "== repartition (12 appels, le hostname doit varier)"
for _ in $(seq 1 12); do
  curl -fsS "$B/comptes/health" | sed -n 's/.*"host":"\([^"]*\)".*/\1/p'
done | sort | uniq -c

echo
echo "== asynchrone : sur le manager"
echo "   docker service logs --since 1m nebula_worker-medias"
exit $ok
