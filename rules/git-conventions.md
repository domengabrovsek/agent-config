# Git Conventions

**When to apply:** every commit, branch operation, or pull-request action.

## Already enforced

Hooks and deny rules back these. Know them to avoid hitting the gate.

- Conventional commit format. Scope optional: `feat(auth): add token refresh` `(hook)`
- No AI attribution in commits, PR titles, PR bodies, or issues: no Co-Authored-By, no "Generated with" footer `(hook)`
- Comments you post end with the agent footer from `pr-comments` `(hook)`
- Check the branch with `git branch --show-current` before committing. Never commit or push to main/master, even when the user approves it. Every change lands through a PR `(hook)`
- Rebase onto the target branch (`git fetch origin main && git rebase origin/main`) before opening a PR. Update an open PR with `gh pr update-branch`, never a force-push `(review-time: no hook checks this)`
- Pushes run the repo's `verify:fast` when declared. Open or ready a PR only after `npm run verify` passes at HEAD `(hook)`

## Judgment calls

- Commit, push, and open the PR for feature-branch work without asking once its checks pass `(review-time: requires judging that the checks ran)`
- Never force-push without asking immediately before the push. Approval of a plan containing a force-push is not approval of the push. Teammates report a needed force-push back rather than running it `(review-time: needs a fresh confirmation at execution time; deny rules block bare --force)`
- Never merge a PR. The user merges `(review-time: depends on a user signal, not a pattern)`
- PR descriptions use bullets, not prose paragraphs `(review-time: formatting of free-form text)`
- Never reference `.claude/state/` plans, research, or diaries in a PR description. They are untracked and invisible to reviewers `(hook)`
- After pushing new commits to an open PR, update its title and body with `gh pr edit` `(review-time: requires judging whether the body still reflects the diff)`
- Use the repo's `.github/pull_request_template.md` when it exists, otherwise `~/.agents/pull_request_template.md` `(review-time: template selection requires reading the directory)`
- Editing tests? Update mocks to match the new DB queries, service dependencies, and imports `(review-time: requires understanding mock-target coupling)`
- Semver: MAJOR for breaking, MINOR for additive, PATCH for fixes `(review-time: classifying a change as breaking needs judgment)`
- Use `gh` for all GitHub operations. Never MCP tools `(review-time: tool selection per action, not a single regex)`

## PR state goes stale

Conversation memory about a PR is not evidence.

- Before claiming PR state (open, merged, closed, checks passing, "you're all set"), run `gh pr view --json state,mergedAt,statusCheckRollup,url` and answer from that output. A probe holds for 5 minutes unless a state-changing command ran in between `(review-time: requires recognizing a state claim in your own reply)`
- `hooks/pre-git-state-refresh.sh` injects a `[pr-state]` line before write-side git and `gh pr` commands. Read it. If it reports `state=MERGED` or `state=CLOSED` for a PR you are about to write to, stop and confirm intent `(hook)`
