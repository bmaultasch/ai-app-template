# One-Time Machine Setup

Run these once on a new machine. After this, `./bootstrap.sh <app-name>` handles everything.

## 1. Install tools

```bash
# Package manager
npm install -g pnpm

# CLI tools
brew install gh jq dopplerhq/cli/doppler supabase/tap/supabase

# Vercel CLI
npm install -g vercel
```

## 2. Authenticate

```bash
gh auth login
supabase login
doppler login
vercel login
```

## 3. Zscaler certificate (corporate network)

If you're behind Zscaler, ensure the cert is at `/Users/brandon/zcert/zscaler.pem` and add to your shell profile:

```bash
echo 'export NODE_EXTRA_CA_CERTS=/Users/brandon/zcert/zscaler.pem' >> ~/.zshrc
source ~/.zshrc
```

## 4. Create a Vercel token

1. Go to https://vercel.com/account/tokens
2. Create a token with full access
3. Save it in Doppler for your first project:

```bash
doppler secrets set VERCEL_TOKEN=your-token-here --project <your-first-project> --config prd
```

## 5. Bootstrap your first app

```bash
./bootstrap.sh my-first-app
cd my-first-app
make dev
```

That's it. Every new project after this is just `./bootstrap.sh <name>`.
