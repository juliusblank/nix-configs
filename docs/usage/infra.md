# Infrastructure Usage

This document covers day-to-day use of the OpenTofu infrastructure — editing and applying
changes to AWS and GitHub resources managed in `terraform/`.

OpenTofu uses a two-step workflow: **plan** (evaluate what would change, save to a file) then
**apply** (execute exactly what was in the saved plan). This keeps apply deterministic — no
re-evaluation happens at apply time, so what you reviewed is exactly what runs.

Credentials are injected automatically from 1Password by the `just` recipes — no manual
`export AWS_ACCESS_KEY_ID=...` is needed.

## One-time bootstrap: 1Password Service Account for CI

The infra CI workflow fetches the GitHub PAT live from 1Password on every run using a
**1Password Service Account** — a non-human credential scoped to a specific vault. This means
PAT rotation in 1Password is picked up automatically by the next CI run, with no manual secret
update in GitHub.

The service account token itself is stored as a GitHub Actions secret (`OP_SERVICE_ACCOUNT_TOKEN`)
and managed by terraform going forward. The steps below are only needed once, on first setup or
after re-creating the service account.

### Step 1 — Create the service account in 1Password

1. Go to **1Password.com → Settings → Developer → Service Accounts**
2. Click **New Service Account** — name it `github-actions-nix-configs`
3. Grant it **read access** to the `github_nix-configs` vault only
4. Copy the token (it is shown only once)

### Step 2 — Save the token to 1Password

Store the token as a 1Password item so it can be injected by the justfile:

```bash
op item create \
  --vault Private \
  --category "API Credential" \
  --title "1Password SA github-actions-nix-configs" \
  token=<paste token here>
```

### Step 3 — Provision the GitHub Actions secret via terraform

Run the standard plan/apply cycle — terraform will create the `OP_SERVICE_ACCOUNT_TOKEN`
secret in GitHub Actions from the value now in 1Password:

```bash
just tf-plan   # review — expect one new github_actions_secret
just tf-apply
```

From this point on, rotating the service account token is the same process: update the item
in 1Password, then run `just tf-plan && just tf-apply`.

## Standard workflow (from `main`)

The default path for planned infrastructure changes: edit on a branch, merge, then plan and
apply on `main`.

### 1. Create a branch

```bash
git checkout -b feat/infra-add-s3-logging
```

### 2. Edit Terraform files

Infrastructure definitions live in `terraform/`. One file per concern:

| File | What it manages |
|---|---|
| `github.tf` | GitHub repository settings and branch protection |
| `oidc.tf` | AWS OIDC provider and GitHub Actions IAM role |
| `s3-cache.tf` | S3 bucket for the nix binary cache |
| `variables.tf` | Input variable declarations |
| `outputs.tf` | Output value declarations |
| `providers.tf` | Provider and backend configuration |

Always format and validate after editing:

```bash
cd terraform
tofu fmt
tofu validate
```

### 3. Commit and open a PR

```bash
git add terraform/
git commit -m "feat(infra): enable S3 access logging on nix-cache bucket"
git push -u origin feat/infra-add-s3-logging
gh pr create --fill
```

CI automatically runs `tofu plan` and posts the output as a collapsible comment on the PR.
Review it there — no local plan step needed.

### 4. Merge and let CI apply

After the PR is squash-merged into `main`, the infra workflow runs `tofu plan` followed by
`tofu apply` automatically. No manual step required.

If you need to verify state after an automated apply, check the Actions run in GitHub.

### Manual plan/apply (optional)

You can still run plan and apply locally if needed — for example, to preview changes before
pushing, or to recover from a failed CI run:

```bash
git checkout main && git pull

# Generate the plan and save it to terraform/tfplan
just tf-plan

# Review the output, then apply exactly the saved plan
just tf-apply
```

`tf-apply` will error out if no plan file exists, preventing accidental applies without a
reviewed plan.

## Branch workflow (fixing infra issues)

Sometimes you need to test or apply an infrastructure fix directly from a feature branch —
for example, to unblock a broken CI pipeline or fix a misconfigured resource that cannot wait
for a full PR cycle.

The `tf-apply` guardrails allow this when the working tree is clean (all changes committed),
but require explicit confirmation.

### When to use this

- Fixing a broken resource that is blocking other work
- Testing an infrastructure change in isolation before writing a PR
- Recovering from a partially-applied or failed apply

### Example: fixing a broken branch protection rule from a branch

```bash
# Make and commit the fix on a branch
git checkout -b fix/infra-branch-protection
# ... edit terraform/github.tf ...
tofu fmt && tofu validate
git add terraform/github.tf
git commit -m "fix(infra): restore require-pr-reviews rule on main"

# Plan from the branch — tf-plan warns but proceeds
just tf-plan
```

Output:
```
WARNING: planning from branch 'fix/infra-branch-protection', not main.

OpenTofu will perform the following actions:
  ...
Plan: 1 to change.

Saved the plan to: tfplan
```

Review the plan, then apply:

```bash
just tf-apply
```

Output:
```
WARNING: applying from branch 'fix/infra-branch-protection', not main.
Press Enter to continue or Ctrl+C to abort.

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

`tf-apply` requires a clean working tree when not on `main`. If there are uncommitted changes
it will refuse:

```
ERROR: cannot apply from branch 'fix/infra-branch-protection' with a dirty working tree.
Commit or stash all changes before running tf-apply outside main.
```

After a successful branch apply, open and merge the PR as normal so `main` stays in sync with
actual infrastructure state.

## Importing existing resources

If a resource already exists in AWS or GitHub and needs to be brought under OpenTofu management:

```bash
just tf-import <resource_address> <resource_id>
```

Examples:

```bash
# Import an existing GitHub repository
just tf-import github_repository.nix_configs nix-configs

# Import an existing S3 bucket
just tf-import aws_s3_bucket.nix_cache juliusblank-nix-cache
```

After importing, run `just tf-plan` to confirm OpenTofu sees no diff between the imported
state and the current `.tf` definition. If there is a diff, update the `.tf` file to match
actual resource configuration before applying.

## Quick reference

```bash
just tf-plan                          # plan and save to terraform/tfplan
just tf-apply                         # apply saved plan, then delete it
just tf-import <resource> <id>        # import existing resource into state

cd terraform && tofu fmt              # format .tf files
cd terraform && tofu validate         # validate configuration structure
```
