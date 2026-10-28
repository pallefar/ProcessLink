#!/bin/zsh
# Read-only smoke test for the Flightdeck OS UAT API. Prints counts, never the
# cookie or a password. Usage: tools/uat-smoke.sh [base-url] [account-id]
set -euo pipefail
base="${1:-http://127.0.0.1:4173}"
account="${2:-uat-admin}"
jar=$(mktemp)
trap 'rm -f "$jar"' EXIT

json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

accounts=$(curl -fsS "$base/api/auth/quick-login")
echo "quick-login enabled: $(print -r -- "$accounts" | json 'd.get("enabled")')"
print -r -- "$accounts" | python3 -c "import json,sys; d=json.load(sys.stdin); print('accounts:', ', '.join(a['id'] for a in d.get('accounts', [])))"
curl -fsS -c "$jar" -H 'content-type: application/json' \
  -d "{\"id\":\"$account\"}" "$base/api/auth/quick-login" >/dev/null
echo "signed in: $(curl -fsS -b "$jar" "$base/api/auth/me" | json 'd["principal"]["username"], "·", d["principal"]["role"]')"
workspace=$(curl -fsS -b "$jar" "$base/api/workspaces" | json 'd["workspaces"][0]["id"]')
echo "workspace: $workspace"
project=$(curl -fsS -b "$jar" -H "X-Workspace-Id: $workspace" "$base/api/projects" | python3 -c "import json,sys; d=json.load(sys.stdin); print(next((p['id'] for p in d['projects'] if p['id']=='project-contract'), d.get('defaultProjectId') or d['projects'][0]['id']))")
echo "project: $project"
vision=$(curl -fsS -b "$jar" -H "X-Workspace-Id: $workspace" -H "X-Project-Id: $project" "$base/api/project-vision")
echo "vision: $(print -r -- "$vision" | json 'd["workspace"]["status"]')"
kpis=$(curl -fsS -b "$jar" -H "X-Workspace-Id: $workspace" -H "X-Project-Id: $project" "$base/api/apps/advantage/process-kpis")
echo "advantage KPIs: $(print -r -- "$kpis" | json 'len(d["kpis"])')"
opps=$(curl -fsS -b "$jar" -H "X-Workspace-Id: $workspace" -H "X-Project-Id: $project" "$base/api/apps/advantage/opportunities")
echo "advantage opportunities: $(print -r -- "$opps" | json 'len(d["opportunities"])')"

if [[ -n "${ATLAS_URL:-}" && -n "${ATLAS_EMAIL:-}" ]]; then
  echo "atlas: $(curl -fsS -H 'Cookie: __sites_local_auth=1' "$ATLAS_URL/api/projects" | json 'len(d["projects"])') projects ($ATLAS_EMAIL)"
fi
