# The declaration

One file per service per goatnet. It is named `external-service-<name>.yml` and holds
exactly one mapping, `external_service_<name>` (hyphens become underscores). The file
name and the mapping name must agree — the goatnet's footprint check enforces that.

Adding a service is adding this file. Removing one is marking it `enabled: false`.
Nothing else on the goatnet is edited either way, and that is the whole point.

You write this file and hand it to the platform team. Where it goes in the goatnet's
configuration is their business, not yours; what it must contain is below. This repo's
worked examples are in [`examples/`](../examples/).

## The example

```yaml
external_service_survey_registry:
  name: survey                          # -> survey.<site>.<zone>; one lowercase DNS label
  backend_url: "http://100.127.0.76:8081"   # your host's MESH IP + the port its fence binds
  health_path: /healthz                 # open, no auth; the pre-flight and the status page probe it
  door: authenticated                   # what YOUR OWN fence decides (closed set, below)
  client:                               # optional: the goatnet registers this OAuth2 client for you
    id: oauth2-proxy-survey-registry
    secret_env: SURVEY_OAUTH2_CLIENT_SECRET     # the SAME variable configures your fence
    scopes: [openid, profile, email, groups]    # add offline_access only if your fence refreshes
    redirect_path: /oauth2/callback
    token_lifespan: 8h                  # pin to your fence's cookie lifetime when it holds no refresh token
  status:                               # optional: the status-page row; defaults derive from the fields above
    name: "Field survey registry"
    desc: "Records for a two-week field survey: sites, teams and daily returns."
    access: public                      # what the page shows: any authenticated identity gets past the door
    category: exercise
    icon: clipboard
  owner: survey-office
  retire_after: "2035-10-15"            # a TEMPORARY service: the footprint check is strict, and it cannot be applied after this date
  enabled: true                         # false = withdrawn
```

## Field by field

| Field | Required | Meaning |
|---|---|---|
| `name` | yes | The hostname label, and the service's own label. One lowercase DNS label |
| `hostnames` | no, default `[name]` | Several endpoint names from one declaration, each your own: `<name>`, `<name>-<surface>`, or nested one level as `<surface>.<name>`. Flat names are covered by the goatnet's `*.<site>.<zone>` certificate name; nesting adds one `*.<name>.<site>.<zone>`. No wildcard DNS — each name you want is a line in this list |
| `tls` | no, default `edge` | `edge`: the goatnet terminates TLS and proxies to `backend_url`. `partner`: you terminate on your own host and `mesh_ip` is required |
| `backend_url` | in `edge` mode | `http(s)://<mesh ip>:<port>`. A non-mesh address is refused |
| `mesh_ip` | in `partner` mode | Your host's `100.64/10` address. Every hostname resolves straight to it |
| `acme_delegate` | in `partner` mode, and refused in `edge` | A hostname in a DNS zone **you** control, outside the goatnet's zone. The goatnet publishes `_acme-challenge.<label>.<site>.<zone>` pointing at it, so you get a publicly trusted certificate with Let's Encrypt's DNS-01 challenge by writing the TXT record in your own DNS. Your host never serves anything publicly |
| `mesh_peer` | no | Your host's NetBird peer name (`netbird status`). When set, nothing is published unless the peer at `mesh_ip` has this name, so a re-enrolled host is caught before its names point at the wrong address |
| `health_path` | no, default `/` | Answers 200 without a session. The pre-flight, the status page and any probe read it |
| `door` | yes | One of `group-gated`, `authenticated`, `in-app`, `mesh-only`. Recorded so a reader knows what your own fence decides; the goatnet enforces nothing here |
| `client` | no | When present, the goatnet registers an OAuth2 client with these scopes and redirect, secret from `$secret_env`, lifespans pinned when `token_lifespan` is set. Absent means you register your own, or have none |
| `status` | no | Status-page row fields (`id`, `name`, `desc`, `kind`, `access`, `category`, `icon`, `link_path`, `probe_front_door`, `expect_codes`). A row the goatnet already publishes for the same hostname wins |
| `traefik_name` | no, default `ext-<name>` | The key the goatnet's edge uses for your route and backend |
| `owner` | yes | Who to call. Free text |
| `retire_after` | no | `YYYY-MM-DD`. Marks a temporary service: the footprint check becomes strict, and the service cannot be applied after the date |
| `guard_tokens` | no, and set it on a temporary service whose name is also a hostname | Strings the footprint check searches for; defaults to the file's `<name>` part, its underscore form and `external_service_<name>`. None may occur inside a hostname: the generated mesh zone lists every hostname, so such a token fails the check on the pull request that adds the service. Use `[external-service-<name>, external_service_<name>]` |
| `enabled` | no, default `true` | `false` withdraws the service |

