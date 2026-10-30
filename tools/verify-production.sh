#!/bin/bash
# Production smoke: no writes except a quick-login session and a health read.
set -euo pipefail
OS="${OS_URL:-http://127.0.0.1:4173}"
AGENT="${AGENT_URL:-http://127.0.0.1:4185}"
TOKEN="${AGENT_ENROLL_TOKEN:-local-dev-token}"
fail=0
check() { if eval "$2"; then echo "OK   $1"; else echo "FAIL $1"; fail=1; fi; }

check "OS live" "curl -fsS '$OS/api/health/live' >/dev/null"
check "direct web port closed" "test \"\$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:4180/)\" = 000"
check "proxy unauthenticated is 401" "test \"\$(curl -s -o /dev/null -w '%{http_code}' '$OS/processlink/')\" = 401"
jar=$(mktemp)
trap 'rm -f "$jar"' EXIT
curl -fsS -c "$jar" -X POST "$OS/api/auth/quick-login" -H 'content-type: application/json' -d '{"id":"uat-admin"}' >/dev/null
check "proxy authenticated is 200" "test \"\$(curl -s -b '$jar' -o /dev/null -w '%{http_code}' '$OS/processlink/')\" = 200"
embed=$(mktemp)
curl -fsS -b "$jar" "$OS/processlink/embed.js" -o "$embed"
if grep -q "ProcessLink" "$embed"; then echo "OK   micro-frontend module"; else echo "FAIL micro-frontend module"; fail=1; fi
rm -f "$embed"
check "OS state API" "curl -fsS -b '$jar' '$OS/api/processlink/state?key=feedback.v1' | grep -q '\"key\":\"feedback.v1\"'"
check "agent health" "curl -fsS '$AGENT/health' | grep -q '\"ok\":true'"
check "agent fleet list" "curl -fsS -H 'authorization: Bearer $TOKEN' '$AGENT/v1/agents' | grep -q '\"agents\"'"
check "agent rejects wrong token" "test \"\$(curl -s -o /dev/null -w '%{http_code}' -H 'authorization: Bearer nope' '$AGENT/v1/agents')\" = 401"
exit $fail
