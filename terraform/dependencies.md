# terraform/ — External Dependencies

Data sources and remote state references that reach outside this OpenTofu root module.
Every cross-project dependency must have a row in this table.

| Resource | Type | Source project / account | Purpose | Added |
|---|---|---|---|---|

<!-- Add rows in this format:
| `data.aws_caller_identity.current` | data source | AWS account 123456789 | Fetch current account ID for ARN construction | 2025-04-18 |
| `data.terraform_remote_state.network` | remote state | infra/network | Read VPC and subnet IDs | 2025-04-18 |
-->
