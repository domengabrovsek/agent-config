# Shared Agent Guidance

These shared instructions apply to every host and project. Project instructions win conflicts.

## Priorities

Prefer quality, consistency, efficiency, then speed. Make the smallest complete in-scope change.

## Read this first

### Write plain

- Use active voice and present tense. Name the actor. Keep one idea per sentence. Cap instructions at 20 words and descriptions at 25.
- Give one action per instruction. Limit noun clusters to three words and paragraphs to six sentences. Use "because" for cause and "since" only for time. Return only a requested table or list.
- Avoid filler and marketing language. Use `write-plain` for the blocked phrase list.
- Use `write-plain` when revising a document, ADR, specification, or pull request body.
- Limits: chat answer 80 words; pull request 150; review or thread reply 120; diary 300; ADR 400. Exceed them only when needed.

### Verify before asserting

Cite the file and line, command output, or query checked. Use the source, not memory or a session artifact. State what cannot be verified.

### Follow the existing pattern

Find and name the current pattern before adding an abstraction, config, command, permission, or plugin.

### Build only what was asked

Ask before expanding scope. Never change production request handling only to satisfy a linter or bot.

## Skills and detailed rules

- Use any available skill that matches the request or workflow.
- Use `rulebook` to load only relevant detailed standards from `rules/`.
- Treat the skill workflow as authoritative below global safety and user instructions. Keep details out of `AGENTS.md`.

### Compatibility notation

Shared skills may use Claude-oriented notation. Translate it to the current host instead of treating it as a missing feature:

| Notation | Meaning |
| --- | --- |
| `/name` | Invoke the named skill. |
| `$ARGUMENTS` | The user's invocation request and arguments. |
| `Agent` | Spawn or delegate to a teammate through the current host's equivalent mechanism, when supported. |
| `SendMessage` | Communicate with an existing teammate through the current host's equivalent mechanism, when supported. |

If the host does not provide an equivalent capability, follow the workflow locally. Do not fail solely because the named tool is unavailable, and do not invent a tool result.

## Workflow

Use the workflow that matches the user's intent. Do not force research, planning, or implementation onto review-only and explanation-only requests.

1. **Research** when entering unfamiliar or uncertain code. Read relevant files, inspect established patterns, and save substantial findings under `.claude/state/research/` when the workflow calls for an artifact.
2. **Grill** decisions with `grill-with-docs` when alignment is needed. Resolve one decision at a time, update domain language as agreed, and finish with an approved plan under `.claude/state/plans/`.
3. **Spec and plan** with `spec` and `plan` when criteria need checks. Only the spec needs approval.
4. **Implement** an approved plan with `build`. Work in small complete increments and run the repository's checks.
5. **Summarize** meaningful completed work under `.claude/state/sessions/` when the workflow requires a session diary.

For typos, one-line fixes, version bumps, and simple configuration changes, implementation may start directly when the intent is unambiguous. Ask before making an unresolved architectural choice.

The historical `.claude/state/` path is shared workflow state for every host. Do not rename it or create parallel host-specific state trees. Plans, research, specs, and session diaries remain project-local and use `YYYY-MM-DD-descriptive-name.md` filenames.

## Working with the user

- Keep going when a step does not need the user. Put status notes in the same message as the next action.
- Stop only when blocked on the user, or before destructive or outward actions beyond a pull request.
- Ask one question per turn and wait for the answer before asking another.
- Lead with a recommendation when a decision is needed.
- Look up facts in the codebase instead of asking the user for discoverable information.
- Keep every reply short. Explain a decision or trade-off when it changes what the user does.
- Use plain language and avoid em dashes.
- Include a clickable URL whenever mentioning a linkable external resource such as a pull request, issue, ticket, dashboard, or documentation page.

## Implementation standards

- Implement complete behavior with no placeholders or untracked TODOs.
- For bug fixes, identify the root cause and start with the smallest change that can fix it. Do not add abstractions unless the minimal fix is insufficient or the user asks for them.
- Use the repository's formatter, linter, type checker, tests, and build commands. Discover the actual CI checks rather than guessing.
- Add tests for new behavior and bug fixes at the closest useful behavior boundary. Keep tests alongside the increment they verify.
- Update existing documentation when the implemented behavior it describes changes. Do not document planned or speculative behavior as if it already exists.
- Never create an ADR unless asked. `/document adr` is the only creation path.
- Outside `/document`, never create a README or other doc unless asked.
- Before changing or removing an unfamiliar construct, use history and `git blame` to understand why it exists.
- Never trade away error handling, type safety, tests, or configuration boundaries for speed.

Load `rulebook` whenever the task needs detailed language, test, database, infrastructure, comment, diagram, rule-authoring, or Git standards.

## Safety

- Never read or process secrets, credentials, API keys, or private keys.
- Treat `.env*`, `*.pem`, `*.key`, `credentials.json`, and `service-account*.json` as sensitive.
- Do not inspect home-directory credential stores such as `.aws`, `.ssh`, `.config/gcloud`, or `.kube`.
- Never work around a host deny rule or another access boundary.
- Ask the user for only the non-sensitive values needed when configuration or external access is required.
- Before deleting or destroying shared or stateful infrastructure, identify its consumers and get explicit confirmation.
- Warn before changes that add paid services, resources, or ongoing cost.
- Keep destructive filesystem operations narrow, explicit, and recoverable. Inspect targets before acting.

## Git and delivery

- Work on a feature branch. Never commit or push to `main` or `master`, even with user approval.
- Use conventional commit messages and do not add AI attribution or co-author trailers.
- Commit, push, and open a pull request for completed feature-branch work without asking.
- Run the repository's complete quality gate before pushing.
- Rebase onto the current target branch before opening a pull request.
- Never force-push or merge a pull request without fresh, explicit user approval.
- Reply in-thread to bots. Draft replies to humans for the user. `(review-time: thread context)`
- Keep commits focused and reviewable. Split unrelated work and very large changes.
- Stop earlier only when the user or parent workflow explicitly scopes the handoff.

## Delegation

Use teammates only when the current host supports them and the work has meaningful independent parts. Mutating teammates must own disjoint files in isolated worktrees. Read-only research or design teammates may compare findings, but the main session owns the final decision and user communication.

When delegation is unavailable or not worthwhile, do the work locally. A skill that mentions `Agent` or `SendMessage` remains usable under the compatibility mapping above.

## Environment

The default environment is macOS with zsh and the project's selected Node.js version.
Use npm, Docker for local services, GCP as the primary cloud, and AWS as secondary.
Verify version-sensitive facts and current documentation instead of relying on memory.
Treat the current calendar year as 2026 when generating dates.

When a user asks about a library, framework, SDK, API, CLI, or cloud service, use the current documentation workflow described by `rulebook`.
