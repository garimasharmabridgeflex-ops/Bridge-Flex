#!/usr/bin/env bash
# Deploys functions-payments (Stripe sandbox/production billing).
#
# Secrets live in Google Cloud Secret Manager, never in this repo:
#   stripe-secret-key, stripe-webhook-secret,
#   stripe-price-standard, stripe-price-premium, stripe-price-payg
# See backend/README.md "Card payments (Stripe)" for the one-time setup.
#
# Usage: PROJECT_ID=kvision-503115 ./deploy.sh
set -euo pipefail
cd "$(dirname "$0")"

: "${PROJECT_ID:?Set PROJECT_ID to your real Firebase project id, e.g. PROJECT_ID=my-prod-project ./deploy.sh}"
: "${REGION:=europe-west2}"
: "${GO_RUNTIME:=go125}"
: "${APP_PUBLIC_URL:=https://${PROJECT_ID}.web.app}"

SECRETS="STRIPE_SECRET_KEY=stripe-secret-key:latest"
SECRETS="${SECRETS},STRIPE_WEBHOOK_SECRET=stripe-webhook-secret:latest"
SECRETS="${SECRETS},STRIPE_PRICE_STANDARD=stripe-price-standard:latest"
SECRETS="${SECRETS},STRIPE_PRICE_PREMIUM=stripe-price-premium:latest"
SECRETS="${SECRETS},STRIPE_PRICE_PAYG=stripe-price-payg:latest"

deploy_http() { # entry-point
  echo "==> functions-payments: deploying $1 (HTTP)"
  gcloud functions deploy "$1" \
    --gen2 --runtime="$GO_RUNTIME" --region="$REGION" --project="$PROJECT_ID" \
    --source=. --entry-point="$1" \
    --trigger-http --allow-unauthenticated \
    --set-secrets="$SECRETS" \
    --set-env-vars="APP_PUBLIC_URL=${APP_PUBLIC_URL}" \
    --quiet
}

# Stripe cannot present a Firebase token, so the webhook is authenticated by
# its request signature (STRIPE_WEBHOOK_SECRET) instead — see function/webhook.go.
deploy_http StripeWebhook
deploy_http CreateSubscriptionCheckout
deploy_http CreateBillingPortalSession
deploy_http CreatePayout

echo "functions-payments: 4 functions deployed."
