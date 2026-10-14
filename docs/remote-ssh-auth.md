# Remote SSH auth + commit signing — options

**Status:** open. Sync pending with IT, Matei and Robin (SPEC roadmap row 29).
No decision is made yet; this page records the options and trade-offs.

## Problem

On concinnity, GitHub SSH auth and commit signing both go through the
1Password SSH agent. When I work remotely (Claude Code Remote Control from
my phone), the Mac screen is locked, 1Password locks with it, and every
agent request waits for an unlock prompt I cannot see. Git then fails with
`1Password: failed to fill whole buffer`.

Requirements:

- Works while I am away from the Mac (no physical touch, no Mac-side prompt).
- Security close to today's setup: keys cannot be copied off the machine,
  and access is scoped as tightly as possible.
- Covers both **auth** (clone / push) and **signing** (verified commits).

## Options

### A. 1Password, kept unlocked

- 1Password → Settings → Security: turn off "lock on screen lock / sleep",
  longer auto-lock.
- Developer → SSH agent: "Remember key approval" until 1Password locks.
- Scope the agent: put the key in a dedicated vault and list only that item
  in `~/.config/1password/ssh/agent.toml` (already managed in
  `hosts/concinnity/home.nix`).

Limits: the agent scope narrows what the *agent* offers, but unlock is
account-wide — every vault stays decrypted while the app is unlocked. The
`op` CLI still asks for per-session approval on the Mac. Updates and
restarts relock the app, so the failure mode can come back.

### B. Secretive (Mac Secure Enclave), no-auth policy

[Secretive](https://github.com/maxgoedjen/secretive) creates keys inside the
Secure Enclave. With the "no authentication required" policy the key works
whenever my user session runs; there is nothing to unlock.

- The key can never leave the chip, not even for root-level malware.
- Malware running as me can *use* it silently.
- Bound to one Mac; losing the Mac loses the key (register a second key).
- To verify: does the key stay usable while the screen is locked?

There is no "approve on iPhone" path for Secure Enclave keys. Approval
options are Touch ID, an Apple Watch near the Mac, or the Mac password.

### C. YubiKey FIDO key (`ed25519-sk`)

`ssh-keygen -t ed25519-sk -O resident -O verify-required`. The key lives
on the YubiKey; each use needs PIN + touch.

- Strongest option: malware on the Mac cannot use the key without a touch.
- **Does not work remotely** — needs the YubiKey plugged in and touched.
- No maintained phone-based equivalent exists (Krypton was the classic
  "approve SSH on phone" app; it is no longer maintained for general SSH).

### D. Split roles: signing-only key + HTTPS fine-grained PAT for push

- **Signing:** a dedicated GitHub *signing* key (via A or B). Signing keys
  grant no access; the blast radius is "can make commits look like mine".
- **Push:** HTTPS with a fine-grained PAT instead of an SSH auth key —
  per repo, `contents: write` + `pull_requests: write`, with expiry. Stored
  in 1Password, injected via `op read` (same pattern as `GH_TOKEN`).
- **Merge:** GitHub mobile app + branch protection, so a misused token
  can push branches but cannot ship to `main`.

Caveats: one fine-grained PAT per resource owner (`taktile-org` and
personal). `taktile-org` admins may need to approve fine-grained tokens.

### E. Stop signing

`commit.gpgsign = false`. Push auth still proves who pushed, but commits
show "Unverified" and lose cryptographic attestation. Listed for
completeness only.

## Comparison

| | A. 1P unlocked | B. Secretive | C. YubiKey | D. Split (sig key + PAT) |
|---|---|---|---|---|
| Works remotely | Yes (until relock) | Yes | **No** | Yes |
| Key can be copied | Hard (root memory dump) | **Never** | **Never** | Signing key: per A/B; PAT is a bearer token |
| Malware as me can use it | Yes | Yes, silently | **No** (touch) | Yes, within PAT scope |
| Blast radius | Whole account unlocked | One key | One key | Per-repo, expiring |
| Portable across Macs | Yes (synced) | No | Yes | Yes |
| Setup effort | Settings toggles | New app + keys | New keys | Keys + tokens + org approval |
| Reliability | Relocks on update/restart | Stable | Stable | Stable |

## GitHub key types

| Type | Access |
|---|---|
| Account SSH key | Everything the account can do, read **and** write. Cannot be scoped. |
| Deploy key | One repo, optionally read-only. Awkward across many repos. |
| Signing key | No access; only verifies commit signatures. |

Pushing commits made on the Mac needs write access from the Mac — the
GitHub mobile app can merge PRs but cannot push local commits.

## Current leaning (pre-sync)

Split setup: **D** for GitHub (signing key in Secure Enclave via **B**,
fine-grained PAT for push), **C** (YubiKey) kept for high-value access
(prod hosts, AWS), 1Password stays locked normally.

## Questions for the sync

- Is Secretive (third-party, open source) acceptable on managed Macs?
- Does `taktile-org` allow / require approval for fine-grained PATs?
- Org policy on unattended keys and on keeping 1Password unlocked.
- Is there a company-standard approach for remote / unattended dev work?
