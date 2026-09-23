---
paths:
  - "**/*.ts"
  - "**/*.tsx"
---

# TypeScript Standards

**When to apply:** editing TypeScript files (`*.ts`, `*.tsx`).

- No `any` or `unknown` - use proper types, generics, or branded types `(lint)`
- 2-space indentation, single quotes `(lint)`
- Prefer `interface` over `type` for object shapes (unless union/intersection needed) `(review-time: structural choice, biome can flag but not in default config)`
- Prefer an options object when a function takes 3+ parameters, or when any parameter is optional. Destructure inside the function body. Exceptions: tightly coupled, order-intuitive positional params where the order IS the contract (e.g., `clamp(value, min, max)`, `range(start, end, step)`, `lerp(a, b, t)`), and variadic/rest functions. Boolean parameters should always be passed via an options object regardless of count - avoid "flag soup" like `doThing(true, false, true)` `(review-time: requires judgment about which params are "order-intuitive")`
- Destructure imports when possible: `import { foo } from 'bar'` `(lint)`
- No barrel exports (`index.ts` re-exports) - import directly from source `(review-time: file-structure pattern, hard to detect without false positives)`
- No default exports - use named exports only `(lint)`
- Zod schemas for runtime validation at system boundaries (API inputs, env vars, external data) `(review-time: requires knowing which functions are at the boundary)`
- Never use `var` `(hook)`
- Prefer `const` over `let` `(review-time: post-edit-lint catches var only)`
- Use strict null checks - handle `null`/`undefined` explicitly `(lint)`
- No non-null assertion operator (`!`) - use proper null checks, optional chaining, or narrowing instead `(lint)`