## What is checked, exactly

`tools/validate-declaration.py` applies the same rules the goatnet does, so you can see a
refusal before anyone else does.

| Rule | Check |
|---|---|
| name | matches `^[a-z0-9][a-z0-9-]{0,62}$` |
| hostnames | absent, or a non-empty list; every entry is `<name>`, `<name>-<surface>` or `<surface>.<name>`, and no label exceeds 63 characters |
| name length | every `<entry>.<site>.<zone>` is at most 253 characters |
| tls | `edge` or `partner` |
| backend_url (edge) | starts `http://` or `https://`; hostname matches `^100\.(6[4-9]\|[7-9][0-9]\|1[01][0-9]\|12[0-7])\.` (100.64.0.0/10) |
| mesh_ip (partner) | in 100.64.0.0/10 |
| door | in `[group-gated, authenticated, in-app, mesh-only]` |
| client | absent, or has both `id` and `secret_env` |
| retire_after | absent, or `YYYY-MM-DD`; must not be before today (UTC) to apply |
| applying | the mapping exists and `enabled` is not false |
| withdrawing | the mapping is gone or `enabled: false`; refused otherwise |


## What the goatnet derives from it

| Derived | What it is |
|---|---|
| `https://<entry>.<site>.<zone>` | the hostname you publish, one per entry in `hostnames` |
| certificate | nothing per hostname: flat names ride the goatnet's `*.<site>.<zone>`; a service that nests adds `*.<name>.<site>.<zone>` once. In `tls: partner`, nothing |
| issuer `https://oauth2.<site>.<zone>/` | the string your service compares `iss` against, trailing slash included |
| JWKS `https://oauth2.<site>.<zone>/.well-known/jwks.json` | where your service fetches the signing keys |
| OAuth2 client | `client.id`, scopes, one redirect URI `https://<hostname><redirect_path>`, `client_secret_post`, audience `[client.id]`, lifespans when pinned |
| edge route | one route carrying every hostname, mesh-only, backend `backend_url`, and every hostname on the goatnet's certificate. Nothing at all in `tls: partner` mode |
| DNS records | one per hostname, pointing at the goatnet's edge in `edge` mode and at your `mesh_ip` in `partner` mode |
| status rows | one per LISTED hostname, on the goatnet status page's **External services** page, grouped under your `owner`. Past the first, the row is suffixed by its own label, with your service name dropped from a nested entry: `api.northwind` under `northwind` reads `northwind platform (api)` |

Run `tools/validate-declaration.py examples/hello-external.zagros.yml` to see all of
these for this repo's declaration.

## On the status page

Your service is listed on the goatnet status page's **External services** page
(`https://isitup.<site>.<zone>/external`), grouped under your `owner`, with a
line saying you host it. It is not listed among the goatnet's own services, so
nobody mistakes it for one the goat core team runs, and a problem with it
reaches you.

You decide which of your hostnames are listed, and how each is probed:

```yaml
  status:
    name: "Northwind platform"
    list: true                      # the default for every hostname; false lists none of them
    lifecycle: live                 # live (default) | planned | retiring
    hostnames:                      # per-hostname overrides, keyed by the `hostnames:` entry
      api.northwind: { list: false }                 # an API nobody browses: no row, no probe
      heartbeat.northwind: { health_path: /health }  # this surface's own probe path
      keycloak.northwind: { lifecycle: planned }     # declared, not up yet
```

| Field | Default | Meaning |
|---|---|---|
| `status.list` | `true` | Whether each hostname gets a row. `false` lists none of them |
| `status.lifecycle` | `live` | `planned`: shown with a "planned" label, not counted in the page's status banner and not alerted on — use it while a surface is not up yet, so it does not show as a failure. `retiring`: the same, for a surface on its way out |
| `status.hostnames.<entry>` | none | Overrides for ONE hostname: `list`, `lifecycle`, `health_path`, `name`, `desc`, `link_path`, `kind`, `expect_codes`. The key must be an entry of `hostnames:` |

`hostnames:` itself does not change: every entry still gets its DNS record and
its place on the certificate, listed or not. Listing is a status-page choice
only. Without a per-hostname `health_path`, every hostname is probed on the
declaration's one `health_path`, so a platform whose surfaces answer on
different paths should say so here. The validator refuses a `status.hostnames`
key that is not one of your hostnames, and an unknown lifecycle.
