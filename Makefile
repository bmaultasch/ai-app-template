.PHONY: new dev build deploy migrate secrets-sync

# Bootstrap a new app from this template
new:
	@if [ -z "$(filter-out $@,$(MAKECMDGOALS))" ]; then \
		echo "Usage: make new <app-name>"; \
		exit 1; \
	fi
	./bootstrap.sh $(filter-out $@,$(MAKECMDGOALS))

# Local development with secrets injected
dev:
	doppler run -- pnpm dev

# Build with secrets injected
build:
	doppler run -- pnpm build

# Deploy to Vercel production
deploy:
	doppler run -- vercel deploy --prod --yes

# Push Supabase migrations
migrate:
	supabase db push --linked

# Sync Doppler secrets to Vercel env vars
secrets-sync:
	@echo "Syncing Doppler secrets to Vercel..."
	@for key in NEXT_PUBLIC_SUPABASE_URL NEXT_PUBLIC_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY SUPABASE_DB_URL AI_PROVIDER AI_MODEL OPENAI_API_KEY ANTHROPIC_API_KEY; do \
		val=$$(doppler secrets get $$key --plain 2>/dev/null); \
		if [ -n "$$val" ]; then \
			echo "$$val" | vercel env add $$key production --force 2>/dev/null || true; \
			echo "  ✓ $$key"; \
		fi; \
	done
	@echo "Done."

# Catch-all for app name argument to 'make new'
%:
	@:
