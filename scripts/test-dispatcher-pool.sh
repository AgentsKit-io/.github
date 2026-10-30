#!/usr/bin/env bash
# Tests of .github/scripts/dispatcher-pool.sh with a fake gh and a throwaway HOME (never GitHub, the pool or the real HOME),
# and of the copy embedded in .github/workflows/agent.yml. Run from the repository root: bash scripts/test-dispatcher-pool.sh
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/.github/scripts/dispatcher-pool.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0 count=0

mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_GH_LOG"
case "$1 $2" in
  "api repos/"*) [ "${FAKE_GH_FAIL:-0}" = 0 ] || exit 1; printf '%b' "${FAKE_TIMELINE:-}" ;;
  "issue comment") exit 0 ;;
  *) exit 2 ;;
esac
GH
chmod +x "$work/bin/gh"

KEY_R="sk-pool-rembradtech-0123456789abcdef"
KEY_O="sk-pool-owner-fedcba9876543210"
KEY_V="sk-pool-dev4lifev-a1b2c3d4"
KEY_LEGACY="sk-legacy-pool-key-55aa55aa"
KEY_HOSTED="sk-hosted-org-secret-77bb77bb"

# A fresh case: HOME with .pools/ (unless told otherwise), empty outputs and log. Usage: setup [nopools]
setup() {
  case_dir=$(mktemp -d "$work/case.XXXXXX")
  home="$case_dir/home"; mkdir -p "$home"
  if [ "${1:-}" != nopools ]; then
    mkdir -p "$home/.pools"
    printf 'POOL_BASE_URL=http://100.64.0.5:8401/v1\nPOOL_KEY=%s\n' "$KEY_R" > "$home/.pools/rembradtech.env"
    printf 'POOL_BASE_URL=http://100.64.0.5:8400/v1\nPOOL_KEY=%s\n' "$KEY_O" > "$home/.pools/emersonbraun.env"
    printf 'POOL_BASE_URL=http://100.64.0.5:8402/v1\nPOOL_KEY=%s\n' "$KEY_V" > "$home/.pools/dev4lifev.env"
  fi
  : > "$case_dir/env"; : > "$case_dir/output"; : > "$case_dir/gh.log"
}

# Runs the script with the case's HOME and the given VAR=value pairs; output in $case_dir/out.
run() {
  (cd "$case_dir" && env -i PATH="$work/bin:$PATH" HOME="$home" FAKE_GH_LOG="$case_dir/gh.log" \
    GITHUB_ENV="$case_dir/env" GITHUB_OUTPUT="$case_dir/output" RUNNER_NAME=agent-test \
    REPO=AgentsKit-io/factory-sandbox N=7 GH_TOKEN=fake \
    FACTORY_ACTORS="noxcode-factory[bot],EmersonBraun" DEFAULT_DISPATCHER=EmersonBraun HOSTED=false \
    "$@" bash "$script") > "$case_dir/out" 2>&1
  rc=$?
}

