# 12 — Production build E2E tests

## Status: Not started

Current E2E tests run against `astro dev` (dev server).
Need tests against `astro build` (production build) to catch
production-only issues (minification, asset paths, etc.).

## Steps
1. `npm run build`
2. `npx playwright test --config=playwright.prod.config.ts`
3. Verify all 38 tests pass on production build
