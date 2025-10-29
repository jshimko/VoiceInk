# Review Core Project Commands

IMPORTANT!! Ensure you are always using the correct commands for development and testing. Especially if you are experiencing issues.

- **Start all services**: `pnpm dev` (includes web app, dependencies, and database setup)
- **Web app only**: `pnpm --filter @pianobooker/web dev`
- **Worker service only**: `pnpm --filter @pianobooker/worker dev`
- **Build all apps/packages**: `pnpm build`
- **Build specific and its dependencies**: `pnpm build --filter @pianobooker/web`
- **Run tests**: `pnpm test` (includes database setup and all apps/packages)
- **Test specific package**: `pnpm --filter @pianobooker/web test`
- **Single test file in specific app**: `pnpm --filter @pianobooker/web test src/file-to-test.ts`
- **Single test in specific app**: `pnpm --filter @pianobooker/web test -t "test name"`
- **Lint all apps/packages**: `pnpm lint`
- **Lint specific**: `pnpm --filter @pianobooker/web lint`
- **Lint specific file**: `pnpm --filter @pianobooker/web lint src/file-to-lint.ts`
- **Fix linting**: `pnpm lint:fix`
- **Fix linting in file**: `pnpm --filter @pianobooker/web lint:fix src/file-to-fix.ts`
- **Type check**: `pnpm tsc:check`
- **Type check specific**: `pnpm --filter @pianobooker/web tsc:check`
- **Format code with Prettier**: `pnpm format`

IMPORTANT!! Do NOT use "2>&1" to redirect stderr to stdout in any pnpm commands with the --filter flag because is will throw an error almost 100% of the time due to pnpm workspace command arg limitations.
