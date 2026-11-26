# zse-ci: a GitHub PR (gh pr view --json …) → the review status summary.
# --arg me <login>. "Since my last review": after my latest review (its
# commit) or my latest comment, whichever is newer.

def first_line: (. // "" | gsub("<!--[\\s\\S]*?-->"; "") | split("\n") | map(select(test("\\S"))) | .[0] // "" | .[0:90]);
def outcome:
  ((if (.conclusion // "") != "" then .conclusion else (.state // .status // "") end) | ascii_upcase)
  | if . == "SUCCESS" or . == "NEUTRAL" then "pass"
    elif . == "SKIPPED" then "skip"
    elif . == "FAILURE" or . == "ERROR" or . == "TIMED_OUT" or . == "CANCELLED"
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
| ([(.statusCheckRollup // [])[] | {name: (.name // .context // "?"), o: outcome}]) as $ci
| {
    title, state, draft: .isDraft, decision: (.reviewDecision // ""), mergeable: (.mergeable // ""),
    branch: .headRefName, head: (.headRefOid[0:7]),
    ci: {
      pass: ([$ci[] | select(.o == "pass")] | length),
      fail: ([$ci[] | select(.o == "fail")] | length),
      pending: ([$ci[] | select(.o == "pending")] | length),
      skip: ([$ci[] | select(.o == "skip")] | length),
      failing: [$ci[] | select(.o == "fail") | .name],
      running: [$ci[] | select(.o == "pending") | .name]
    },
    base: (if $base == null then null else ($base + {at: ($base.at[0:16] | sub("T"; " "))}) end),
    new_commits: [$new_commits[] | {oid: .oid[0:7], line: .messageHeadline[0:80]}],
    new_others: [$new_others[] | . + {at: (.at[0:16] | sub("T"; " "))}],
    new: (($new_commits | length) + ($new_others | length))
  }
