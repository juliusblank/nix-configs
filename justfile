# Default recipe: show available recipes
default:
    @just --list

# --- Variables ---
aws_profile := "personal"
aws_region := "eu-central-1"
state_bucket := "juliusblank-terraform-state"
lock_table := "juliusblank-terraform-locks"
cache_bucket := "juliusblank-nix-cache"

# ==============================================================================
# Step 0: Infrastructure bootstrap
# ==============================================================================

# Create the S3 bucket and DynamoDB table for Terraform state (idempotent)
setup-terraform-backend:
    #!/usr/bin/env bash
    set -euo pipefail
    export AWS_PROFILE={{aws_profile}}
    export AWS_REGION={{aws_region}}

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

    echo "==> Terraform backend ready."

# Initialize Terraform and apply GitHub + AWS infrastructure
setup-github:
    #!/usr/bin/env bash
    set -euo pipefail
    export AWS_PROFILE={{aws_profile}}

    if [ -z "${GITHUB_TOKEN:-}" ]; then
        echo "ERROR: GITHUB_TOKEN is not set."
        echo "Create a PAT at https://github.com/settings/tokens"
        echo "Scopes needed: repo, admin:org (for OIDC), delete_repo (optional)"
        echo "Then: export GITHUB_TOKEN=ghp_..."
        exit 1
    fi

    cd terraform
    terraform init
    terraform plan -out=tfplan
    echo ""
    echo "Review the plan above. Apply? (Ctrl+C to cancel)"
    read -r
    terraform apply tfplan
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
        macbook-private|macbook-work)
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
    case "{{host}}" in
        macbook-private|macbook-work)
            darwin-rebuild switch --flake ".#{{host}}"
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

# Push built paths to S3 nix cache
push-cache host:
    #!/usr/bin/env bash
    set -euo pipefail
    export AWS_PROFILE={{aws_profile}}
    KEY_DIR="$HOME/.config/nix-cache-keys"
    nix copy --to "s3://{{cache_bucket}}?region={{aws_region}}" \
        --sign "$KEY_DIR/cache-priv-key.pem" \
        "$(readlink -f result)"

# Format all nix files
fmt:
    nixfmt .

# Update flake inputs
update:
    nix flake update

# Show diff of what would change on deploy
diff host:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{host}}" in
        macbook-private|macbook-work)
            darwin-rebuild build --flake ".#{{host}}"
            nix store diff-closures /run/current-system ./result
            ;;
        *)
            echo "Diff not yet implemented for {{host}}"
            ;;
    esac

# ==============================================================================
# Terraform
# ==============================================================================

# Run terraform plan
tf-plan:
    #!/usr/bin/env bash
    set -euo pipefail
    export AWS_PROFILE={{aws_profile}}
    cd terraform && terraform plan

# Run terraform apply
tf-apply:
    #!/usr/bin/env bash
    set -euo pipefail
    export AWS_PROFILE={{aws_profile}}
    cd terraform && terraform apply
