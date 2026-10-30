#!/usr/bin/env bash
# dispatcher-pool.sh: the "Pool do despachante" step of agent.yml (docs/factory-agent.md). The task runs on the pool of
# whoever dispatched it, never on another one.
#
# 1. Who dispatched: `issues` event: the issue's `por:<login>` label, valid only if its last `labeled` event in the
#    timeline was made by one of FACTORY_ACTORS; no `por:` label: DEFAULT_DISPATCHER (the owner). `issue_comment`
#    ("@claude"): the comment author.
# 2. Their pool: $POOLS_DIR/<login lowercased>.env (POOL_BASE_URL, POOL_KEY; written on the runner by the factory's
#    pool-sync), read as data. The key is masked and goes to $GITHUB_ENV with POOL_BASE_URL (the Anthropic base URL: no
#    trailing /v1). Hosted runner: only the owner's pool exists there (HOSTED_POOL_KEY, the org secret).
#    Transition: the owner with no $POOLS_DIR at all uses the old $LEGACY_KEY_FILE and LEGACY_BASE_URL.
# 3. No pool (no file, a label put by someone else, an invalid login, ...): comments "sem pool do despachante @<login>:
#    <motivo>" on the issue, writes skip=true to $GITHUB_OUTPUT and exits 0; the agent does not run.
#
# Env: EVENT, REPO, N, ISSUE_LABELS (JSON list of label names), COMMENT_AUTHOR, FACTORY_ACTORS (comma or space separated),
# DEFAULT_DISPATCHER, HOSTED (true/false), HOSTED_POOL_KEY, LEGACY_BASE_URL, POOLS_DIR, LEGACY_KEY_FILE, GITHUB_ENV,
# GITHUB_OUTPUT; GH_TOKEN for gh. The key is never printed (only in the ::add-mask:: command) nor passed as an argument.
# A copy of this file is embedded in .github/workflows/agent.yml; scripts/test-dispatcher-pool.sh checks they match.
set -euo pipefail

: "${POOLS_DIR:=$HOME/.pools}"
: "${LEGACY_KEY_FILE:=$HOME/.pool-key}"
: "${LEGACY_BASE_URL:=http://100.87.168.68:8317}"
: "${DEFAULT_DISPATCHER:?}" "${GITHUB_ENV:?}" "${GITHUB_OUTPUT:?}"

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
key_pattern='^[A-Za-z0-9._~+=-]+$'
url_pattern='^https?://[]A-Za-z0-9._:[-]+(/v1)?/?$'

stop() {
  local who="$1" why="$2"
  [[ "$who" =~ ^[A-Za-z0-9-]{1,39}$ ]] && who="@$who" || who="'$(printf '%s' "$who" | tr -cd 'A-Za-z0-9:._-' | cut -c1-60)'"
  local body="sem pool do despachante $who: $why"
  echo "::warning::$body (the agent does not run)"
  gh issue comment "$N" -R "$REPO" --body "$body" >/dev/null || echo "::warning::could not comment on #$N"
  echo "skip=true" >> "$GITHUB_OUTPUT"
  exit 0
}

