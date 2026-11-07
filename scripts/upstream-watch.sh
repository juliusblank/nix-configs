#!/usr/bin/env bash
# upstream-watch — reminders for upstream issues and PRs that this repo waits on.
#
# Each watched item is an open issue in this repo with the label `upstream-watch`. Its
# body holds one fenced ```yaml block with the data:
#
#   url: https://github.com/NixOS/nixpkgs/issues/571894   # what to watch
#   interval_days: 30                                     # days between checks
#   last_checked: 2026-10-26
#   next_check: 2026-11-26
#   upstream_state: open                                  # written by this script
#   reminded_on: null                                     # written by this script
#
# Usage:
#   upstream-watch.sh check           comment on items whose upstream state changed or
#                                     whose next_check is due (once per due date)
#   upstream-watch.sh checked ISSUE   set last_checked = today and next_check = today +
#                                     interval_days (on a `/checked` comment)
#
# Needs: gh (GH_TOKEN, GH_REPO), yq (mikefarah), GNU date. DRY_RUN=1 prints instead of
# writing. Closing the issue stops the watch.
set -euo pipefail

label=upstream-watch
today=$(date -u +%F)
dry_run=${DRY_RUN:-}

# Print the yaml block of an issue body (without the fences).
extract_yaml() {
  awk '/^```yaml[[:space:]]*$/ {inside=1; next} inside && /^```[[:space:]]*$/ {exit} inside'
}

# Replace the yaml block in body (stdin) with the content of file $1.
replace_yaml() {
  awk -v file="$1" '
    /^```yaml[[:space:]]*$/ && !done {
      print; while ((getline line < file) > 0) print line; skip=1; next
    }
    skip && /^```[[:space:]]*$/ { skip=0; done=1 }
    !skip
  '
}

# Upstream state of a GitHub issue or PR URL: open, closed or merged. Empty for other
# URLs and when the API call fails (for example a private repo that the workflow token
# cannot read): the item then gets the date check only.
upstream_state() {
  local url=$1 repo num state
  if [[ $url =~ ^https://github\.com/([^/]+/[^/]+)/(issues|pull)/([0-9]+) ]]; then
    repo=${BASH_REMATCH[1]}
    num=${BASH_REMATCH[3]}
    if ! state=$(gh api "repos/$repo/issues/$num" \
      --jq 'if .pull_request.merged_at then "merged" else .state end' 2>/dev/null); then
      echo "warning: cannot read $url (private repo or API error), date check only" >&2
      return 0
    fi
    case $state in
      open | closed | merged) echo "$state" ;;
      *) echo "warning: unexpected state for $url, date check only" >&2 ;;
    esac
  fi
}

comment() {
  local issue=$1 text=$2
  if [[ -n $dry_run ]]; then
    printf '[dry-run] #%s comment: %s\n' "$issue" "$text"
  else
    gh issue comment "$issue" --body "$text" >/dev/null
  fi
}

# Write the updated yaml (file $3) back into the body of issue $1 (current body: $2).
save_yaml() {
  local issue=$1 body=$2 yaml=$3 new
  new=$(printf '%s\n' "$body" | replace_yaml "$yaml")
  if [[ -n $dry_run ]]; then
    printf '[dry-run] #%s new data:\n%s\n' "$issue" "$(cat "$yaml")"
  else
    gh issue edit "$issue" --body "$new" >/dev/null
  fi
}

check() {
  local issues issue body yaml url state old_state next reminded changed
  issues=$(gh issue list --label "$label" --state open --limit 200 --json number --jq '.[].number')
  for issue in $issues; do
    body=$(gh issue view "$issue" --json body --jq .body)
    yaml=$(mktemp)
    printf '%s\n' "$body" | extract_yaml > "$yaml"
    url=$(yq '.url // ""' "$yaml")
    if [[ -z $url ]]; then
      echo "#$issue: no yaml block with url, skipped" >&2
      continue
    fi
    changed=

    state=$(upstream_state "$url")
    old_state=$(yq '.upstream_state // ""' "$yaml")
    if [[ -n $state && $state != "$old_state" ]]; then
      if [[ -n $old_state ]]; then
        comment "$issue" "Upstream is now **$state** (was $old_state): $url"
      fi
      STATE=$state yq -i '.upstream_state = strenv(STATE)' "$yaml"
      changed=1
    fi

    next=$(yq '.next_check // ""' "$yaml")
    reminded=$(yq '.reminded_on // ""' "$yaml")
    # Due: next_check is today or earlier, and no reminder since that date.
    if [[ -n $next && ! $next > $today ]] && [[ -z $reminded || $reminded < $next ]]; then
      comment "$issue" "Check due (next_check $next): $url — comment \`/checked\` when done."
      TODAY=$today yq -i '.reminded_on = env(TODAY)' "$yaml"
      changed=1
    fi

    echo "#$issue: $url state=${state:-n/a} next_check=${next:-n/a}"
    [[ -n $changed ]] && save_yaml "$issue" "$body" "$yaml"
    rm -f "$yaml"
  done
}

checked() {
  local issue=$1 body yaml interval next
  body=$(gh issue view "$issue" --json body --jq .body)
  yaml=$(mktemp)
  printf '%s\n' "$body" | extract_yaml > "$yaml"
  interval=$(yq '.interval_days // 30' "$yaml")
  next=$(date -u -d "$today + $interval days" +%F)
  TODAY=$today NEXT=$next yq -i \
    '.last_checked = env(TODAY) | .next_check = env(NEXT) | .reminded_on = null' "$yaml"
  save_yaml "$issue" "$body" "$yaml"
  comment "$issue" "Checked on $today. Next check: $next."
  rm -f "$yaml"
}

case ${1:-} in
  check) check ;;
  checked) checked "${2:?issue number}" ;;
  *)
    echo "usage: upstream-watch.sh check | checked ISSUE" >&2
    exit 2
    ;;
esac
