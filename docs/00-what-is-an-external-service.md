# What is an external service?

A plain-language orientation. No prior goat knowledge assumed.

## The setting

A goatnet is a private mesh with its own identity plane. People sign in once at the
goatnet's identity provider (Ory Hydra) and receive an id_token that names them: a
stable subject, an email, their groups, and on some goatnets `aff.id`, the organisation
they belong to. The services the goatnet runs itself use that token.

An **external service** is one the goatnet does not build or deploy. Three things are
true of it:

- **off-box**: it runs on its own host, which joins the mesh as a machine
- **non-core**: the platform team does not own it and it is not in the platform's
  release ladder
- **often temporary**: an event registry, a demo, a vendor tool that lives for one
  event

It still wants three things from the goatnet: sign-in with goatnet identities, a name on
the goatnet's edge (`https://<name>.<site>.<zone>`), and a row on the status page.

## The trust rule

The goatnet authenticates. Your service authorizes. A token's claims grant nothing on
their own.

In practice: your service verifies the token's signature, issuer, audience and expiry
against the goatnet's published keys. Then it looks the person up in its own records
(a roster) and decides. A claim such as `aff.id` is evidence your service may use to
roster somebody, never a grant by itself. When a claim and the roster disagree, the
roster decides and the disagreement is logged.

## Why the fence lives on your host

Your host joins the mesh in the `EXTERNAL-INFRA` tier. Every role group can reach that
tier directly, on any port. A sign-in fence in front of your service on the goatnet's
edge would therefore be a fence with a gap beside it: anyone on the mesh could walk
around it to the host.

So the fence is on your own host. Either an oauth2-proxy sidecar signs people in and
forwards the id_token, or your service does the flow natively. Your service binds its
mesh IP, never `0.0.0.0`. Mesh membership is the outer gate; the token check is the
inner one.

## The boundary rule

A temporary service's name may appear in the goatnet's configuration only in its own
declaration file.

A service named in several places needs a teardown that visits every one of them, and
nobody keeps that list. The golden path makes the whole goatnet-side footprint one file, and a CI check on the
goatnet's configuration fails any change that names a temporary service anywhere else.
That is what makes "set `enabled: false` and withdraw it" a complete teardown rather
than a hopeful one.

## What this demo proves and what it represents

The service code, the declaration rules and the footprint-check logic run here for real.
The issuer is simulated: a small program mints tokens on request so your service's checks
can be exercised without a goatnet. Applying a declaration, rendering the edge and running
the real CI check all happen on the goatnet, not here. The full accounting is in
[honesty-matrix.md](honesty-matrix.md).
