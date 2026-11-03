# 02 — Sign in and authorize

The provider authenticates, the service authorizes. This scenario starts a simulated
issuer and the real hello service, mints tokens and walks every relying-party rule.

```bash
bash scenarios/02-sign-in-and-authorize/run.sh
```

Both processes are stopped on exit, including Ctrl-C.

## The steps

| Step | Token | Expected | Why |
|---|---|---|---|
| (a) | rostered vendor, verified email | **200** and `/api/me` | the roster row decides; the principal is returned |
| (b) | same person, `email_verified: false` | **403** | an unverified email is refused; the fix is at the identity provider, not the service |
| (c) | unrostered, `aff.id` = active vendor, fresh snapshot | **200**, audit `auto_rostered` | the org snapshot vouches for the org; the service rosters the person and says so |
| (d) | unrostered, `aff.id` unknown to the snapshot | **403** | fail closed: authenticated but not on the roster |
| (d2) | unrostered, `aff.id` = inactive vendor | **403** | known is not enough; the org must be an active vendor |
| (e) | unrostered, active vendor, snapshot 48h old | **403** | a stale snapshot switches auto-roster off |
| (f) | rostered, `aud` = another client | **401** | a token minted for another service is not for this one |
| (g) | rostered, `iss` without the trailing slash | **401** | `iss` is an exact string match |
| (h) | rostered, `aff.id` disagrees with the roster row | **200**, audit `org_mismatch` | the roster decides; the claim is evidence and is logged |
| (i) | rostered, expired | **401** | `exp` is checked |

Every refusal body names who can fix it.

## Why the trailing slash matters (step g)

The goatnet's Hydra is configured with issuer `https://oauth2.<site>.<zone>/`.
Every token it signs carries exactly that string in `iss`. OpenID Connect requires the
relying party to compare `iss` as a string, so a service configured with
`https://oauth2.<site>.<zone>` (no slash) refuses every token, and the error looks
like a bad key or a bad clock. The goatnet prints the issuer with its slash for this reason.
The service here also warns at start when its configured issuer has no slash.

## What is real and what is simulated

The service code is real and is what you would run. The issuer is simulated: it
signs real RS256 tokens and publishes a real JWKS, so the verification is real, but it
has no login flow and mints whatever claims it is asked for. See
[docs/honesty-matrix.md](../../docs/honesty-matrix.md).
