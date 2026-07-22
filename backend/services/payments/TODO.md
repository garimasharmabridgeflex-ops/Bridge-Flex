# functions-payments — TODO

This codebase is a deliberate stub. See `ARCHITECTURE.md` v2 §5 for the full
design rationale — summary: payments is deferred, and when it's built it
should be **Stripe Connect** (Express accounts for nurseries and staff), not
the "Run Payments with Stripe" Firestore extension, because Bridge Flex is a
marketplace that pays out two different parties, not a single business
selling to one customer.

## What exists today

- `POST /createPayout` — a single placeholder HTTP handler that responds
  `501 PAYMENTS_NOT_YET_BUILT`. No Stripe SDK dependency, no API keys, no
  Stripe account required. Its only job is to prove the three-service
  deploy/call wiring (core → payments) end to end before any real payments
  logic exists.
- `shifts.paymentStatus` (owned conceptually by this service, physically a
  field on the `shifts` doc core writes) already exists in the core data
  model — see ARCHITECTURE.md v2 §2/§5.
- `transactions/{transactionId}` — collection name reserved in
  `firestore.rules` (deny-all), no documents, no code here reads or writes it
  yet.

## What real payments work needs to do here, when it's time

1. Add the Stripe Go SDK (`github.com/stripe/stripe-go`) to this module only
   — core and communication must never depend on it (§1 — dependency
   isolation is the whole point of a separate codebase).
2. Express account onboarding: an `onCall`-equivalent HTTP endpoint that
   creates/links a Stripe Connect Express account per nursery/staff `uid`,
   storing the returned `stripeConnectAccountId` — decide where (a new field
   on `profiles`, function-only, never client-writable, mirroring the
   `dbsStatus` pattern).
3. Payout/charge flow: replace the `POST /createPayout` stub with real logic
   that reads the relevant `shifts` doc, creates a Stripe transfer/charge,
   and writes a `transactions/{transactionId}` doc — this is the *only*
   place `transactions` docs get created.
4. Webhook handler: a new `POST /stripeWebhook` `onRequest`-equivalent
   endpoint, signature-verified using Stripe's webhook secret, updating
   `shifts/{id}.paymentStatus` and the matching `transactions` doc on
   payment-succeeded/failed events. Test locally with the Stripe CLI's
   `stripe listen --forward-to` pointed at this handler's local port — see
   ARCHITECTURE.md v2 §7 for why that's the recommended approach over a
   hand-rolled mock client once this stage starts.
5. Resolve the open product question from ARCHITECTURE.md v2 §8 item 3
   (employer-of-record) before deciding the exact Connect topology — it
   determines whether nurseries or Bridge Flex is the payer of record.
6. None of the above requires the Blaze plan to *develop* (Stripe test mode
   + local webhook forwarding work against emulated Firestore same as any
   other function) — only a real deploy does, same constraint as the rest of
   this project.
