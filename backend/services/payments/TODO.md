# functions-payments — Architecture & Implementation Notes

This codebase is a deliberate stub isolated from `core` and `communication`.

## Architecture Note (October 2026 Specification)

**Stripe Connect Express is NOT used.**
KFlex operates as an employer / agency paying practitioners directly through **internal UK PAYE payroll** (supported via CSV exports for HMRC Basic PAYE Tools in Phase 8). Practitioners are never paid out via Stripe Connect transfers.

Instead, this service is responsible for:
1. **Nursery Subscriptions:** Collecting £199/mo (Standard), £299/mo (Premium), and £9.99 (Pay As You Go booking fees) using Stripe Billing / Hosted Checkout.
2. **Nursery Staffing Invoices:** Collecting weekly staffing charges based on approved timesheet hours, supporting both online Stripe card/Bacs payments and manual bank transfers.
3. **Webhooks & Invoicing:** Processing `invoice.paid`, `payment_intent.succeeded`, and failed payment events; updating `subscriptions` and `invoices` via the transactional outbox pattern.

## What exists today

- `POST /createPayout` — placeholder HTTP handler responding `501 PAYMENTS_NOT_YET_BUILT`.
- `shifts.paymentStatus` — field on the `shifts` doc for tracking payment state.
- `transactions/{transactionId}` — collection name reserved in `firestore.rules` (deny-all rules).

## Requirements for Phase 10 (Stripe Phase)

1. Add the official Stripe Go SDK (`github.com/stripe/stripe-go/v81`) to this module only.
2. Store live Stripe API keys and webhook secrets in Google Cloud Secret Manager (never in code).
3. Implement `POST /createSubscriptionCheckout` for nursery plan activations.
4. Implement `POST /stripeWebhook` with cryptographic signature verification (`webhook.ConstructEvent`).
5. Ensure zero credit card numbers or banking credentials ever touch KFlex databases (hosted Stripe surfaces only).
