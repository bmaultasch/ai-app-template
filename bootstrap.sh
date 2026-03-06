#!/usr/bin/env bash
set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────
GITHUB_ORG="bmaultasch"
TEMPLATE_REPO="bmaultasch/ai-app-template"
SUPABASE_ORG=""  # filled automatically
DOPPLER_CONFIG="prd"
export NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS:-/Users/brandon/zcert/zscaler.pem}"
export SUPABASE_ACCESS_TOKEN="${SUPABASE_ACCESS_TOKEN:?Set SUPABASE_ACCESS_TOKEN before running (from supabase.com/dashboard/account/tokens)}"

# Vercel CLI ignores NODE_EXTRA_CA_CERTS behind Zscaler — use token + TLS bypass for Vercel commands only
VERCEL_TOKEN="${VERCEL_TOKEN:-}"
VERCEL_SCOPE="${VERCEL_SCOPE:-}"
vcmd() { NODE_TLS_REJECT_UNAUTHORIZED=0 vercel "$@" --token "$VERCEL_TOKEN" ${VERCEL_SCOPE:+--scope "$VERCEL_SCOPE"} 2>&1; }

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}▸${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
fail()  { echo -e "${RED}✗${NC} $1"; exit 1; }

# ─── Usage ───────────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: ./bootstrap.sh <app-name>"
  echo "Example: ./bootstrap.sh my-cool-app"
  exit 1
fi

APP_NAME="$1"
APP_DIR="$(pwd)/$APP_NAME"

echo ""
echo -e "${BLUE}━━━ Bootstrapping ${APP_NAME} ━━━${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 1: Prerequisites
# ═══════════════════════════════════════════════════════════════════════════════
info "Phase 1: Checking prerequisites..."

MISSING=()

command -v gh       >/dev/null || MISSING+=("gh (brew install gh)")
command -v supabase >/dev/null || MISSING+=("supabase (brew install supabase/tap/supabase)")
command -v doppler  >/dev/null || MISSING+=("doppler (brew install dopplerhq/cli/doppler)")
command -v pnpm     >/dev/null || MISSING+=("pnpm (npm install -g pnpm)")
command -v jq       >/dev/null || MISSING+=("jq (brew install jq)")
command -v vercel   >/dev/null || MISSING+=("vercel (npm install -g vercel)")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  fail "Missing tools:\n$(printf '  - %s\n' "${MISSING[@]}")"
fi

# Check auth status
gh auth status &>/dev/null || fail "Not logged into GitHub. Run: gh auth login"
doppler me &>/dev/null     || fail "Not logged into Doppler. Run: doppler login"

ok "All prerequisites met"

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 2: GitHub Repo
# ═══════════════════════════════════════════════════════════════════════════════
info "Phase 2: Creating GitHub repo..."

if gh repo view "${GITHUB_ORG}/${APP_NAME}" &>/dev/null; then
  ok "Repo ${GITHUB_ORG}/${APP_NAME} already exists"
  if [[ -d "$APP_DIR" ]]; then
    ok "Directory $APP_DIR already exists"
  else
    gh repo clone "${GITHUB_ORG}/${APP_NAME}" "$APP_DIR"
    ok "Cloned existing repo"
  fi
else
  gh repo create "${GITHUB_ORG}/${APP_NAME}" \
    --template "$TEMPLATE_REPO" \
    --private \
    --clone \
    --include-all-branches=false
  ok "Created repo from template"
  # gh repo create --clone puts it in ./$APP_NAME
fi

cd "$APP_DIR"

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 3: Supabase Project
# ═══════════════════════════════════════════════════════════════════════════════
info "Phase 3: Setting up Supabase..."

# Get org ID (skip header rows, grab first org)
SUPABASE_ORG=$(supabase orgs list 2>/dev/null | grep -oE '[a-z]{20}' | head -1 || true)
if [[ -z "$SUPABASE_ORG" ]]; then
  fail "No Supabase org found. Run: supabase login"
fi

# Check if project exists (match by name, extract reference ID)
EXISTING_PROJECT=$(supabase projects list 2>/dev/null | grep -w "$APP_NAME" | grep -oE '[a-z]{20}' | head -1 || true)

if [[ -n "$EXISTING_PROJECT" ]]; then
  SUPABASE_REF="$EXISTING_PROJECT"
  ok "Supabase project already exists (ref: $SUPABASE_REF)"
else
  info "Creating Supabase project (this takes ~1 minute)..."
  CREATE_OUTPUT=$(supabase projects create "$APP_NAME" \
    --org-id "$SUPABASE_ORG" \
    --db-password "$(openssl rand -base64 24)" \
    --region us-east-1 2>&1)
  # Extract ref from output or project list
  SUPABASE_REF=$(echo "$CREATE_OUTPUT" | grep -oE '[a-z]{20}' | head -1 || true)
  if [[ -z "$SUPABASE_REF" ]]; then
    # Wait for project to appear in list
    sleep 10
    SUPABASE_REF=$(supabase projects list 2>/dev/null | grep -w "$APP_NAME" | grep -oE '[a-z]{20}' | head -1 || true)
  fi
  if [[ -z "$SUPABASE_REF" ]]; then
    fail "Could not determine Supabase project ref. Check: supabase projects list"
  fi
  ok "Created Supabase project (ref: $SUPABASE_REF)"
fi

# Set project_id in config.toml so supabase link works
if [[ -f supabase/config.toml ]]; then
  sed -i '' "s/^project_id = .*/project_id = \"$APP_NAME\"/" supabase/config.toml
fi

# Link locally
supabase link --project-ref "$SUPABASE_REF" 2>/dev/null || true
ok "Linked Supabase project"

# Get API keys
API_KEYS_JSON=$(supabase projects api-keys --project-ref "$SUPABASE_REF" -o json 2>/dev/null || true)

if [[ -n "$API_KEYS_JSON" ]]; then
  SUPABASE_ANON_KEY=$(echo "$API_KEYS_JSON" | jq -r '.[] | select(.name == "anon") | .api_key')
  SUPABASE_SERVICE_KEY=$(echo "$API_KEYS_JSON" | jq -r '.[] | select(.name == "service_role") | .api_key')
else
  warn "Could not fetch API keys automatically. Get them from the Supabase dashboard."
  SUPABASE_ANON_KEY=""
  SUPABASE_SERVICE_KEY=""
fi

SUPABASE_URL="https://${SUPABASE_REF}.supabase.co"
SUPABASE_DB_URL="postgresql://postgres.${SUPABASE_REF}:@db.${SUPABASE_REF}.supabase.co:5432/postgres"

# Push migrations
info "Pushing database migrations..."
supabase db push --linked 2>/dev/null && ok "Migrations applied" || warn "Migration push failed — you may need to run 'make migrate' manually"

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 4: Doppler Project
# ═══════════════════════════════════════════════════════════════════════════════
info "Phase 4: Setting up Doppler..."

# Create project (idempotent — errors if exists, which is fine)
doppler projects create "$APP_NAME" 2>/dev/null && ok "Created Doppler project" || ok "Doppler project already exists"

# Set up config
doppler setup --project "$APP_NAME" --config "$DOPPLER_CONFIG" --no-interactive 2>/dev/null || true

# Push project-specific secrets
info "Setting Doppler secrets..."
SECRETS_ARGS=(
  "NEXT_PUBLIC_SUPABASE_URL=${SUPABASE_URL}"
  "NEXT_PUBLIC_SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
  "SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_KEY}"
  "SUPABASE_DB_URL=${SUPABASE_DB_URL}"
  "AI_PROVIDER=openai"
  "AI_MODEL=gpt-4o"
)

doppler secrets set "${SECRETS_ARGS[@]}" \
  --project "$APP_NAME" --config "$DOPPLER_CONFIG" 2>/dev/null \
  && ok "Doppler secrets configured" \
  || warn "Could not set some Doppler secrets — check manually"

# Copy global keys from shared-secrets into this project
info "Copying global keys from shared-secrets..."
for key in OPENAI_API_KEY ANTHROPIC_API_KEY VERCEL_TOKEN SUPABASE_ACCESS_TOKEN NODE_EXTRA_CA_CERTS; do
  val=$(doppler secrets get "$key" --project shared-secrets --config prd --plain 2>/dev/null || true)
  if [[ -n "$val" ]]; then
    doppler secrets set "${key}=${val}" --project "$APP_NAME" --config "$DOPPLER_CONFIG" 2>/dev/null || true
  fi
done
ok "Global keys copied"

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 5: Vercel Project
# ═══════════════════════════════════════════════════════════════════════════════
info "Phase 5: Setting up Vercel..."

# Check for VERCEL_TOKEN (from env, then Doppler)
if [[ -z "$VERCEL_TOKEN" ]]; then
  VERCEL_TOKEN=$(doppler secrets get VERCEL_TOKEN --project "$APP_NAME" --config "$DOPPLER_CONFIG" --plain 2>/dev/null || true)
fi
if [[ -z "$VERCEL_TOKEN" ]]; then
  VERCEL_TOKEN=$(doppler secrets get VERCEL_TOKEN --plain 2>/dev/null || true)
fi
if [[ -z "$VERCEL_TOKEN" ]]; then
  warn "VERCEL_TOKEN not found. Set it: export VERCEL_TOKEN=xxx"
  warn "Create one at: https://vercel.com/account/tokens"
  fail "Cannot continue without VERCEL_TOKEN"
fi

# Auto-detect Vercel scope/team if not set
if [[ -z "$VERCEL_SCOPE" ]]; then
  VERCEL_SCOPE=$(NODE_TLS_REJECT_UNAUTHORIZED=0 vercel teams ls --token "$VERCEL_TOKEN" 2>/dev/null | tail -1 | awk '{print $1}' || true)
  if [[ -n "$VERCEL_SCOPE" ]]; then
    ok "Detected Vercel scope: $VERCEL_SCOPE"
  fi
fi

# Link Vercel project
vcmd link --yes && ok "Vercel project linked" || warn "Vercel link failed — run 'vercel link' manually"

# Push env vars to Vercel
if [[ -f .vercel/project.json ]]; then
  VERCEL_PROJECT_ID=$(jq -r '.projectId' .vercel/project.json)
  VERCEL_ORG_ID=$(jq -r '.orgId' .vercel/project.json)

  info "Pushing env vars to Vercel..."
  push_vercel_env() {
    local key="$1" value="$2"
    # Remove existing, then add (idempotent)
    echo "$value" | vcmd env add "$key" production --force 2>/dev/null || true
  }

  push_vercel_env "NEXT_PUBLIC_SUPABASE_URL" "$SUPABASE_URL"
  push_vercel_env "NEXT_PUBLIC_SUPABASE_ANON_KEY" "$SUPABASE_ANON_KEY"
  push_vercel_env "SUPABASE_SERVICE_ROLE_KEY" "$SUPABASE_SERVICE_KEY"
  push_vercel_env "SUPABASE_DB_URL" "$SUPABASE_DB_URL"
  push_vercel_env "AI_PROVIDER" "openai"
  push_vercel_env "AI_MODEL" "gpt-4o"

  ok "Vercel env vars set"

  # Set GitHub repo secrets for CI
  if [[ -n "$VERCEL_TOKEN" ]]; then
    info "Setting GitHub repo secrets for CI..."
    gh secret set VERCEL_TOKEN --body "$VERCEL_TOKEN" --repo "${GITHUB_ORG}/${APP_NAME}" 2>/dev/null || true
    gh secret set VERCEL_ORG_ID --body "$VERCEL_ORG_ID" --repo "${GITHUB_ORG}/${APP_NAME}" 2>/dev/null || true
    gh secret set VERCEL_PROJECT_ID --body "$VERCEL_PROJECT_ID" --repo "${GITHUB_ORG}/${APP_NAME}" 2>/dev/null || true
    ok "GitHub secrets configured"
  else
    warn "Skipping GitHub secrets — no VERCEL_TOKEN available"
  fi
else
  warn "No .vercel/project.json found — Vercel link may have failed"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 6: Install & Deploy
# ═══════════════════════════════════════════════════════════════════════════════
info "Phase 6: Installing dependencies and deploying..."

pnpm install && ok "Dependencies installed" || fail "pnpm install failed"

# Try direct deploy, fall back to push-to-main
info "Deploying to Vercel..."
if vcmd deploy --prod --yes 2>/dev/null; then
  ok "Deployed to Vercel"
else
  warn "Direct Vercel deploy failed (Zscaler?). Deploying via GitHub Actions..."
  git add -A
  git diff --cached --quiet || {
    git commit -m "chore: initial setup via bootstrap"
    git push origin main
    ok "Pushed to main — GitHub Actions will deploy"
  }
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}━━━ ${APP_NAME} is ready! ━━━${NC}"
echo ""
echo "  GitHub:    https://github.com/${GITHUB_ORG}/${APP_NAME}"
echo "  Supabase:  https://supabase.com/dashboard/project/${SUPABASE_REF}"
echo "  Doppler:   https://dashboard.doppler.com/workplace/projects/${APP_NAME}"
echo "  Vercel:    Check 'vercel' CLI or dashboard"
echo ""
echo "  Local dev: cd ${APP_NAME} && make dev"
echo ""
if [[ -z "$EXISTING_OPENAI" || "$EXISTING_OPENAI" == "" ]]; then
  echo -e "  ${YELLOW}⚠ Don't forget to set your AI API key:${NC}"
  echo "    doppler secrets set OPENAI_API_KEY=sk-xxx --project $APP_NAME --config $DOPPLER_CONFIG"
  echo ""
fi
