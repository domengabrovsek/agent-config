---
name: mr
description: "Create a merge request or pull request from the current branch: verify quality gates, enforce conventional commits, validate the title, preview, and wait for explicit approval before creating. Use when the user says 'create MR', 'create PR', 'open a merge request', or 'raise a PR'."
---

# Create Merge Request / Pull Request

## Workflow

**why-no-hook:** skill workflow guidance; each step requires understanding the surrounding context (repo, task shape, prior state).

1. **Run `/verify-done` first**: hard-fail on any failure. Do not proceed to push, title generation, or PR ceremony if lint, typecheck, test, or build is broken. This pre-empts the most common CI failures (lint, format, typecheck) before they cost a CI run. `(review-time: see section note)`
2. **Detect VCS platform**: check for `.gitlab-ci.yml` (-> glab) or `.github/` (-> gh) `(review-time: see section note)`
3. **Determine base branch**: `(review-time: see section note)`
   - Default for GitLab repos: `main` `(review-time: see section note)`
   - Default for GitHub repos: `develop` `(review-time: see section note)`
   - If the user specifies a different target, use that instead `(review-time: see section note)`
4. **Review all commits on the branch**: run `git log <base>..HEAD` and `git diff <base>...HEAD` to understand the full changeset `(review-time: see section note)`
5. **Enforce conventional commits**: every commit on the branch must match `^(feat|fix|chore|docs|test|refactor|perf|style|build|ci|revert)(\(.+\))?!?: .+`. If any commit fails, stop and ask the user to amend or rewrite the commit history. Do not proceed. `(review-time: see section note)`
6. **Check for env-specific values**: scan diff for hard-coded URLs, credentials, environment names that look wrong for the target branch `(review-time: see section note)`
7. **Push branch** with `-u` flag `(review-time: see section note)`
8. **Generate and validate the PR title**: `(review-time: see section note)`
   - Compose a conventional-commit title summarizing the change `(review-time: see section note)`
   - Validate against the same regex as commit messages: `^(feat|fix|chore|docs|test|refactor|perf|style|build|ci|revert)(\(.+\))?!?: .+` `(review-time: see section note)`
   - If the generated title fails the regex, regenerate. Do not show the user a non-conforming title. `(review-time: see section note)`
9. **Preview and wait for approval**: `(review-time: see section note)`
   - Print the validated MR/PR title, the fully filled-in description body, and the target branch to the chat `(review-time: see section note)`
   - Explicitly stop and wait for the user to confirm in a subsequent turn (e.g. "go", "create it", "lgtm") `(review-time: see section note)`
   - Ambiguous or non-committal replies do not count as approval - ask again rather than proceed `(review-time: see section note)`
   - Do NOT call `gh pr create` / `glab mr create` until that explicit confirmation arrives `(review-time: see section note)`
10. **Create MR/PR using the template**: `(review-time: see section note)`
    - If `.github/pull_request_template.md` or `.gitlab/merge_request_templates/` exists, use that template `(review-time: see section note)`
    - Otherwise use `~/.agents/pull_request_template.md` `(review-time: see section note)`
    - Fill in the description explaining what changed and why `(review-time: see section note)`
    - Add a "Not touched (intentionally)" list naming adjacent code left alone, when the reviewer could expect it changed; it proves scope discipline and surfaces known adjacent problems `(review-time: see section note)`
    - Check the relevant category box(es) - exactly one or more of: Bugfix, Feature, Refactor, Chore, CI/CD, Infrastructure `(review-time: see section note)`
    - Check "Changes have been tested locally" only if tests were actually run `(review-time: see section note)`
    - Check "No unnecessary changes outside the scope of this PR" only if true `(review-time: see section note)`
    - Check "Considered the security impact of these changes" - always check, we always consider it `(review-time: see section note)`
    - Check "No credentials or secrets in the code" only if verified `(review-time: see section note)`
    - Do NOT edit the template structure, wording, or add extra sections - only fill in data and check boxes `(review-time: see section note)`
11. **Set dependencies for stacked MRs/PRs**: `(review-time: see section note)`
    If the target branch is not the default branch (`main`/`master`/`develop`), check for a base MR/PR:

    **GitLab:**

    - Find the base MR: `glab mr list --source-branch <target-branch>` `(review-time: see section note)`
    - If found, create a blocking dependency after MR creation: `(review-time: see section note)`

      ```sh
      glab api --method POST "projects/<url-encoded-project-path>/merge_requests/<our-iid>/blocks" \
        -f "blocking_merge_request_iid=<base-mr-iid>"
      ```

    - HTTP 409 is fine - GitLab may auto-detect some dependencies `(review-time: see section note)`
    - Mention in description: `> **Stacked MR**: depends on !<base-iid>. Retarget to main after !<base-iid> is merged.` `(review-time: see section note)`

    **GitHub:**

    - Find the base PR: `gh pr list --head <target-branch> --json number,title --jq '.[0]'` `(review-time: see section note)`
    - GitHub has no native dependency enforcement. Instead, add `Depends on #<base-pr-number>` in the PR description (under Linked Issues or similar). This is a widely recognized convention that third-party apps (e.g., Dependent Issues, PR Dependencies) can enforce via status checks. `(review-time: see section note)`
    - Mention in description: `> **Stacked PR**: depends on #<base-pr-number>. Retarget to main/develop after #<base-pr-number> is merged.` `(review-time: see section note)`

12. **Report**: print the MR/PR URL. If a dependency was set, mention it. `(review-time: see section note)`

## Rules

- Use CLI tools (`gh pr create` / `glab mr create`), not MCP tools or APIs (except `glab api` for MR dependencies - `glab mr create` has no dependency flag) `(review-time: see section note)`
- Pass the body via HEREDOC for correct formatting `(review-time: see section note)`
- If auth fails, stop and ask the user to authenticate - do not retry `(review-time: see section note)`
- If the repo has a specific MR template, prefer it over the default `(review-time: see section note)`
- Never reference local Claude artifacts (research notes, plans, session summaries under `.claude/state/`, etc.) in the MR/PR description - they only have value locally and mean nothing to reviewers `(review-time: see section note)`
- Never pass `--yes` or any other non-interactive auto-accept flag to `glab mr create` / `gh pr create` `(review-time: see section note)`
- This approval gate applies even when auto mode is active - auto mode is not a license to open MRs/PRs without a human checkpoint `(review-time: see section note)`
- **Scope of the approval gate**: the gate is specifically on the `glab mr create` / `gh pr create` invocation. Related operations that happen before it - pushing the branch, drafting the body, transitioning the Jira ticket - do not need a separate prompt once MR creation itself has been approved in the same turn `(review-time: see section note)`
