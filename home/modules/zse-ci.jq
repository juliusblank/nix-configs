# zse-ci: a GitHub PR (gh pr view --json …) → the review status summary.
# --arg me <login>. "Since my last review": after my latest review (its
# commit) or my latest comment, whichever is newer.
#
# review_state (the picker, `zse ls` and the tab name show it):
#   merged / closed  the PR is merged or closed
#   new              I have not reviewed or commented yet, or there are new
#                    commits or comments / reviews by others since then
#   approved         my latest review approves, nothing new since
#   submitted        my latest review comments or requests changes (or I
#                    only commented), nothing new since

# Ticket IDs as in zse.zsh (ZSE_TICKET_RE / ZSE_TICKET_NOT; keep in sync).
def tickets: [match("(?:^|[^A-Za-z0-9])([A-Za-z]{2,6}-[0-9]{3,})(?![0-9])"; "g").captures[0].string | ascii_upcase
              | select(split("-")[0] | test("^(SHA|ISO|RFC|CVE|UTC)$") | not)];
def first_line: (. // "" | gsub("<!--[\\s\\S]*?-->"; "") | split("\n") | map(select(test("\\S"))) | .[0] // "" | .[0:90]);
def outcome:
  ((if (.conclusion // "") != "" then .conclusion else (.state // .status // "") end) | ascii_upcase)
  | if . == "SUCCESS" or . == "NEUTRAL" then "pass"
    elif . == "SKIPPED" then "skip"
    elif . == "CANCELLED" then "cancel"
    elif . == "FAILURE" or . == "ERROR" or . == "TIMED_OUT"
      or . == "ACTION_REQUIRED" or . == "STARTUP_FAILURE" then "fail"
    else "pending" end;

(.reviews // []) as $rv
| (.comments // []) as $cm
| (.commits // []) as $commits
| (
    [$rv[] | select(.author.login == $me)
      | {kind: "review", at: .submittedAt, oid: (.commit.oid // null), state: (.state | ascii_downcase)}]
    + [$cm[] | select(.author.login == $me)
      | {kind: "comment", at: .createdAt, oid: null, state: null}]
    | sort_by(.at) | last
  ) as $base
| (
    if $base == null then []
    elif $base.oid != null then
      ([$commits[].oid] | index($base.oid)) as $i
      | if $i == null then [$commits[] | select(.committedDate > $base.at)] else $commits[$i + 1:] end
    else [$commits[] | select(.committedDate > $base.at)]
    end
  ) as $new_commits
| (
    if $base == null then []
    else
      [$rv[] | select(.author.login != $me and .submittedAt > $base.at)
        | {author: .author.login, kind: ("review " + (.state | ascii_downcase)), at: .submittedAt, line: (.body | first_line)}]
      + [$cm[] | select(.author.login != $me and .createdAt > $base.at)
        | {author: .author.login, kind: "comment", at: .createdAt, line: (.body | first_line)}]
      | sort_by(.at)
    end
  ) as $new_others
| ([$rv[] | select(.author.login == $me)] | sort_by(.submittedAt) | last | .state // "") as $my_review
| (($new_commits | length) + ($new_others | length)) as $new
| (
    if .state == "MERGED" then "merged"
    elif .state == "CLOSED" then "closed"
    elif $base == null or $new > 0 then "new"
    elif $my_review == "APPROVED" then "approved"
    else "submitted"
    end
  ) as $review_state
# The newest run of each check only (as GitHub shows it): a re-run or a
# run that a newer push or a concurrency group cancelled stays in the rollup.
| ([(.statusCheckRollup // [])[] | {wf: (.workflowName // ""), name: (.name // .context // "?"),
     at: (.startedAt // .createdAt // ""), o: outcome}]
   | group_by([.wf, .name]) | map(max_by(.at))) as $ci
| {
    title,
    # The author's first name in lower case (the login without a name)
    author: ((.author.name // "" | split(" ") | .[0] // "") as $f
      | if $f != "" then $f else (.author.login // "" | sub("^app/"; "") | sub("\\[bot\\]$"; "") | sub("-taktile$"; "") | sub("^taktile-"; "") | split("-")[0] | split(".")[0] | split("_")[0]) end | ascii_downcase),
    state, draft: .isDraft, decision: (.reviewDecision // ""), mergeable: (.mergeable // ""),
    branch: .headRefName, base_branch: (.baseRefName // ""), head: (.headRefOid[0:7]),
    ticket: ([(.headRefName // "" | tickets), (.title // "" | tickets), (.body // "" | tickets)] | map(first // empty) | first),
    ci: {
      pass: ([$ci[] | select(.o == "pass")] | length),
      fail: ([$ci[] | select(.o == "fail")] | length),
      pending: ([$ci[] | select(.o == "pending")] | length),
      skip: ([$ci[] | select(.o == "skip")] | length),
      cancel: ([$ci[] | select(.o == "cancel")] | length),
      failing: [$ci[] | select(.o == "fail") | .name],
      cancelled: [$ci[] | select(.o == "cancel") | .name],
      running: [$ci[] | select(.o == "pending") | .name]
    },
    base: (if $base == null then null else ($base + {at: ($base.at[0:16] | sub("T"; " "))}) end),
    new_commits: [$new_commits[] | {oid: .oid[0:7], line: .messageHeadline[0:80]}],
    new_others: [$new_others[] | . + {at: (.at[0:16] | sub("T"; " "))}],
    new: $new,
    review_state: $review_state,
    my_review: ($my_review | ascii_downcase | gsub("_"; " "))
  }
