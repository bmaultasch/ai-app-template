# AI App Template

## Stack
- **Framework:** Next.js 15 (App Router, TypeScript, Turbopack)
- **Auth & DB:** Supabase (Auth + Postgres with RLS)
- **AI:** Vercel AI SDK (supports OpenAI, Anthropic via `AI_PROVIDER` env var)
- **UI:** Tailwind CSS v4, shadcn/ui (add components with `pnpm dlx shadcn@latest add <component>`)
- **Secrets:** Doppler (single source of truth, injected at runtime)
- **Deploy:** Vercel via GitHub Actions

## Key Commands
| Command | What it does |
|---|---|
| `make dev` | Start local dev with Doppler secrets injected |
| `make build` | Build with secrets |
| `make deploy` | Deploy to Vercel production |
| `make migrate` | Push Supabase migrations |
| `make secrets-sync` | Push Doppler secrets → Vercel env vars |

## Project Structure
```
src/
  app/
    layout.tsx          # Root layout
    page.tsx            # Home (redirects to /login if not authed)
    login/page.tsx      # Magic link login
    auth/callback/      # OAuth/magic link callback
    api/chat/route.ts   # AI streaming endpoint
  lib/
    supabase/
      client.ts         # Browser client
      server.ts         # Server client (RSC/Route Handlers)
      middleware.ts      # Session refresh middleware
    ai.ts               # AI model config
    utils.ts            # cn() utility
  components/
    chat.tsx            # Chat UI component
  middleware.ts         # Re-exports supabase middleware
supabase/
  config.toml           # Local Supabase config
  migrations/           # SQL migrations (applied with `make migrate`)
```

## Adding Things

### New page
Create `src/app/your-page/page.tsx`. It's automatically routed at `/your-page`.

### New API route
Create `src/app/api/your-route/route.ts` with exported `GET`/`POST`/etc functions.

### New database table
1. Create a new migration: `supabase migration new <name>`
2. Write SQL in the generated file under `supabase/migrations/`
3. Apply: `make migrate`
4. Always enable RLS and add policies

### New AI provider
The AI SDK supports many providers. Install the provider package and update `src/lib/ai.ts`.

### New UI component (shadcn)
```bash
pnpm dlx shadcn@latest add button
```

## Gotchas
- **NEXT_PUBLIC_ prefix:** Client-side env vars MUST start with `NEXT_PUBLIC_` or they won't be available in the browser
- **RLS:** Always enable Row Level Security on new tables and add policies
- **Middleware:** The middleware refreshes Supabase auth tokens. Don't remove it.
- **Zscaler:** If on a corporate network, ensure `NODE_EXTRA_CA_CERTS=/Users/brandon/zcert/zscaler.pem` is set. `make dev` handles this via Doppler.
- **No .env files:** Secrets come from Doppler (`make dev`). The `.env.example` documents what vars exist but has no values.
