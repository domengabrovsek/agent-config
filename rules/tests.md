---
paths:
  - "**/*.test.*"
  - "**/*.spec.*"
  - "**/__tests__/**"
  - "**/e2e/**"
---

# Testing Standards

**When to apply:** editing test files (`*.test.ts`, `*.spec.ts`, `*.test.tsx`, `*.spec.tsx`).

- Vitest preferred as the test runner `(review-time: preference, not enforceable when team picks otherwise)`
- Mock external dependencies only (third-party APIs, file system, time) - not internal modules. Integration tests use a real test database `(review-time: requires understanding the module boundary being mocked)`
- Manual class instantiation over dependency injection in tests `(review-time: structural pattern, varies per framework)`
- Test behavior, not implementation details `(review-time: semantic - which assertions count as implementation-coupled)`
- No flaky tests in main branch - if a test is flaky, fix or remove it `(CI)`
- No hardcoded test data that couples to environment - use factories or builders `(review-time: identifying environmental coupling needs reading)`
- Each test should be independent - no shared mutable state between tests `(review-time: shared-state detection requires analysis)`
- Prefer `describe`/`it` blocks with descriptive names that read as sentences `(review-time: naming quality is subjective)`
- Run single test files during development, full suite before declaring done `(review-time: workflow guidance, not code pattern)`