check() { # check <description> <condition...>
  local what="$1"; shift
  count=$((count + 1))
  if "$@"; then echo "ok   $current: $what"; else echo "FAIL $current: $what"; fails=$((fails + 1)); sed 's/^/     | /' "$case_dir/out"; fi
}
has() { grep -qF -- "$2" "$1"; }
lacks() { ! grep -qF -- "$2" "$1"; }
exit0() { [ "$rc" = 0 ]; }
# The agent runs on <base> with <key>, no comment was posted.
runs_on() {
  check "exits 0" exit0
  check "POOL_KEY exported" has "$case_dir/env" "POOL_KEY=$2"
  check "POOL_BASE_URL is $1" has "$case_dir/env" "POOL_BASE_URL=$1"
  check "no skip" lacks "$case_dir/output" "skip=true"
  check "no comment" lacks "$case_dir/gh.log" "issue comment"
  check "key masked before anything else uses it" has "$case_dir/out" "::add-mask::$2"
}
# The agent does not run; the issue gets "sem pool do despachante <who>: ...<why>".
stops() {
  check "exits 0" exit0
  check "skip=true" has "$case_dir/output" "skip=true"
  check "nothing exported" eval '[ ! -s "$case_dir/env" ]'
  check "comment on the issue: sem pool do despachante $1" has "$case_dir/gh.log" "issue comment 7 -R AgentsKit-io/factory-sandbox --body sem pool do despachante $1: "
  check "reason: $2" has "$case_dir/gh.log" "$2"
}
# No key ever reaches the output (other than the ::add-mask:: command), the comment, gh's arguments or GITHUB_OUTPUT.
no_key_leak() {
  local k
  for k in "$KEY_R" "$KEY_O" "$KEY_V" "$KEY_LEGACY" "$KEY_HOSTED"; do
    check "key ${k:0:12}… not in the output" eval '! grep -v "^::add-mask::" "$case_dir/out" | grep -qF -- "$k"'
    check "key ${k:0:12}… not in gh calls" lacks "$case_dir/gh.log" "$k"
    check "key ${k:0:12}… not in GITHUB_OUTPUT" lacks "$case_dir/output" "$k"
  done
}

current="label put by the factory → that login's pool"
setup
run EVENT=issues ISSUE_LABELS='["agent:go","por:rembradtech"]' FAKE_TIMELINE='agent:go\tEmersonBraun\npor:rembradtech\tnoxcode-factory[bot]\n'
runs_on http://100.64.0.5:8401 "$KEY_R"
check "dispatcher output" has "$case_dir/output" "dispatcher=rembradtech"
check "timeline asked" has "$case_dir/gh.log" "api repos/AgentsKit-io/factory-sandbox/issues/7/timeline --paginate"
no_key_leak

current="label put by the Mac release login (factory actor, other case) → that login's pool"
setup
run EVENT=issues ISSUE_LABELS='["por:Dev4LifeV","agent:go"]' FAKE_TIMELINE='por:Dev4LifeV\temersonbraun\n'
runs_on http://100.64.0.5:8402 "$KEY_V"
no_key_leak

current="label put by someone else → stops"
setup
run EVENT=issues ISSUE_LABELS='["agent:go","por:rembradtech"]' FAKE_TIMELINE='por:rembradtech\tmallory\n'
stops @rembradtech "foi posto por @mallory, que não é ator da fábrica"
no_key_leak

current="label put by the factory, then removed and put again by someone else → stops (the last one counts)"
setup
run EVENT=issues ISSUE_LABELS='["por:rembradtech"]' FAKE_TIMELINE='por:rembradtech\tnoxcode-factory[bot]\npor:rembradtech\tmallory\n'
stops @rembradtech "posto por @mallory"

current="label with no labeled event in the timeline → stops"
setup
run EVENT=issues ISSUE_LABELS='["por:rembradtech"]' FAKE_TIMELINE='agent:go\tEmersonBraun\n'
stops @rembradtech "não tem evento labeled"

current="timeline cannot be read → stops"
setup
run EVENT=issues ISSUE_LABELS='["por:rembradtech"]' FAKE_GH_FAIL=1
stops @rembradtech "linha do tempo"

current="two por: labels → stops"
setup
run EVENT=issues ISSUE_LABELS='["por:rembradtech","por:Dev4LifeV"]' FAKE_TIMELINE='por:rembradtech\tnoxcode-factory[bot]\npor:Dev4LifeV\tnoxcode-factory[bot]\n'
stops @rembradtech "mais de um rótulo por:"

current="invalid login in the label → stops"
setup
run EVENT=issues ISSUE_LABELS='["por:../../etc/x"]' FAKE_TIMELINE='por:../../etc/x\tnoxcode-factory[bot]\n'
stops "'....etcx'" "login inválido"
check "timeline not even asked" lacks "$case_dir/gh.log" "timeline"