# 1. The dispatcher.
dispatcher="" via=""
case "${EVENT:-}" in
  issue_comment)
    dispatcher="${COMMENT_AUTHOR:-}" via="author of the @claude comment" ;;
  issues)
    jq -e 'type == "array"' <<<"${ISSUE_LABELS:-[]}" >/dev/null 2>&1 || stop "?" "não foi possível ler os rótulos da issue"
    mapfile -t labels < <(jq -r '.[]? | select(type == "string" and startswith("por:"))' <<<"${ISSUE_LABELS:-[]}")
    if [ "${#labels[@]}" -eq 0 ]; then
      dispatcher="$DEFAULT_DISPATCHER" via="no por: label: the default dispatcher"
    else
      distinct=$(printf '%s\n' "${labels[@]}" | tr '[:upper:]' '[:lower:]' | sort -u | wc -l)
      [ "$distinct" -eq 1 ] || stop "${labels[0]#por:}" "mais de um rótulo por: na issue ($(printf '%s ' "${labels[@]}"))"
      label="${labels[0]}" dispatcher="${labels[0]#por:}"
      [[ "$dispatcher" =~ ^[A-Za-z0-9-]{1,39}$ ]] || stop "$dispatcher" "login inválido no rótulo $label"
      events=$(gh api "repos/$REPO/issues/$N/timeline" --paginate \
        --jq '.[] | select(.event == "labeled") | [.label.name, (.actor.login // "")] | @tsv') \
        || stop "$dispatcher" "não foi possível ler a linha do tempo da issue para conferir quem pôs $label"
      actor=$(awk -F'\t' -v l="$(lower "$label")" 'tolower($1) == l {a = $2} END {print a}' <<<"$events")
      [ -n "$actor" ] || stop "$dispatcher" "o rótulo $label não tem evento labeled na linha do tempo"
      ok=0
      IFS=', ' read -r -a actors <<<"${FACTORY_ACTORS:-}"
      for a in ${actors[@]+"${actors[@]}"}; do [ "$(lower "$a")" != "$(lower "$actor")" ] || ok=1; done
      [ "$ok" = 1 ] || stop "$dispatcher" "o rótulo $label foi posto por @$actor, que não é ator da fábrica"
      via="label $label put by $actor"
    fi ;;
  *)
    dispatcher="$DEFAULT_DISPATCHER" via="event ${EVENT:-none}: the default dispatcher" ;;
esac
[[ "$dispatcher" =~ ^[A-Za-z0-9-]{1,39}$ ]] || stop "$dispatcher" "login inválido"
login=$(lower "$dispatcher")
is_owner=0; [ "$login" != "$(lower "$DEFAULT_DISPATCHER")" ] || is_owner=1
echo "dispatcher: @$dispatcher ($via)"

# 2. Their pool.
base="" key=""
if [ "${HOSTED:-false}" = true ]; then
  [ "$is_owner" = 1 ] || stop "$dispatcher" "runner hospedado só tem o pool do dono (@$DEFAULT_DISPATCHER); use um runner próprio"
  key="${HOSTED_POOL_KEY:-}" base="$LEGACY_BASE_URL"
  [ -n "$key" ] || stop "$dispatcher" "o segredo FACTORY_POOL_KEY não chegou ao runner hospedado"
  from="org secret FACTORY_POOL_KEY"
elif [ -f "$POOLS_DIR/$login.env" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      POOL_BASE_URL=*) base="${line#POOL_BASE_URL=}" ;;
      POOL_KEY=*) key="${line#POOL_KEY=}" ;;
    esac
  done < "$POOLS_DIR/$login.env"
  from="$POOLS_DIR/$login.env"
elif [ "$is_owner" = 1 ] && [ ! -e "$POOLS_DIR" ] && [ -f "$LEGACY_KEY_FILE" ]; then
  key=$(tr -d ' \r\n\t' < "$LEGACY_KEY_FILE") base="$LEGACY_BASE_URL"
  from="$LEGACY_KEY_FILE (transition: no $POOLS_DIR on this runner)"
else
  stop "$dispatcher" "o runner ${RUNNER_NAME:-} não tem $(basename "$POOLS_DIR")/$login.env"
fi
[[ "$key" =~ $key_pattern ]] || stop "$dispatcher" "o pool do runner ${RUNNER_NAME:-} não tem POOL_KEY válida"
[[ "$base" =~ $url_pattern ]] || stop "$dispatcher" "o pool do runner ${RUNNER_NAME:-} não tem POOL_BASE_URL válida"
base="${base%/}" base="${base%/v1}"

echo "::add-mask::$key"
{ echo "POOL_KEY=$key"; echo "POOL_BASE_URL=$base"; } >> "$GITHUB_ENV"
{ echo "dispatcher=$dispatcher"; echo "base_url=$base"; } >> "$GITHUB_OUTPUT"
echo "pool of @$dispatcher from $from: $base"
