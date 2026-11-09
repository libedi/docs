#!/usr/bin/env bash
# GitLab MR reviewer/discussion helper for Git Bash (Windows).
# Token: NOVA_TOKEN (Windows user-level environment variable, inherited by Git Bash).
# Usage: gitlab-mr-review.sh reviewers|list PROJECT_ID MR_IID
#        gitlab-mr-review.sh reply PROJECT_ID MR_IID DISCUSSION_ID COMMIT_SHA UTF8_BODY_FILE \
#          --last-seen-note-id NOTE_ID [--confirm-post] [--ack-unverified]
#   NOTE_ID: largest non-system note ID of the discussion as read from 'list'.
# Exit codes: 0 success or dry run, 1 API/validation failure or refused reply,
#             2 usage/configuration error, 3 pagination unverified (no jq and no
#             X-Next-Page header; the raw page was already printed).
set -euo pipefail

usage() {
  printf 'Usage:\n  %s reviewers|list PROJECT_ID MR_IID\n  %s reply PROJECT_ID MR_IID DISCUSSION_ID COMMIT_SHA BODY_FILE --last-seen-note-id NOTE_ID [--confirm-post] [--ack-unverified]\n' "$0" "$0" >&2
  exit 2
}
(( $# >= 3 )) || usage
action=$1; project=$2; mr=$3; shift 3
[[ $project =~ ^[1-9][0-9]*$ && $mr =~ ^[1-9][0-9]*$ ]] || usage
[[ -n ${GITLAB_URL:-} && -n ${NOVA_TOKEN:-} ]] || { echo 'GITLAB_URL and NOVA_TOKEN are required. Do not set the token from the agent; ask the user.' >&2; exit 2; }
[[ $GITLAB_URL =~ ^https?://[^/]+ ]] || { echo 'GITLAB_URL must begin with http(s)://' >&2; exit 2; }
command -v curl >/dev/null || { echo 'curl is required.' >&2; exit 2; }
base="${GITLAB_URL%/}/api/v4/projects/$project/merge_requests/$mr"
page_size=100
has_jq=0
if command -v jq >/dev/null 2>&1; then has_jq=1; fi

# Avoid echoing token or HTTP error bodies. Curl exits non-zero on 4xx/5xx.
api_get() {
  curl --ssl-revoke-best-effort --fail --silent --show-error --header "PRIVATE-TOKEN: $NOVA_TOKEN" "$1"
}

# Pages are followed via X-Next-Page (empty on the last page). If the header is
# missing altogether (e.g. stripped by a proxy), a full page may mean truncation:
# with jq the item count is checked and a full page fails (exit 1); without jq
# completeness cannot be checked, so it exits 3 instead of reporting success.
get_all() {
  local endpoint=$1 page=1 url headers body next count
  while :; do
    url="$base/$endpoint?per_page=$page_size&page=$page"
    headers=$(mktemp) || exit 1
    body=$(mktemp) || { rm -f "$headers"; exit 1; }
    if ! curl --ssl-revoke-best-effort --fail --silent --show-error --dump-header "$headers" --output "$body" \
        --header "PRIVATE-TOKEN: $NOVA_TOKEN" "$url"; then
      rm -f "$headers" "$body"
      echo 'GitLab paged request failed.' >&2
      exit 1
    fi
    count=''
    if (( has_jq )); then
      jq -e 'type == "array"' "$body" >/dev/null || { rm -f "$headers" "$body"; echo 'Expected JSON array.' >&2; exit 1; }
      count=$(jq 'length' "$body")
      if [[ $action == reviewers ]]; then
        jq -c '.[] | {reviewer: .user.username, state: .state}' "$body"
      else
        jq -c '.[] | select(any(.notes[]?; .resolvable == true and .resolved == false) or (all(.notes[]?; .resolvable != true))) | {
          kind: (if any(.notes[]?; .resolvable == true and .resolved == false) then "unresolved" else "triage" end),
          discussion_id: .id,
          notes: [.notes[]? | select(.system != true) | {
            id, author: .author.username, body, resolvable, resolved,
            file: .position.new_path, old_file: .position.old_path,
            line: .position.new_line, old_line: .position.old_line, created_at
          }]
        } | select(.notes | length > 0)' "$body"
      fi
    else
      # Raw per-page array. Agent must parse and classify.
      # stderr markers are separate from stdout JSON content.
      printf 'PAGE %s (%s): raw JSON, jq unavailable\n' "$page" "$endpoint" >&2
      cat "$body"
      printf '\n'
    fi
    # Prints "missing" when the header is absent, otherwise "found:<value>". Removes CR from CRLF headers.
    next=$(awk 'tolower($0) ~ /^x-next-page:/ {sub(/^[^:]*:/, ""); gsub(/[[:space:]]/, ""); found=1; value=$0} END {if (found) print "found:" value; else print "missing"}' "$headers")
    rm -f "$headers" "$body"
    if [[ $next == missing ]]; then
      if [[ -z $count ]]; then
        echo "X-Next-Page header missing on page $page and jq is unavailable; completeness unverified (exit 3). Count the items in the raw page: fewer than $page_size means it is complete." >&2
        exit 3
      elif (( count >= page_size )); then
        echo 'X-Next-Page header missing on a full page; refusing a possibly truncated result.' >&2
        exit 1
      fi
      break
    fi
    next=${next#found:}
    [[ -z $next ]] && break
    [[ $next =~ ^[1-9][0-9]*$ ]] || { echo "Invalid X-Next-Page: $next" >&2; exit 1; }
    (( next > page && next <= 10000 )) || { echo 'Pagination failed safety check.' >&2; exit 1; }
    page=$next
  done
}
case $action in
  reviewers|list)
    (( $# == 0 )) || usage
    if [[ $action == reviewers ]]; then get_all reviewers; else get_all discussions; fi
    ;;
  reply)
    (( $# >= 3 )) || usage
    id=$1; sha=$2; filename=$3; shift 3
    [[ -n $id && -f $filename && -r $filename && -s $filename ]] || { echo 'Valid discussion ID and nonempty UTF-8 body file required.' >&2; exit 2; }
    confirm=0; ack=0; last_seen=''
    while (( $# > 0 )); do
      case $1 in
        --confirm-post) confirm=1 ;;
        --ack-unverified) ack=1 ;;
        --last-seen-note-id) (( $# >= 2 )) || usage; last_seen=$2; shift ;;
        --last-seen-note-id=*) last_seen=${1#*=} ;;
        *) usage ;;
      esac
      shift
    done
    # Slash/control characters are not valid Discussion ID path components.
    [[ $id =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Invalid discussion ID.' >&2; exit 2; }
    [[ $sha =~ ^[0-9a-fA-F]{7,40}$ ]] || { echo 'COMMIT_SHA must be 7-40 hex characters.' >&2; exit 2; }
    [[ $last_seen =~ ^[1-9][0-9]*$ ]] || { echo '--last-seen-note-id (largest non-system note ID read from list) is required.' >&2; exit 2; }
    grep -q '[^[:space:]]' "$filename" || { echo 'Reply cannot be whitespace-only.' >&2; exit 2; }
    grep -qiF -- "$sha" "$filename" || { echo 'Body file must mention COMMIT_SHA so the reply points to the pushed fix.' >&2; exit 2; }
    discussion=$(api_get "$base/discussions/$id") || exit 1
    # Idempotency key = discussion + commit SHA. Unlike a full-body comparison it is not
    # affected by trailing newlines, CRLF, or how the server normalizes the body.
    # Here-strings instead of pipes: grep -q exits early, which pipefail would report as failure.
    if (( has_jq )); then
      jq -e 'any(.notes[]?; .resolvable == true and .resolved == false)' <<< "$discussion" >/dev/null ||
        { echo 'Discussion is not an open resolvable thread (resolved or triage); reply refused. Report it to the user instead.' >&2; exit 1; }
      if jq -e --arg sha "$sha" 'any(.notes[]?; (.body // "") | ascii_downcase | contains($sha | ascii_downcase))' <<< "$discussion" >/dev/null; then
        echo 'A note mentioning this commit already exists in the discussion; refusing duplicate.' >&2; exit 1
      fi
      # New review notes since the agent read the thread must be re-reviewed before replying.
      # System notes are ignored: pushing a fix adds "changed this line in version N" system notes.
      new_count=$(jq --argjson last "$last_seen" '[.notes[]? | select(.system != true and .id > $last)] | length' <<< "$discussion")
      if (( new_count > 0 )); then
        echo "Discussion has $new_count new note(s) after note $last_seen; reply refused. Re-review the thread first." >&2; exit 1
      fi
    else
      # A SHA needs no JSON unescaping, so the duplicate check works without jq. It matches the
      # raw JSON anywhere, so it can only over-refuse, never miss.
      if grep -qiF -- "$sha" <<< "$discussion"; then
        echo 'This commit SHA already appears in the discussion; refusing duplicate.' >&2; exit 1
      fi
      if (( ! ack )); then
        echo "jq not found. Check manually that the discussion is an open resolvable thread with no new non-system notes after note $last_seen, then retry with --ack-unverified." >&2
        exit 1
      fi
      # This is intentionally not silent: caller explicitly owns manual validation.
      echo 'WARNING: posting without automatic open/resolvable and new-note verification.' >&2
    fi
    if (( ! confirm )); then
      printf 'DRY RUN: reply to discussion %s for commit %s (nothing posted).\n' "$id" "$sha"
      exit 0
    fi
    if (( has_jq )); then
      curl --ssl-revoke-best-effort --fail --silent --show-error --request POST \
        --header "PRIVATE-TOKEN: $NOVA_TOKEN" \
        --data-urlencode "body@$filename" \
        "$base/discussions/$id/notes" | jq -c '{posted: true, note_id: .id}'
    else
      curl --ssl-revoke-best-effort --fail --silent --show-error --request POST \
        --header "PRIVATE-TOKEN: $NOVA_TOKEN" \
        --data-urlencode "body@$filename" \
        "$base/discussions/$id/notes"
      printf '\n'
    fi
    ;;
  *) usage ;;
esac
