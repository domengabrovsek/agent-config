---
paths:
  - "**/*.tf"
  - "**/*.tfvars"
  - "**/Dockerfile*"
  - "**/docker-compose*"
  - "**/.github/workflows/**"
  - "**/.gitlab-ci.yml"
  - "**/k8s/**"
  - "**/kubernetes/**"
  - "**/helm/**"
  - "**/manifests/**"
  - "**/ansible/**"
  - "**/ansible.cfg"
  - "**/playbooks/**"
  - "**/roles/**/tasks/**"
  - "**/roles/**/handlers/**"
  - "**/group_vars/**"
  - "**/host_vars/**"
  - "**/site.yml"
---

# Infrastructure Conventions

**When to apply:** editing Terraform, Dockerfiles, docker-compose, Kubernetes manifests, Ansible playbooks or roles, or CI/CD workflow files - and when running any infra command that applies, destroys, or grants access (`terraform apply/destroy`, `ansible-playbook`, `gcloud`, `gsutil`, `aws`, `kubectl delete`).

- Infrastructure as Code only - no manual changes to cloud resources `(review-time: process, not detectable in code)`
- No `latest` tags for Docker images - always use specific version tags `(hook)`
- No secrets in code, Dockerfiles, or CI configs - use secret managers `(review-time: secrets blocked by deny rules + reviewer judgment; pattern detection has false positives)`
- No mutable infrastructure - rebuild, don't patch `(review-time: requires understanding the change's effect on a running resource)`
- Multi-stage Docker builds to minimize image size `(review-time: structural Dockerfile pattern, hard to flag without false positives)`
- CI/CD pipelines must run lint, typecheck, and tests before deploy `(CI)`
- Always tag cloud resources with project, environment, and owner `(review-time: tag presence varies per Terraform resource type)`
- GCP is primary cloud, AWS is secondary `(review-time: provider preference, not a code pattern)`

## GitHub Actions references

A third-party tag can be moved to new code, so third-party actions get a SHA pin. Dependabot bumps those pins. Own actions track `@main`, so a change there reaches every repo at once.

Own means the owner of the repo's `origin` remote, plus any owners in `OWN_ACTION_OWNERS` (comma-separated). Set it where one person's repos span several owners.

- Reference own actions and reusable workflows at `@main`, never a SHA or tag `(hook)`
- Pin every other action to its full commit SHA, with the version as a comment: `uses: actions/checkout@<sha> # v4.2.2` `(hook)`
- Never propose pinning own actions, in a pull request or as a follow-up `(review-time: a proposal is prose, which no hook sees)`

## Destructive and privileged operations

**why-no-hook:** each rule needs knowledge external to the command text - who consumes a resource, whether a role is valid at a given scope, what a deploy pipeline actually does. A hook sees only the argv, not the blast radius.

- Before destroying or deleting any shared or stateful cloud resource (bucket, database, KV store, secret, DNS zone), enumerate every system that consumes it and confirm with the user - never assume a resource is single-purpose `(review-time: see section note)`
- Before granting an IAM role, verify the role is assignable at the target scope (project vs folder vs org) before applying - some roles are org/folder-only (e.g. `orgpolicy.policyAdmin`) and an invalid binding can fail the apply and clobber existing bindings `(review-time: see section note)`
- Read the actual CI/CD workflow and deployment config files before explaining or modifying how a deploy works - never guess at deploy mechanics from naming or convention `(review-time: see section note)`

## Terraform comments

Terraform spreads state across many stacks and files. A reader looking at one block in isolation should be able to tell its role and lifecycle without grepping the whole repo, so Terraform gets a per-block comment convention that the rest of the codebase does not.

- Every `resource` and `data` block gets a brief comment above it: what it is for, plus context not obvious from the type and label. Multi-line uses `/* */` `(review-time: requires judging whether context is already obvious)`
- `variable`, `output`, and `module` blocks use their built-in `description` attribute. No comment on top of those `(review-time: block-type recognition)`
- No tracker refs (`SER-123`, `#456`, `ADR-0042`) and no em dashes inside any `description = "..."`. These surface in terraform-docs output and module-consumer READMEs, where a tracker ref is more visible than in a buried comment. Multi-line and WHAT-style descriptions are fine `(hook)`

Good:

```hcl
# Per-env random password for the platform admin's first login.
# Consumed by the app-bootstrap Cloud Run Job; rotated by bumping keepers.rotation_id.
resource "random_password" "platform_admin_initial" {
  ...
}
```

Bad, restates the resource type and adds nothing:

```hcl
# A random password resource.
resource "random_password" "platform_admin_initial" {
  ...
}
```

Good description:

```hcl
variable "platform_admin_email" {
  description = "Email address for the platform admin account. Used by the app-bootstrap job to seed the initial user."
  type        = string
}
```

Bad description, carries tracker refs:

```hcl
variable "platform_admin_email" {
  description = "Per ADR 0031: email for the platform admin. See api-service PR #1397."
  type        = string
}
```
