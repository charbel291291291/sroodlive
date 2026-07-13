# Phase 3 Financial Lineage Contract

Every financial action has one immutable `operation_id` and a scoped unique
`idempotency_key`. The server derives `actor_user_id` from `auth.uid()` and records
`beneficiary_user_id`, `agency_id`, optional `agent_id`, `request_id`,
`transaction_id`, `correlation_id`, operation type/status and timestamps.

Amounts are captured independently as currency, coins, diamonds and fiat, with
the applied exchange rate and immutable metadata/policy version. Completion must
atomically produce the authorization decision, transaction, wallet/credit
mutation, balanced ledger entries and audit event. A reversal never edits posted
history: it creates a new operation and compensating entries linked by
`reversal_of`, then timestamps the original as reversed only through a controlled
transition.

Lifecycle: request -> authorization -> locked transaction -> wallet/Agency credit
mutation -> commission calculation -> settlement allocation -> balanced ledger
posting -> audit event -> stored idempotent result. Any failure rolls back the
entire transaction.
