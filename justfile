# Default recipe: show available recipes
default:
    @just --list

# --- Variables ---
aws_region := "eu-central-1"
state_bucket := "juliusblank-terraform-state"
lock_table := "juliusblank-terraform-locks"
cache_bucket := "juliusblank-nix-cache"

# ==============================================================================
# Step 0: Infrastructure bootstrap
# ==============================================================================

# Create the S3 bucket and DynamoDB table for OpenTofu state (idempotent)
setup-terraform-backend:
    #!/usr/bin/env bash
    set -euo pipefail
    export AWS_ACCESS_KEY_ID=$(op read "op://Private/AWS Personal/access_key_id")
    export AWS_SECRET_ACCESS_KEY=$(op read "op://Private/AWS Personal/secret_access_key")
    export AWS_DEFAULT_REGION={{aws_region}}

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

# Initialize OpenTofu and apply GitHub + AWS infrastructure
setup-github:
    #!/usr/bin/env bash
    set -euo pipefail
    AWS_ACCESS_KEY_ID=$(op read "op://Private/AWS Personal/access_key_id")
    AWS_SECRET_ACCESS_KEY=$(op read "op://Private/AWS Personal/secret_access_key")
    TF_VAR_github_token=$(op read "op://github_nix-configs/GitHub PAT nix-configs/token")
    TF_VAR_op_service_account_token=$(op read "op://Private/1Password SA github-actions-nix-configs/token")
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TF_VAR_github_token TF_VAR_op_service_account_token
    export AWS_DEFAULT_REGION={{aws_region}}

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

# Check the flake evaluates correctly
check:
    nix flake check

# Build a specific host config without activating
build host:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{host}}" in
        serenity|macbook-work)
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

# Build and activate a host config
deploy host:
    #!/usr/bin/env bash
    set -euo pipefail
    branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$branch" != "main" ]; then
        echo "WARNING: deploying from branch '$branch', not main."
    fi
    case "{{host}}" in
        serenity|macbook-work)
            sudo darwin-rebuild switch --flake ".#{{host}}"
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
    export AWS_ACCESS_KEY_ID=$(op read "op://Private/AWS Personal/access_key_id")
    export AWS_SECRET_ACCESS_KEY=$(op read "op://Private/AWS Personal/secret_access_key")
    export AWS_DEFAULT_REGION={{aws_region}}
    KEY_DIR="$HOME/.config/nix-cache-keys"
    store_path=$(nix build --no-link --print-out-paths ".#darwinConfigurations.{{host}}.system")
    nix store sign --key-file "$KEY_DIR/cache-priv-key.pem" --recursive "$store_path"
    nix copy --to "s3://{{cache_bucket}}?region={{aws_region}}" "$store_path"

# Format all nix files
fmt:
    find . -name '*.nix' -not -path './.direnv/*' | xargs nixfmt

# Update flake inputs
update:
    nix flake update

# Show diff of what would change on deploy
diff host:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{host}}" in
        serenity|macbook-work)
            darwin-rebuild build --flake ".#{{host}}"
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
    AWS_ACCESS_KEY_ID=$(op read "op://Private/AWS Personal/access_key_id")
    AWS_SECRET_ACCESS_KEY=$(op read "op://Private/AWS Personal/secret_access_key")
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
    export AWS_DEFAULT_REGION={{aws_region}}
    cd terraform && tofu force-unlock -force {{lock_id}}

# Import an existing resource into tofu state
# Usage: just tf-import <resource> <id>
# Example: just tf-import github_repository.nix_configs nix-configs
tf-import resource id:
    #!/usr/bin/env bash
    set -euo pipefail
    AWS_ACCESS_KEY_ID=$(op read "op://Private/AWS Personal/access_key_id")
    AWS_SECRET_ACCESS_KEY=$(op read "op://Private/AWS Personal/secret_access_key")
    TF_VAR_github_token=$(op read "op://github_nix-configs/GitHub PAT nix-configs/token")
    TF_VAR_op_service_account_token=$(op read "op://Private/1Password SA github-actions-nix-configs/token")
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TF_VAR_github_token TF_VAR_op_service_account_token
    export AWS_DEFAULT_REGION={{aws_region}}
    cd terraform && tofu import {{resource}} {{id}}

# Run tofu plan
tf-plan:
    #!/usr/bin/env bash
    set -euo pipefail

    # Assign before export: `export VAR=$(cmd)` swallows the exit code of cmd,
    # so a failed op read would silently set an empty variable.
    AWS_ACCESS_KEY_ID=$(op read "op://Private/AWS Personal/access_key_id")
    AWS_SECRET_ACCESS_KEY=$(op read "op://Private/AWS Personal/secret_access_key")
    TF_VAR_github_token=$(op read "op://github_nix-configs/GitHub PAT nix-configs/token")
    TF_VAR_op_service_account_token=$(op read "op://Private/1Password SA github-actions-nix-configs/token")
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TF_VAR_github_token TF_VAR_op_service_account_token
    export AWS_DEFAULT_REGION={{aws_region}}

    branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$branch" != "main" ]; then
        echo "WARNING: planning from branch '$branch', not main."
    fi

    cd terraform && tofu plan -out=tfplan

# Run tofu apply
tf-apply:
    #!/usr/bin/env bash
    set -euo pipefail
    AWS_ACCESS_KEY_ID=$(op read "op://Private/AWS Personal/access_key_id")
    AWS_SECRET_ACCESS_KEY=$(op read "op://Private/AWS Personal/secret_access_key")
    TF_VAR_github_token=$(op read "op://github_nix-configs/GitHub PAT nix-configs/token")
    TF_VAR_op_service_account_token=$(op read "op://Private/1Password SA github-actions-nix-configs/token")
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TF_VAR_github_token TF_VAR_op_service_account_token
    export AWS_DEFAULT_REGION={{aws_region}}

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
