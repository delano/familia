# Migrating to `IDENTIFIER_SECRET`

`Familia::VerifiableIdentifier` reads its HMAC secret from one of two environment variables. `IDENTIFIER_SECRET` is the preferred name going forward; `VERIFIABLE_ID_HMAC_SECRET` remains supported and is not deprecated. (#423)

## Precedence

| `VERIFIABLE_ID_HMAC_SECRET` | `IDENTIFIER_SECRET` | Secret used |
|---|---|---|
| nonblank | any | `VERIFIABLE_ID_HMAC_SECRET` |
| unset or blank | nonblank | `IDENTIFIER_SECRET` |
| unset or blank | unset or blank | raises `KeyError` on first use |

"Blank" means empty or whitespace-only. A blank legacy value falls through to `IDENTIFIER_SECRET` instead of raising, so container setups that inject `VERIFIABLE_ID_HMAC_SECRET=${VERIFIABLE_ID_HMAC_SECRET:-}` keep working when only `IDENTIFIER_SECRET` is set. The value is used exactly as found in the environment; it is not stripped.

The `KeyError` is raised lazily on the first `generate_verifiable_id` / `verified_identifier?` / `secret_key` call and is not memoized, so fixing the environment and calling again succeeds.

## Removing the downstream bridge

Applications that carried this line to feed the legacy name from the new one:

```ruby
ENV['VERIFIABLE_ID_HMAC_SECRET'] ||= ENV['IDENTIFIER_SECRET']
```

can delete it once on this release. Familia performs the same fallback itself.

## Generating a secret

```bash
openssl rand -hex 32
export IDENTIFIER_SECRET="<the generated value>"
```

## Warning: keep both variables identical during a rollout

Verifiable identifiers are only verifiable with the secret that generated them. If a deployment sets both variables at any point during a rollout, they MUST hold the same value; otherwise instances that resolve to `VERIFIABLE_ID_HMAC_SECRET` and instances that resolve to `IDENTIFIER_SECRET` will reject each other's identifiers. Rotating the value invalidates every previously generated identifier.
