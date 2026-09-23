# Testing Patterns

Reusable testing methodology reference. Referenced by the test skill and the QA Expert agent.

## Testing Pyramid

Choose the lowest test level that captures the behavior:

### Unit Tests (preferred - fast, isolated, deterministic)

**Use for**: business logic, utility functions, state transformations, validation rules, data formatting

```text
- Pure functions and calculations
- State machine transitions
- Validation logic (schema, business rules)
- Error handling branches
- Edge cases (empty input, boundary values, null/undefined)
```

### Integration Tests (moderate - verify boundaries)

**Use for**: API endpoints, database queries, service interactions, middleware chains

```text
- API request/response contracts
- Database queries with real/test database
- External service integration (with test doubles at the HTTP boundary)
- Middleware and auth flows
- Message queue producers/consumers
```

### E2E Tests (selective - slow, brittle, expensive)

**Use for**: critical user journeys only, not business logic

```text
- Login -> perform core action -> verify result
- Checkout/payment flow (happy path + key error)
- Onboarding/signup flow
- Cross-service data flow verification
```

## Prove-It Pattern (Bug Fixes)

Every bug fix must follow this sequence:

1. **Reproduce**: write a test that triggers the exact bug
2. **Confirm RED**: run the test - it must fail, proving the bug exists
3. **Fix**: implement the minimum code change to fix the root cause
4. **Confirm GREEN**: run the test - it must pass
5. **Regression**: run the full test suite to verify nothing else broke

If you cannot write a failing test, you do not fully understand the bug. Investigate further before coding a fix.

## Test Data Patterns

### Factory Pattern (preferred)

Create test data with sensible defaults and explicit overrides:

```typescript
function createUser(overrides: Partial<User> = {}): User {
  return {
    id: randomUUID(),
    name: 'Test User',
    email: `test-${randomUUID()}@example.com`,
    createdAt: new Date(),
    ...overrides,
  };
}

// Usage
const admin = createUser({ role: 'admin' });
const deletedUser = createUser({ deletedAt: new Date() });
```

### Builder Pattern (for complex objects)

Use when objects have many optional fields or require construction steps:

```typescript
const order = OrderBuilder.create()
  .withCustomer(customer)
  .withItems([item1, item2])
  .withDiscount(10)
  .build();
```

### Rules

- Never use production data in tests
- Never hardcode IDs, dates, or values that could collide
- Use `faker` or random generators for string fields
- Isolate test data per test - no shared mutable state

## Mock Boundaries

### What to Mock

- External HTTP APIs (use `msw` or `nock` at the network boundary)
- Time (`vi.useFakeTimers()`) when testing time-dependent logic
- Environment variables when testing config-dependent behavior
- File system when testing file operations

### What NOT to Mock

- Your own code (internal modules, utilities, helpers)
- The database in integration tests - use a real test database
- Third-party library internals (mock the interface you own, not the library)
- More than 2 modules in a single test file - if you need more, you are testing at the wrong level

### Test Double Types

- **Stub**: returns canned data - use for queries
- **Spy**: records calls - use for verifying side effects
- **Fake**: simplified real implementation - use for in-memory repositories
- **Mock**: pre-programmed expectations - use sparingly, prefer stubs

## Flaky Test Prevention

- No `setTimeout` or `waitForTimeout` with fixed delays - use proper wait conditions
- No shared mutable state between tests - each test sets up and tears down its own data
- No dependency on test execution order - every test must pass with `test.only()`
- No reliance on wall clock time - use fake timers
- No assertions on randomly generated data without seeding
- No E2E tests without retry strategy (network, browser, API flakiness)
- No file system tests without temp directory isolation

## Test Naming

Test names should read like specifications:

```text
- "returns empty array when no users match the filter"
- "throws ValidationError when email format is invalid"
- "sends notification email after successful order placement"
- "denies access when user lacks admin role"
```

Avoid: `"test1"`, `"should work"`, `"handles edge case"`, `"user test"`
