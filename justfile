# Default recipe: show available recipes
default:
    @just --list

# --- Variables ---
aws_region := "eu-central-1"
state_bucket := "juliusblank-terraform-state"
lock_table := "juliusblank-terraform-locks"
cache_bucket := "juliusblank-nix-cache"
# Keep in sync with `inputs.nix-darwin` in flake.nix (branch / tag).
nix_darwin_flake := "github:nix-darwin/nix-darwin/nix-darwin-26.05"

# ==============================================================================
# Step 0: Infrastructure bootstrap
# ==============================================================================

# Create the S3 bucket and DynamoDB table for OpenTofu state (idempotent)
setup-terraform-backend:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Creating S3 bucket for Terraform state..."
    if aws s3api head-bucket --bucket {{state_bucket}} 2>/dev/null; then
        echo "    Bucket {{state_bucket}} already exists, skipping."
    else
        aws s3api create-bucket \
            --bucket {{state_bucket}} \
            --region {{aws_region}} \
            --create-bucket-configuration LocationConstraint={{aws_region}}
        aws s3api put-bucket-versioning \
            --bucket {{state_bucket}} \
            --versioning-configuration Status=Enabled
        aws s3api put-public-access-block \
            --bucket {{state_bucket}} \
            --public-access-block-configuration \
                BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
        echo "    Bucket {{state_bucket}} created."
    fi

    echo "==> Creating DynamoDB table for state locking..."
    if aws dynamodb describe-table --table-name {{lock_table}} --region {{aws_region}} 2>/dev/null; then
        echo "    Table {{lock_table}} already exists, skipping."
    else
        aws dynamodb create-table \
            --table-name {{lock_table}} \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            --region {{aws_region}}
        echo "    Table {{lock_table}} created."
    fi

    echo "==> OpenTofu backend ready."
    echo "==> Next step: run 'just tf-import-backend' to bring these resources under tofu management."

# Import the state S3 bucket and DynamoDB lock table into tofu state.
# Run once after `just setup-terraform-backend` to hand ownership to tofu.
# Safe to re-run — tofu import is idempotent for already-imported resources.
tf-import-backend:
    #!/usr/bin/env bash
    set -euo pipefail
    TF_VAR_github_token=$(op read "op://github_nix-configs/GitHub PAT nix-configs/token")
    TF_VAR_op_service_account_token=$(op read "op://infrastructure/github-actions-nix-configs/token")
    export TF_VAR_github_token TF_VAR_op_service_account_token

    echo "==> Importing state backend resources into tofu..."
    cd terraform
    tofu import aws_s3_bucket.terraform_state            {{state_bucket}}
    tofu import aws_s3_bucket_versioning.terraform_state {{state_bucket}}
    tofu import aws_s3_bucket_public_access_block.terraform_state {{state_bucket}}
    tofu import aws_dynamodb_table.terraform_locks        {{lock_table}}
    echo "==> Import complete. Run 'just tf-plan' to confirm no unexpected drift."

# Import the nix-configs-infra IAM user into tofu state.
# Run once to hand ownership to tofu. After applying, remove any legacy inline
# policies that were attached manually before this resource was managed by tofu.
tf-import-user:
    #!/usr/bin/env bash
    set -euo pipefail
    TF_VAR_github_token=$(op read "op://github_nix-configs/GitHub PAT nix-configs/token")
    TF_VAR_op_service_account_token=$(op read "op://infrastructure/github-actions-nix-configs/token")
    export TF_VAR_github_token TF_VAR_op_service_account_token

    echo "==> Importing nix-configs-infra IAM user into tofu..."
    cd terraform
    tofu import aws_iam_user.nix_configs_infra nix-configs-infra
    echo "==> Import complete. Run 'just tf-plan' then 'just tf-apply' to create the tofu-access policy."
    echo "==> Then remove any legacy inline policies from the user in the AWS console."

# Initialize OpenTofu and apply GitHub + AWS infrastructure
setup-github:
    #!/usr/bin/env bash
    set -euo pipefail
    TF_VAR_github_token=$(op read "op://github_nix-configs/GitHub PAT nix-configs/token")
    TF_VAR_op_service_account_token=$(op read "op://infrastructure/github-actions-nix-configs/token")
    export TF_VAR_github_token TF_VAR_op_service_account_token

    cd terraform
    tofu init
    tofu plan -out=tfplan
    echo ""
    echo "Review the plan above. Apply? (Ctrl+C to cancel)"
    read -r
    tofu apply tfplan
    rm tfplan

