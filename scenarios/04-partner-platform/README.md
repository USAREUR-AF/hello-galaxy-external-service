# 04 — a platform with several endpoints

The first three scenarios follow one service on one name, with the goatnet's edge in
front of it. Most platforms do not arrive that way. One turns up wanting `api`, `audit`,
`authentication`, `device`, `provisioning`, `reports`, `settings`, `heartbeat`, `policy`,
`user`, `monitoring`, a demo console and `keycloak` — thirteen surfaces — and asks
whether the goatnet can host that.

It can, and two questions decide the shape: **where the names hang**, and **who holds a
key**.

## Where the names hang

Every `hostnames:` entry belongs to your service, in one of three shapes:

| Entry | Publishes | Certificate name that covers it |
|---|---|---|
| `northwind` (your `name`) | `northwind.<site>.<zone>` | the goatnet's `*.<site>.<zone>` |
| `northwind-api` | `northwind-api.<site>.<zone>` | the goatnet's `*.<site>.<zone>` |
| `api.northwind` | `api.northwind.<site>.<zone>` | `*.northwind.<site>.<zone>`, added once for you |

`api`, `policy`, `user` and `monitoring` are words every platform wants. Claimed bare,
they would sit in a namespace the whole goatnet shares and the second platform could not
have them. Prefixed or nested under your own name, they belong to you and the name says
so. A bare `api`, another service's name, and nesting two levels deep are all refused:

```yaml
hostnames:
  - northwind               # the front door
  - northwind-audit         # flat: costs the certificate nothing
  - api.northwind           # nested: your service adds *.northwind.<site>.<zone>, once
  - demo-console.northwind  # one level only -- demo.console.northwind is refused
```

**Why one level, and why prefer flat.** The certificate the goatnet serves you under holds
at most 100 names and is shared with its sign-in service. So it carries one wildcard for
every flat name of every service, plus one per service that nests. A wildcard matches
exactly one label, which is why nesting stops at one level. Flat names are free; nesting
costs one certificate name, so nest when the separation is worth it.

**There is still no wildcard DNS.** The wildcard is on the certificate only. Every name
is a record the goatnet writes out in full, so every name you want is a line in this list.
In return, nothing resolves that nobody declared.

## Who holds a key

| Shape | What you run | What the goatnet publishes | When it fits |
|---|---|---|---|
| One name, paths behind it | Your own reverse proxy splitting `/api`, `/audit`, … | One record, one row, one route, one certificate name | Fewest moving parts. Reach for this first |
| Several names, the goatnet terminates (`tls: edge`) | Just the service | One route carrying every name, every name on the goatnet's mesh-only certificate, one status row each | You need distinct hostnames and are content behind the goatnet's edge |
| Several names, you terminate (`tls: partner`) | The service **and** TLS | Mesh DNS records pointing at your host, and public `_acme-challenge` records pointing into your own zone (`acme_delegate`). No route, no backend, no certificate | You must serve your own certificate, or your platform terminates TLS itself |

## What this scenario shows

`examples/northwind-platform.zagros.yml` is the third shape: fourteen surfaces under
one name, one declaration, you terminating. The script previews exactly what the goatnet
derives from it, then shows the same declaration switched to `edge` so the difference is
visible side by side rather than described. Then the refusals: partner mode with no
`mesh_ip`, partner mode with no usable `acme_delegate`, a delegation in edge mode, a
malformed `mesh_peer`, an unknown `tls` value, and six hostnames that are not yours or
nest too deep.
Last, what the certificate carries for the flat and the nested shapes.

```bash
bash scenarios/04-partner-platform/run.sh
```

## The thing worth understanding

`tls: partner` is not "the same but simpler". It moves a control:

- the goatnet's edge is no longer in the path, so **its mesh-only allowlist is not the
  gate**. Reachability control lives on your host.
- The status page can only report what your health endpoint says.
- The goatnet never issues a certificate for a name you serve, and never holds your key.
  You get one yourself from Let's Encrypt with the **DNS-01** challenge: the goatnet
  publishes `_acme-challenge.<label>.<site>.<zone>` as a CNAME to your `acme_delegate`,
  and your ACME client writes the TXT record in your own DNS. Your host never serves
  anything publicly, not even for validation, and renewal needs nobody from the goatnet.
  The service names themselves still resolve only inside the mesh.

Everything else is unchanged. It is still one declaration, still one `enabled: false` to
withdraw, and the footprint check still proves a temporary service left nothing behind.

## A trap this scenario points at

The footprint check searches the goatnet's configuration for a temporary service's
guard tokens and fails on any hit outside its declaration. The goatnet's mesh zone is
**generated** from the declarations, so it lists every hostname — which means a token
that occurs inside a hostname (`northwind` inside `api.northwind`) fails the check on the very
pull request that adds the service. Guard on names that appear nowhere else:
`[external-service-northwind, external_service_northwind]`. The validator now refuses the
other shape, and the goatnet's existing temporary services already follow it.
