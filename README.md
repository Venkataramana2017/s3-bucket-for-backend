# S3 bucket with Terraform

Creates one S3 bucket named `bucket-backend-terraform` in account
`313932316713`, region `us-east-1`, by default.

Versioning, AES256 server-side encryption, all four public-access blocks and
bucket-owner-enforced ownership (ACLs disabled) are enabled. Tags record the
name, environment and Terraform management. Forced deletion of bucket contents
is disabled; destroying a non-empty bucket will fail.

## Configure and deploy

Requires Terraform >= 1.10 and < 2.0 and an authenticated AWS CLI profile with S3
bucket management permissions. Defaults are in `variables.tf`. Optionally copy
`terraform.tfvars.example` to `terraform.tfvars` and edit it. Never store AWS
credentials in these files. Set `aws_profile = null` to use role/environment
credentials. The provider restricts deployment to the configured account.

```powershell
aws sts get-caller-identity --profile default
.tools/terraform.exe init
.tools/terraform.exe fmt -check
.tools/terraform.exe validate
.tools/terraform.exe plan '-out=s3.tfplan'
.tools/terraform.exe apply s3.tfplan
.tools/terraform.exe output
```

Use `terraform` if installed on PATH; `.tools/terraform.exe` is the workspace-local
copy. The plan creates one bucket and four configuration resources for that same
bucket. The name must be globally unique. If it is taken, choose another before
applying. Import existing unmanaged resources before attempting to manage them.

## State and dependencies

Commit `.terraform.lock.hcl` to preserve the provider version. State, plans,
local tooling and variable overrides are ignored. Preserve `terraform.tfstate`:
it tracks deployed resources. Subsequent plans should show no changes. Deleting
state can make Terraform try to recreate an existing bucket.

## GitHub Actions

Pushes to `main`, `feature*` and `deve*` run formatting, validation and command authorization tests.
PRs also run a plan automatically. In the PR Conversation comment box, repository
writers can post `/plan`, `/apply` or `/destroy` to run the corresponding operation.
With the required `terraform-execution` status enabled on `main`, a PR can merge
only after `/apply` or `/destroy` succeeds for its current commit. A plan alone
does not unlock merging. New commits require another successful execution.
See [GitHub Actions setup](docs/github-actions.md) for the separate state bucket,
OIDC roles, state migration and required GitHub variables before enabling CI.