# Generate a nix cache signing key pair (run once)
setup-nix-cache-keys:
    #!/usr/bin/env bash
    set -euo pipefail
    KEY_DIR="$HOME/.config/nix-cache-keys"
    mkdir -p "$KEY_DIR"

    if [ -f "$KEY_DIR/cache-priv-key.pem" ]; then
        echo "Signing keys already exist in $KEY_DIR, skipping."
    else
        nix key generate-secret --key-name juliusblank-nix-cache > "$KEY_DIR/cache-priv-key.pem"
        nix key convert-secret-to-public < "$KEY_DIR/cache-priv-key.pem" > "$KEY_DIR/cache-pub-key.pem"
        echo "Keys generated in $KEY_DIR"
        echo "Public key (add to nix.settings.trusted-public-keys):"
        cat "$KEY_DIR/cache-pub-key.pem"
    fi

# ==============================================================================
# Day-to-day operations
# ==============================================================================

# Show the active generation, HEAD drift, and what each host runs (GitHub Deployments)
status:
    #!/usr/bin/env bash
    set -euo pipefail
    profile=/nix/var/nix/profiles/system
    active_gen=$(readlink "$profile" | grep -o '[0-9]*')
    # GNU stat first: the devShell puts coreutils on PATH, and GNU `stat -f`
    # means "file system status", which succeeds with unrelated output.
    activated=$(stat --format="%y" "$profile" 2>/dev/null | cut -d. -f1 \
                || stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$profile" 2>/dev/null)
    echo "Host:       $(hostname -s)"
    echo "Generation: $active_gen  (system activated $activated)"
    echo "Version:    $(cat /run/current-system/darwin-version 2>/dev/null)"
    if command -v darwin-version >/dev/null; then
        echo "Revision:   $(darwin-version --json | jq -r '.configurationRevision // "unknown"' | cut -c1-12)"
    fi
    echo ""
    if [[ -f .deploy-status ]]; then
        # shellcheck source=/dev/null
        source .deploy-status
        echo "Last deploy: generation $generation  commit $commit ($branch)  $deployed_at"
        head_commit=$(git rev-parse --short HEAD)
        head_branch=$(git rev-parse --abbrev-ref HEAD)
        if [[ "$commit" == "$head_commit" ]]; then
            echo "             HEAD matches — nothing to deploy"
        else
            echo "             HEAD is $head_commit ($head_branch) — run 'just deploy <host>' to update"
        fi
    else
        echo "Last deploy: no record yet — run 'just deploy <host>' to create one"
    fi
    echo ""
    echo "Latest commit on main:"
    git log main --oneline -1 2>/dev/null || echo "  (not in a git repo)"
    echo ""
    # GitHub Deployments, written by `just deploy`. Compare with the
    # Revision line above to spot deploys that bypassed the recipe.
    echo "GitHub deployments:"
    for host in serenity concinnity; do
        gh api "repos/{owner}/{repo}/deployments?environment=$host&per_page=1" \
          --jq "if length == 0 then \"  $host\t(no record)\" else .[0] | \"  $host\t\(.sha[0:7])  \(.created_at)  \(.description)\" end" \
          2>/dev/null || echo "  $host: (gh lookup failed)"
    done

# Check the flake evaluates correctly
check:
    nix flake check

# Build a specific host config without activating
build host:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{host}}" in
        serenity|concinnity)
            nix build ".#darwinConfigurations.{{host}}.system"
            ;;
        pi-*)
            nix build ".#nixosConfigurations.{{host}}.config.system.build.toplevel"
            ;;
        *)
            echo "Unknown host: {{host}}"
            exit 1
            ;;
    esac

