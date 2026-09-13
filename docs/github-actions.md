# Terraform through PRs

Pushes to `main`, `freatue*` and `deve*` trigger formatting,
Terraform validation and command authorization tests. These checks run even when
the branch has no PR and need no AWS credentials. A local commit alone does not
trigger GitHub Actions; push it to GitHub. Branch deletion and tag pushes do not
run these checks. The workflow file must be present on the pushed branch.

The workflow also plans automatically when a same-repository PR is opened, updated,
reopened or marked ready. Only actors with repository write, maintain or admin
permission can trigger Terraform. Fork PRs and draft PRs are rejected.

In GitHub, open **Pull requests > your PR > Conversation**, enter exactly one of
these commands in the existing comment box, and click **Comment**:

```text
/plan
/apply
/destroy
```

Each new command triggers a workflow run and the result is posted back to the PR.
There is no extra comment-box installation. Use PR conversation comments, not
commit comments, review-line comments or ordinary issues.

The workflow records the current PR commit when it authorizes the comment and
checks it again before execution. Apply and destroy create a fresh plan and
immediately apply that saved plan; they do not reuse the earlier PR plan.
Comments do not approve a specific earlier plan or unchanged cloud state. Destroy plans remove
all resources managed by the root state, including the managed S3 bucket.
Non-empty buckets cannot be destroyed because `force_destroy` remains false.
No apply/destroy runs on PR open, merge or close. Edited comments and reruns do
not authorize operations; post a new comment. Plan output appears in PR comments
and workflow logs, so keep this repository private if the configuration includes
sensitive infrastructure details.

All PRs share one deployment and one state key, not one bucket per PR. Runs are
serialized and Terraform also uses S3 lock files. GitHub may replace a pending
run when a newer one queues; post another command if yours was superseded.

## One-time AWS setup

The bucket managed by root Terraform must NOT hold its own state: `/destroy`
would destroy it. `bootstrap/` independently provisions a protected,
versioned state bucket and separate plan/deploy OIDC roles. It is never included
in the PR workflow's Terraform execution.

1. Copy `bootstrap/terraform.tfvars.example` to `bootstrap/terraform.tfvars` and
   set the exact GitHub `owner/repository`. If the account already has the
   `token.actions.githubusercontent.com` IAM OIDC provider, set its ARN too.
2. Using an AWS identity permitted to create the bucket, OIDC provider and roles:

   ```powershell
   $env:AWS_PROFILE = 'default'
   .tools/terraform.exe '-chdir=bootstrap' init
   .tools/terraform.exe '-chdir=bootstrap' plan '-out=bootstrap.tfplan'
   .tools/terraform.exe '-chdir=bootstrap' apply bootstrap.tfplan
   .tools/terraform.exe '-chdir=bootstrap' output
   ```

3. Migrate the existing root state, using the `state_bucket` output:

   ```powershell
   ./bootstrap/migrate-state.ps1 -StateBucket 'STATE_BUCKET_OUTPUT'
   ```

   Answer Terraform's state-copy prompt. The script verifies a no-change plan.
   Keep the bootstrap state and local backups secure. Do not commit state files.
   The generated local backend file is ignored; CI generates the same backend
   from GitHub variables. CI fails if the state object is missing, preventing an
   accidental deployment with empty state. After a deliberate destroy, Terraform
   retains an empty state object so a later apply can recreate the bucket.

## GitHub setup

Create GitHub environments named `terraform-plan` and `terraform-deploy`.
Set each environment's `AWS_ROLE_ARN` variable to its corresponding bootstrap
`github_environment_roles` output. Plan can read the managed bucket and state,
and create/remove lock files; deploy can manage the named bucket and update
state. Neither role can delete the state bucket or state object.

Set these repository Actions variables:

| Variable | Value |
| --- | --- |
| `AWS_ACCOUNT_ID` | `313932316713` |
| `AWS_REGION` | `us-east-1` |
| `TF_STATE_BUCKET` | Bootstrap `state_bucket` output |
| `TF_STATE_KEY` | `s3/terraform.tfstate` |

Enable GitHub Actions and allow workflows to comment on PRs. No AWS access-key
secrets are needed: authentication uses GitHub OIDC. Keep environment deployment
branches restricted to the default branch (the privileged workflow runs there).
An optional required reviewer on `terraform-deploy` adds a GitHub approval gate
before apply/destroy; leave it unset for comment-only execution.

Merge `.github/`, the root configuration, docs and dependency lock files into
the default branch first. Comment events only execute workflows already on the
default branch. Then open a new same-repository test PR. The workflow and its
authorization script are loaded from the default branch; only Terraform code is
checked out at the authorized PR commit. Repository writers are trusted to run
Terraform code with the role assigned to the operation. Protect workflow/IAM
changes through normal default-branch review.

This workspace did not initially contain Git metadata or a remote. Until these
files are pushed and AWS/GitHub setup is completed, the workflow is not live.
Changing the managed bucket name also requires updating the bootstrap role's
`managed_bucket_name` and applying bootstrap before running the PR workflow.

References: [GitHub comment events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#issue_comment),
[AWS OIDC](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws),
[Terraform S3 state and locking](https://developer.hashicorp.com/terraform/language/backend/s3).
