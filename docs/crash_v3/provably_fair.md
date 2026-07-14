# Crash Rocket V3 fairness specification

For each round the engine generates a cryptographically random 32-byte server
seed. PostgreSQL publishes `SHA256(server_seed)` before betting and freezes the
round's nonce, client seed, edge, cap, and growth rate.

The result digest is:

```text
HMAC_SHA256(server_seed, UTF8(client_seed + ":" + nonce))
```

Interpret the first 13 hexadecimal characters as an unsigned 52-bit integer
`n`. The uniform value is `u = n / 2^52`, so `0 <= u < 1`; this uses no modulo
operation and therefore introduces no modulo bias.

With edge `e = house_edge_bps / 10000`, the raw point is
`(1 - e) / (1 - u)`. The authoritative multiplier is:

```text
floor(min(maximum_multiplier, max(1.00, raw_point)) * 100) / 100
```

The display curve is independently timed from the server flight timestamp:

```text
floor(min(cap, exp(growth_rate * elapsed_seconds)) * 100) / 100
```

Cash-out is valid only while the round is `flying` and the server-calculated
curve value is strictly below the committed crash multiplier. Flutter renders
the same curve only as prediction; the RPC result always wins.

After settlement the server seed is revealed. `crash_v3_verify_round` recomputes
the seed hash, HMAC, and crash point and returns one `verified` boolean. Known
SHA-256 and HMAC-SHA256 vectors are exercised by the SQL contract test.
