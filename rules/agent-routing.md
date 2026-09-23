# Expert Agent Routing

**When to apply:** a task touches a specialized domain. Skip for typos, one-liners, and config tweaks.

Spawn a teammate via the Agent tool with the matching `subagent_type`. It loads the persona in its own context and returns a summary.

- Never read `agents/*.md` into the main conversation. That pollutes context and bleeds the persona's bias into unrelated work later in the session `(review-time: file-access decision, not a code pattern)`
- Act on the teammate's summary, not on the persona file `(review-time: about how the reply gets used)`
- Teammates may disagree. Surface the conflict to the user rather than silently picking a side `(review-time: requires reading several teammate outputs)`
- A task crossing domains spawns its teammates in parallel, in one message `(review-time: requires recognizing the cross-domain shape)`

## Personas

| `subagent_type` | Spawn when the task touches... |
| --- | --- |
| `Staff Engineer` | Architecture, DDD, module boundaries, system-level design |
| `Backend Staff Engineer` | Node.js APIs, server logic, data pipelines, caching, rate limiting |
| `Frontend Staff Engineer` | React, components, CSS, browser, client-side performance |
| `DevOps Engineer` | CI/CD, Docker, Kubernetes, Terraform, observability, GitOps |
| `QA Expert` | Test strategy, test architecture, flaky tests, E2E, coverage |
| `PR Reviewer` | Pull request review, code review |
| `Cybersecurity Expert` | Security review, OWASP, auth flows, vulnerability assessment |
| `PostgreSQL Expert` | SQL, indexes, query plans, migrations, schema design |
| `AWS Expert` | AWS services and infrastructure |
| `GCP Expert` | GCP services and infrastructure |
| `Networking Expert` | DNS, TCP, load balancers, CDN, VPN |
| `ArgoCD Expert` | ArgoCD, ApplicationSet, sync policy, Argo Rollouts |
| `GDPR Expert` | Privacy, consent, DPIA, PII handling for EU subjects |
| `GTM Expert` | Google Tag Manager, server-side tagging, GA4, CAPI |
| `Product Manager` | Feature planning, user stories, success criteria, roadmap |
| `UX Expert` | Usability, accessibility, WCAG, interaction design |
| `Spec Verifier` | Checking an implementation against its spec's acceptance criteria before a PR |

Pair them where the work crosses a seam: UI work takes Frontend plus UX, EU data handling adds GDPR, a security-sensitive PR takes PR Reviewer plus Cybersecurity.
