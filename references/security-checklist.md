# Security Checklist

Reusable security checklist mapped to the [OWASP Top 10:2025](https://top10.owasp.org/2025). Referenced by the ship skill and the PR Reviewer agent.

## Input Validation (OWASP A05: Injection)

- [ ] All external input validated at system boundaries (API requests, webhooks, URL params, env vars)
- [ ] Validation uses schema library (Zod) - not manual checks
- [ ] SQL queries use parameterized statements or ORM methods - never string concatenation
- [ ] GraphQL queries have depth/complexity limits
- [ ] File uploads validated: type, size, extension, content-type header match
- [ ] Path traversal prevented: no user input in file paths without sanitization

## Output Encoding (OWASP A05: Injection, which includes XSS)

- [ ] User-generated content escaped before rendering in HTML
- [ ] Content-Security-Policy header set (no `unsafe-inline` or `unsafe-eval` without justification)
- [ ] No `dangerouslySetInnerHTML` or `eval()` with user data
- [ ] API responses do not leak stack traces, internal paths, or server info
- [ ] Error messages are generic for users, detailed in logs

## Authentication & Sessions (OWASP A07: Authentication Failures)

- [ ] Passwords hashed with bcrypt, scrypt, or argon2 - never MD5/SHA
- [ ] Session tokens are httpOnly, secure, sameSite=strict/lax
- [ ] JWT tokens have reasonable expiry and are validated server-side
- [ ] No auth tokens stored in localStorage - use httpOnly cookies
- [ ] Multi-factor authentication available for sensitive operations
- [ ] Rate limiting on login/signup/password-reset endpoints
- [ ] Account lockout or progressive delays after failed attempts

## Authorization (OWASP A01: Broken Access Control)

- [ ] Every mutation/query accessing user data verifies permissions
- [ ] No reliance on client-side checks only - server enforces all access control
- [ ] CORS configured with explicit origins - no wildcard `*` for authenticated endpoints
- [ ] Admin endpoints require elevated privileges and are audited
- [ ] Principle of least privilege applied to all service accounts and IAM roles

## Transport & Headers (OWASP A04: Cryptographic Failures, A02: Security Misconfiguration)

- [ ] HTTPS only - no mixed content, HSTS header set
- [ ] Security headers configured: CSP `frame-ancestors` (X-Frame-Options only as a legacy fallback), X-Content-Type-Options, Referrer-Policy
- [ ] TLS 1.2+ required - no fallback to older protocols
- [ ] Cookies marked secure (only sent over HTTPS)

## Secrets Management (OWASP A04: Cryptographic Failures)

- [ ] No secrets in source code, commit history, or CI logs
- [ ] Secrets loaded from environment variables or secret manager (not config files)
- [ ] `.env*`, `*.pem`, `*.key`, `credentials.json`, `service-account*.json` in `.gitignore`
- [ ] API keys scoped to minimum required permissions
- [ ] Secrets rotated on a schedule and after any suspected exposure

## Dependencies and Supply Chain (OWASP A03: Software Supply Chain Failures, A08: Software or Data Integrity Failures)

- [ ] `npm audit` (or equivalent) runs in CI with zero critical/high vulnerabilities
- [ ] Dependencies pinned to specific versions (lockfile committed)
- [ ] No dependencies with known CVEs in production
- [ ] New dependencies justified: bundle size, maintenance status, license, security posture
- [ ] Unused dependencies removed
- [ ] CI actions and build tools pinned to a version or commit SHA, not a moving branch
- [ ] Lifecycle install scripts reviewed for new dependencies

## Database Security (OWASP A05: Injection, A06: Insecure Design)

- [ ] Database credentials not hardcoded - loaded from environment/secret manager
- [ ] Database ports not exposed to public internet
- [ ] Migrations are backward-compatible and reversible
- [ ] Sensitive data (PII, financial) encrypted at rest
- [ ] Database backups encrypted and access-controlled
- [ ] Connection pooling configured with appropriate limits

## Error Handling (OWASP A10: Mishandling of Exceptional Conditions)

- [ ] Failures fail closed: an exception in an auth or permission check denies access
- [ ] Every error path releases resources and rolls back partial state
- [ ] Unexpected input and timeouts are handled explicitly, not left to crash the process
- [ ] No empty catch blocks that swallow errors

## Logging & Monitoring (OWASP A09: Security Logging and Alerting Failures)

- [ ] Security events logged: auth failures, permission denials, input validation failures
- [ ] No sensitive data in logs (passwords, tokens, PII, credit cards)
- [ ] Structured logging with correlation IDs for traceability
- [ ] Alerts configured for anomalous patterns (spike in auth failures, unusual access patterns)
- [ ] No `console.log` with sensitive data in production code