current="no por: label → the default dispatcher's pool"
setup
run EVENT=issues ISSUE_LABELS='["agent:go"]'
runs_on http://100.64.0.5:8400 "$KEY_O"
check "dispatcher output" has "$case_dir/output" "dispatcher=EmersonBraun"
check "timeline not asked" lacks "$case_dir/gh.log" "timeline"
no_key_leak

current="@claude comment → the author's pool"
setup
run EVENT=issue_comment COMMENT_AUTHOR=Dev4LifeV ISSUE_LABELS='["por:rembradtech"]'
runs_on http://100.64.0.5:8402 "$KEY_V"
check "dispatcher output" has "$case_dir/output" "dispatcher=Dev4LifeV"
no_key_leak

current="@claude comment by someone with no pool file → stops"
setup
run EVENT=issue_comment COMMENT_AUTHOR=outsider
stops @outsider "não tem .pools/outsider.env"

current="pool file missing for the labelled login → stops (never another pool)"
setup
rm "$home/.pools/rembradtech.env"
run EVENT=issues ISSUE_LABELS='["por:rembradtech"]' FAKE_TIMELINE='por:rembradtech\tnoxcode-factory[bot]\n'
stops @rembradtech "o runner agent-test não tem .pools/rembradtech.env"
no_key_leak

current="pool file without a key → stops"
setup
printf 'POOL_BASE_URL=http://100.64.0.5:8401/v1\n' > "$home/.pools/rembradtech.env"
run EVENT=issues ISSUE_LABELS='["por:rembradtech"]' FAKE_TIMELINE='por:rembradtech\tnoxcode-factory[bot]\n'
stops @rembradtech "POOL_KEY válida"

current="transition: owner, no .pools/ on the runner → the old .pool-key"
setup nopools
printf '%s\n' "$KEY_LEGACY" > "$home/.pool-key"
run EVENT=issues ISSUE_LABELS='["agent:go"]'
runs_on http://100.87.168.68:8317 "$KEY_LEGACY"
no_key_leak

current="transition: someone else, no .pools/ → stops (never the old .pool-key)"
setup nopools
printf '%s\n' "$KEY_LEGACY" > "$home/.pool-key"
run EVENT=issue_comment COMMENT_AUTHOR=rembradtech
stops @rembradtech "não tem .pools/rembradtech.env"
no_key_leak

current="owner with .pools/ but no file of theirs → stops (the old .pool-key is only for runners with no .pools/)"
setup
rm "$home/.pools/emersonbraun.env"
printf '%s\n' "$KEY_LEGACY" > "$home/.pool-key"
run EVENT=issues ISSUE_LABELS='[]'
stops @EmersonBraun "não tem .pools/emersonbraun.env"
no_key_leak

current="hosted runner, owner → the org secret"
setup nopools
run EVENT=issues ISSUE_LABELS='["agent:go"]' HOSTED=true HOSTED_POOL_KEY="$KEY_HOSTED"
runs_on http://100.87.168.68:8317 "$KEY_HOSTED"
no_key_leak

current="hosted runner, someone else → stops"
setup nopools
run EVENT=issue_comment COMMENT_AUTHOR=rembradtech HOSTED=true HOSTED_POOL_KEY="$KEY_HOSTED"
stops @rembradtech "runner hospedado só tem o pool do dono"
no_key_leak

current="agent.yml embeds this exact script"
case_dir="$work"; : > "$work/out"
awk '/cat > "\$RUNNER_TEMP\/dispatcher-pool.sh" <<'"'"'SH'"'"'/ {on=1; next} on && /^ *SH$/ {exit} on {sub(/^          /, ""); print}' \
  "$root/.github/workflows/agent.yml" > "$work/embedded.sh"
check "embedded copy found" eval '[ -s "$work/embedded.sh" ]'
check "embedded copy identical to .github/scripts/dispatcher-pool.sh" eval 'diff -u "$script" "$work/embedded.sh" > "$work/out"'

echo "$((count - fails))/$count checks passed"
[ "$fails" = 0 ]
