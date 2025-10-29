# Reminder of Critical User Requirements

REMINDER!!

**⚠️ ABSOLUTE CONSTRAINTS - NEVER VIOLATE:**

- **NO `any` types EVER** - Zero tolerance policy
- **NO `as unknown as` casting EVER** - Forbidden completely
- **NO `unknown` where specific types exist** - ALWAYS Use proper typed interfaces
- **ALWAYS use pnpm** - Never npm or yarn
- **Zod validation for ALL external data** - No exceptions. Use strict zod validation everywhere and take advantage of zod's inferred types whenever possible so that validation stays in sync with TS types
- **ESM only** - No CommonJS patterns (.js file extensions are NOT required because esbuild handles module resolution during bundling)

ALWAYS respect the user's requirements and preferences in @CLAUDE.md and @README.md.