# Deploy without REF uses the current checkout. With REF, the recipe checks out
# that tag / branch / SHA detached (`release` = newest `v*` tag), deploys it, and
# switches back afterwards, also on failure. Everything after the checkout runs
# inline (no nested `just` calls), because an older tag may carry an older justfile.
# Build and activate a host config (REF: empty = checkout, `release`, tag, branch or SHA)
deploy host ref="":
    #!/usr/bin/env bash
    set -euo pipefail
    ref="{{ref}}"
    if [ -n "$ref" ]; then
        if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
            echo "ERROR: uncommitted changes. Commit or stash them before deploying a ref."
            exit 1
        fi
        git fetch --quiet --tags origin
        if [ "$ref" = "release" ]; then
            ref=$(git tag --list 'v*' --sort=-v:refname | head -1)
            [ -n "$ref" ] || { echo "ERROR: no release tags found."; exit 1; }
        fi
        # A branch REF deploys the just-fetched remote branch, not a possibly stale local one.
        target=$ref ref_branch=""
        if git show-ref --verify --quiet "refs/remotes/origin/$ref"; then
            target="origin/$ref" ref_branch=$ref
        fi
        prev=$(git symbolic-ref --quiet --short HEAD || git rev-parse HEAD)
        trap 'git switch --quiet "$prev" 2>/dev/null || git switch --quiet --detach "$prev"; echo "Back on $prev."' EXIT
        git switch --quiet --detach "$target"
        echo "Deploying $target ($(git rev-parse --short HEAD))"
    fi

    # What is being deployed, for the warning, .deploy-status and GitHub.
    sha=$(git rev-parse HEAD)
    if tag=$(git describe --exact-match --tags HEAD 2>/dev/null); then
        label="release $tag"
    elif [ -n "${ref_branch:-}" ]; then
        label="branch $ref_branch"
    elif b=$(git symbolic-ref --quiet --short HEAD); then
        label="branch $b"
    else
        label="commit ${sha:0:7}"
    fi
    case "$label" in
        "branch main" | release\ *) ;;
        *) echo "WARNING: deploying $label, not main or a release tag." ;;
    esac

    # Record the deploy as a GitHub Deployment (environment = host): the repo
    # sidebar shows the SHA each host runs; PRs show "deployed to <host>".
    # Best effort: the caller only warns on failure.
    record_deployment() {
        local gen=$1 desc id
        desc="$label, generation $gen"
        if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
            desc="$desc, DIRTY tree (uncommitted changes not in ${sha:0:7})"
        fi
        # GitHub can only attach a deployment to a commit it knows.
        if [ -z "$(git branch -r --contains "$sha" 2>/dev/null)" ]; then
            echo "Skipping GitHub deployment: ${sha:0:7} is not pushed."
            return 1
        fi
        id=$(jq -n --arg ref "$sha" --arg env "{{host}}" --arg desc "$desc" \
            '{ref: $ref, environment: $env, description: $desc, auto_merge: false, required_contexts: [], production_environment: true}' \
          | gh api --method POST 'repos/{owner}/{repo}/deployments' --input - --jq .id) || return 1
        jq -n --arg desc "$desc" '{state: "success", description: $desc, auto_inactive: true}' \
          | gh api --method POST "repos/{owner}/{repo}/deployments/$id/statuses" --input - --silent || return 1
        echo "GitHub deployment $id recorded: {{host}} → ${sha:0:7} ($label)"
    }

    case "{{host}}" in
        serenity|concinnity)
            # Non-interactive bash: no `darwin-rebuild` on PATH. New nix-darwin requires root
            # for `switch`. Resolve the store path, then `sudo` that binary (not `sudo
            # darwin-rebuild` — macOS secure_path would not find it).
            # Zellij keeps sessions per version: after a version change the new client
            # no longer sees sessions of the old server (zse lists them as stopped). So
            # when this deploy changes the Zellij version, offer to stop the running
            # sessions first (old zellij still works now) and restore them after.
            # Plain strings, not arrays: must also run under macOS /bin/bash 3.2 with set -u.
            restore_sessions=""
            cur_zj=$(zellij --version 2>/dev/null | awk '{print $2}' || true)
            new_zj=$(nix eval --raw ".#darwinConfigurations.{{host}}.config.home-manager.users.\"$(id -un)\".programs.zellij.package.version" 2>/dev/null || true)
            if [ -n "$cur_zj" ] && [ -n "$new_zj" ] && [ "$cur_zj" != "$new_zj" ]; then
                running=$(zellij list-sessions --short --no-formatting 2>/dev/null | tr '\n' ' ' || true)
                if [ -n "${running// /}" ]; then
                    echo "Zellij $cur_zj → $new_zj: running sessions: $running"
                    if [ -n "${ZELLIJ:-}" ]; then
                        echo "  You are inside Zellij; stopping would end this deploy. Run it from a"
                        echo "  terminal outside Zellij, or answer N and handle sessions by hand"
                        echo "  (docs/usage/nix-system.md, Known issues)."
                    fi
                    ans=""
                    read -r -p "Stop them now and restore them after the deploy? [y/N] " ans < /dev/tty || true
                    if [ "$ans" = y ] && [ -z "${ZELLIJ:-}" ]; then
                        for s in $running; do
                            [ -f "$HOME/.local/state/zse/sessions/$s" ] \
                              || echo "  $s is not registered in zse; it will not be restored."
                            zellij kill-session "$s" && restore_sessions="$restore_sessions $s"
                        done
                    fi
                fi
            fi
            drb=$(nix build --no-link --print-out-paths "{{nix_darwin_flake}}#darwin-rebuild")
            sudo "$drb/bin/darwin-rebuild" switch --flake ".#{{host}}"
            if [ -n "$restore_sessions" ]; then
                # zse is a zsh function; an interactive zsh loads the new one.
                zsh -ic "zse restore$restore_sessions" || echo "WARNING: zse restore failed; run: zse restore"
            fi
            gen=$(readlink /nix/var/nix/profiles/system | grep -o '[0-9]*')
            # %q: `status` sources this file, and the label contains spaces.
            printf 'host=%q\ncommit=%q\nbranch=%q\ngeneration=%q\ndeployed_at=%q\n' \
              "{{host}}" \
              "${sha:0:7}" \
              "$label" \
              "$gen" \
              "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
              > .deploy-status
            echo "Deploy recorded in .deploy-status (generation $gen)"
            record_deployment "$gen" || echo "WARNING: GitHub deployment record failed (deploy itself succeeded)."
            ;;
        pi-*)
            echo "For remote NixOS hosts, use:"
            echo "  nixos-rebuild switch --flake .#{{host}} --target-host {{host}} --use-remote-sudo"
            ;;
        *)
            echo "Unknown host: {{host}}"
            exit 1
            ;;
    esac

