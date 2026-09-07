# Expert Agents

16 expert agent personas: lean spawn-time briefs with repo-specific guardrails, red-flag detection, and explicit output contracts. Each agent is spawned as a subagent when a task matches its domain via the routing table in [`rules/agent-routing.md`](../rules/agent-routing.md) (see ADR 0003 and ADR 0007).

## Engineering

| Agent | File | Focus |
| --- | --- | --- |
| Staff Engineer | [`staff-engineer.md`](../agents/staff-engineer.md) | System design, code architecture, design principles, DDD, SOLID |
| Frontend Staff Engineer | [`frontend-staff-engineer.md`](../agents/frontend-staff-engineer.md) | React, component architecture, rendering strategies, Core Web Vitals, accessibility |
| Backend Staff Engineer | [`backend-staff-engineer.md`](../agents/backend-staff-engineer.md) | API design, database engineering, event-driven architecture, caching, resilience |
| DevOps Engineer | [`devops-engineer.md`](../agents/devops-engineer.md) | IaC, containers, Kubernetes, CI/CD, observability, SRE |
| QA Expert | [`qa-expert.md`](../agents/qa-expert.md) | Test strategy, test automation, CI testing, performance testing, accessibility testing |

## Infrastructure & Data

| Agent | File | Focus |
| --- | --- | --- |
| AWS Expert | [`aws-expert.md`](../agents/aws-expert.md) | AWS services, Well-Architected Framework, cost optimization, IAM |
| GCP Expert | [`gcp-expert.md`](../agents/gcp-expert.md) | GCP services, Cloud Run, BigQuery, IAM, networking |
| PostgreSQL Expert | [`postgresql-expert.md`](../agents/postgresql-expert.md) | Query optimization, indexing, partitioning, replication, schema design |
| Networking Expert | [`networking-expert.md`](../agents/networking-expert.md) | TCP/IP, DNS, load balancing, CDN, VPN, network security |
| ArgoCD Expert | [`argocd-expert.md`](../agents/argocd-expert.md) | ArgoCD, GitOps, ApplicationSet, sync strategies, Argo Rollouts, progressive delivery |

## Marketing & Analytics

| Agent | File | Focus |
| --- | --- | --- |
| GTM Expert | [`gtm-expert.md`](../agents/gtm-expert.md) | Server-side tagging, GTM web/server containers, data layer, Consent Mode v2, Conversion APIs |

## Security & Compliance

| Agent | File | Focus |
| --- | --- | --- |
| Cybersecurity Expert | [`cybersecurity-expert.md`](../agents/cybersecurity-expert.md) | OWASP, auth, cryptography, supply chain security, threat modeling |
| GDPR Expert | [`gdpr-expert.md`](../agents/gdpr-expert.md) | EU data protection, DPIAs, consent management, data subject rights, international transfers |

## Product & Design

| Agent | File | Focus |
| --- | --- | --- |
| Product Manager | [`product-manager.md`](../agents/product-manager.md) | Product strategy, user stories, prioritization, roadmapping, metrics |
| UX Expert | [`ux-expert.md`](../agents/ux-expert.md) | Interaction design, usability, accessibility, design systems, information architecture |

## Code Review

| Agent | File | Focus |
| --- | --- | --- |
| PR Reviewer | [`pr-reviewer.md`](../agents/pr-reviewer.md) | Structured severity-based code reviews, TypeScript/Node.js, GraphQL, database, security |

## Agent Structure

Every agent follows the same 5-section skeleton (ADR 0007):

1. **Role** - 2-3 sentences of responsibility and approach
2. **How to work** - investigation-first discipline; findings are returned in the final message, not written to report files
3. **Guardrails** - 6-10 repo-specific, non-obvious blockers, each tagged `(persona)`; anything already covered by `rules/` is deliberately absent because custom subagents inherit CLAUDE.md and all imported rules
4. **Red Flags** - concrete, easy-to-miss patterns that trigger investigation
5. **Output format** - the exact shape of the returned summary (severity buckets + verdict for advisory personas; changed/verified/concerns for writer personas)

Two kinds of persona (see CONTEXT.md glossary):

- **Advisory personas** drop the editing tools via `tools:` frontmatter (no Edit/Write/NotebookEdit): PR Reviewer, Cybersecurity Expert, GDPR Expert, Product Manager, UX Expert. They keep Bash, which they need for `git diff` and `gh`, so a write is still reachable through a shell command; the frontmatter removes the one-call edit and the brief does the rest. They are not lane-mode writers.
- **Writer personas** (the other 11) omit `tools:` and keep full access for lane-mode implementation work.

## Routing

The routing table in [`rules/agent-routing.md`](../rules/agent-routing.md) maps domain triggers to agent files. Claude spawns matching agents as subagents before starting work (ADR 0003 - agent files are never read into the main conversation). Multiple subagents spawn in parallel when a task crosses domains (e.g., a new API endpoint spawns backend + security + QA).

## Parallelism limits

`rules/parallel-agents.md` caps lane-mode work at a target of 4 parallel agents with a hard ceiling of 5. The rationale:

- **Merge conflict surface** scales as n*(n-1)/2: 4 agents = 6 pair combinations, 5 = 10, 8 = 28. The jump from 4 to 5 is acceptable; past 5 it gets painful fast.
- **Review bandwidth**: reviewing 4 separate diffs in one sitting is the upper edge of what a human can do without rubber-stamping.
- **API rate limits**: parent + 4 children = 5 concurrent token streams, which leaves headroom on standard tiers. 8+ regularly hits throttling and silently serializes the "parallel" work.
- **Local resources**: each worktree is a full repo copy plus tool processes. 4 is comfortable on a typical Mac; 8+ starts to matter for large monorepos.
- **Diminishing wall-clock returns**: the slowest agent dictates total time. With 4 agents you already capture ~80% of the theoretical speedup; more mostly buys coordination overhead.
