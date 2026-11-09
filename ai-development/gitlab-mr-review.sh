#!/usr/bin/env bash
# GitLab MR reviewer/discussion helper for Git Bash (Windows).
# Usage: gitlab-mr-review.sh reviewers|list PROJECT_ID MR_IID
#        gitlab-mr-review.sh reply PROJECT_ID MR_IID DISCUSSION_ID UTF8_BODY_FILE [--confirm-post] [--ack-unverified]
set -euo pipefail

usage() {
  printf 'Usage:\n  %s reviewers|list PROJECT_ID MR_IID\n  %s reply PROJECT_ID MR_IID DISCUSSION_ID BODY_FILE [--confirm-post] [--ack-unverified]\n' "$0" "$0" >&2
  exit 2
}
(( $# >= 3 )) || usage
action=$1; project=$2; mr=$3; shift 3
[[ $project =~ ^[1-9][0-9]*$ && $mr =~ ^[1-9][0-9]*$ ]] || usage
[[ -n ${GITLAB_URL:-} && -n ${GITLAB_TOKEN:-} ]] || { echo 'GITLAB_URL and GITLAB_TOKEN are required.' >&2; exit 2; }
[[ $GITLAB_URL =~ ^https?://[^/]+ ]] || { echo 'GITLAB_URL must begin with http(s)://' >&2; exit 2; }
command -v curl >/dev/null || { echo 'curl is required.' >&2; exit 2; }
base="${GITLAB_URL%/}/api/v4/projects/$project/merge_requests/$mr"
has_jq=0
if command -v jq >/dev/null 2>&1; then has_jq=1; fi

# Avoid echoing token or HTTP error bodies. Curl exits non-zero on 4xx/5xx.
api_get() {
  curl --fail --silent --show-error --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$1"
}
# Per-page JSON is validated if jq is installed. Without jq, raw JSON is
# output per page; page count follows 100-item page lengths only if an
# array-length parser is available. Instead use pagination response headers.
get_all() {
  local endpoint=$1 page=1 url headers body next
  while :; do
    url="$base/$endpoint?per_page=100&page=$page"
    headers=$(mktemp) || exit 1
    body=$(mktemp) || { rm -f "$headers"; exit 1; }
    if ! curl --fail --silent --show-error --dump-header "$headers" --output "$body" \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$url"; then
      rm -f "$headers" "$body"
      echo 'GitLab paged request failed.' >&2
      exit 1
    fi
    if (( has_jq )); then
      jq -e 'type == "array"' "$body" >/dev/null || { rm -f "$headers" "$body"; echo 'Expected JSON array.' >&2; exit 1; }
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
    # X-Next-Page is empty on the final page. Remove CR from CRLF headers.
    next=$(awk 'BEGIN{IGNORECASE=1} tolower($0) ~ /^x-next-page:/ {sub(/^[^:]*:[[:space:]]*/, ""); gsub(/\r/, ""); value=$0} END {print value}' "$headers")
    rm -f "$headers" "$body"
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
    (( $# >= 2 )) || usage
    id=$1; filename=$2; shift 2
    [[ -n $id && -f $filename && -r $filename && -s $filename ]] || { echo 'Valid discussion ID and nonempty UTF-8 body file required.' >&2; exit 2; }
    confirm=0; ack=0
    for flag in "$@"; do
      case $flag in
        --confirm-post) confirm=1 ;;
        --ack-unverified) ack=1 ;;
        *) usage ;;
      esac
    done
    # Slash/control characters are not valid Discussion ID path components.
    [[ $id =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Invalid discussion ID.' >&2; exit 2; }
    reply=$(cat "$filename")
    [[ -n ${reply//[[:space:]]/} ]] || { echo 'Reply cannot be whitespace-only.' >&2; exit 2; }
    discussion=$(api_get "$base/discussions/$id") || exit 1
    if (( has_jq )); then
      printf '%s' "$discussion" | jq -e 'any(.notes[]?; .resolvable == true and .resolved == false)' >/dev/null ||
        { echo 'Discussion not open/resolvable; reply refused.' >&2; exit 1; }
      if printf '%s' "$discussion" | jq -e --arg body "$reply" 'any(.notes[]?; .body == $body)' >/dev/null; then
        echo 'Identical reply already exists; refusing duplicate.' >&2; exit 1
      fi
    else
      if (( ! ack )); then
        echo 'jq not found. Review discussion state and duplicate replies manually, then retry with --ack-unverified.' >&2
        exit 1
      fi
      # This is intentionally not silent: caller explicitly owns manual validation.
      echo 'WARNING: posting without automatic state/duplicate verification.' >&2
    fi
    if (( ! confirm )); then
      printf 'DRY RUN: reply to discussion %s (nothing posted).\n' "$id"
      exit 0
    fi
    if (( has_jq )); then
      curl --fail --silent --show-error --request POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --data-urlencode "body@$filename" \
        "$base/discussions/$id/notes" | jq -c '{posted: true, note_id: .id}'
    else
      curl --fail --silent --show-error --request POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --data-urlencode "body@$filename" \
        "$base/discussions/$id/notes"
      printf '\n'
    fi
    ;;
  *) usage ;;
esac