# Push the full closure of a built host config to the S3 nix cache
push-cache host:
    #!/usr/bin/env bash
    set -euo pipefail
    KEY_DIR="$HOME/.config/nix-cache-keys"
    store_path=$(nix build --no-link --print-out-paths ".#darwinConfigurations.{{host}}.system")
    nix store sign --key-file "$KEY_DIR/cache-priv-key.pem" --recursive "$store_path"
    nix copy --to "s3://{{cache_bucket}}?region={{aws_region}}" "$store_path"

# Delete unreachable store paths and all old generations
gc:
    nix-collect-garbage -d

# Format all nix files
fmt:
    find . -name '*.nix' -not -path './.direnv/*' | xargs nixfmt

# Lint all nix files
lint:
    statix check .

# Auto-fix statix lint findings
lint-fix:
    statix fix .

# Preview or regenerate CHANGELOG.md locally (canonical release path is the GitHub release workflow)
changelog:
    git-cliff --output CHANGELOG.md

# Update flake inputs
update:
    nix flake update

# Show diff of what would change on deploy
diff host:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{host}}" in
        serenity|concinnity)
            nix run "{{nix_darwin_flake}}#darwin-rebuild" -- build --flake ".#{{host}}"
            nix store diff-closures /run/current-system ./result
            ;;
        *)
            echo "Diff not yet implemented for {{host}}"
            ;;
    esac

# ==============================================================================
# OpenTofu
# ==============================================================================

# Force-unlock a stuck OpenTofu state lock
# Usage: just tf-unlock <lock-id>
# Lock ID is printed when a plan/apply fails due to an existing lock.
tf-unlock lock_id:
    #!/usr/bin/env bash
    set -euo pipefail
    cd terraform && tofu force-unlock -force {{lock_id}}

# Import an existing resource into tofu state
# Usage: just tf-import <resource> <id>
# Example: just tf-import github_repository.nix_configs nix-configs
tf-import resource id:
    #!/usr/bin/env bash
    set -euo pipefail
    TF_VAR_github_token=$(op read "op://github_nix-configs/GitHub PAT nix-configs/token")
    TF_VAR_op_service_account_token=$(op read "op://infrastructure/github-actions-nix-configs/token")
    export TF_VAR_github_token TF_VAR_op_service_account_token
    cd terraform && tofu import {{resource}} {{id}}

# Run tofu plan
tf-plan:
    #!/usr/bin/env bash
    set -euo pipefail

    # Assign before export: `export VAR=$(cmd)` swallows the exit code of cmd,
    # so a failed op read would silently set an empty variable.
    TF_VAR_github_token=$(op read "op://github_nix-configs/GitHub PAT nix-configs/token")
    TF_VAR_op_service_account_token=$(op read "op://infrastructure/github-actions-nix-configs/token")
    export TF_VAR_github_token TF_VAR_op_service_account_token

    branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$branch" != "main" ]; then
        echo "WARNING: planning from branch '$branch', not main."
    fi

    cd terraform && tofu plan -out=tfplan

# Run tofu apply
tf-apply:
    #!/usr/bin/env bash
    set -euo pipefail
    TF_VAR_github_token=$(op read "op://github_nix-configs/GitHub PAT nix-configs/token")
    TF_VAR_op_service_account_token=$(op read "op://infrastructure/github-actions-nix-configs/token")
    export TF_VAR_github_token TF_VAR_op_service_account_token

    branch=$(git rev-parse --abbrev-ref HEAD)

    if [ "$branch" != "main" ]; then
        if [ -n "$(git status --porcelain)" ]; then
            echo "ERROR: cannot apply from branch '$branch' with a dirty working tree."
            echo "Commit or stash all changes before running tf-apply outside main."
            exit 1
        fi
        echo "WARNING: applying from branch '$branch', not main."
        echo "Press Enter to continue or Ctrl+C to abort."
        read -r
    fi

    if [ ! -f terraform/tfplan ]; then
        echo "ERROR: no plan file found. Run 'just tf-plan' first."
        exit 1
    fi

    cd terraform && tofu apply tfplan && rm tfplan
