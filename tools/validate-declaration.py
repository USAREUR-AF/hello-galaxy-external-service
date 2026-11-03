#!/usr/bin/env python3
"""validate-declaration.py — check an external-service declaration the way the
goatnet checks it, and preview what the goatnet derives from it.

The well-formedness rules are the goatnet's own, copied: the closed set of
`door` values, the mesh-address rule for a backend, the one-DNS-label rule for
every hostname, the `tls` mode, the date rule for `retire_after`, and the
ordering that refuses a removal while the declaration is still enabled. The
derived values follow what the goatnet publishes: the lines a service owner
configures from, the OAuth2 client it registers, the edge route and certificate
names, the mesh DNS records and the status-page rows.

THIS IS A PREVIEW. The goatnet does the real rendering; this tool reproduces the
shapes so a reader can see them without a goatnet.

usage: validate-declaration.py <declaration.yml> [--state present|absent]
         [--site-id zagros] [--site-dns-zone <zone>] [--mesh-ip-a <ip>] [--today YYYY-MM-DD]
exit:  0 the goatnet would accept the state, 1 it would refuse, 2 usage.
"""
import argparse
import datetime
import re
import sys
from urllib.parse import urlsplit

try:
    import yaml
except ImportError:
    sys.exit("validate-declaration: PyYAML is required (pip install -r requirements.txt)")

DOOR_VALUES = ["group-gated", "authenticated", "in-app", "mesh-only"]          # the closed set
LABEL = r"[a-z0-9][a-z0-9-]{0,62}"
NAME_RE = re.compile("^%s$" % LABEL)                                          # `name` is ONE label
# A `hostnames` entry belongs to its service and is flat or nested ONE level:
# <name>, <name>-<surface>, or <surface>.<name>. Flat names are covered by the
# goatnet's *.<site>.<zone> certificate name; a service that nests adds one
# *.<name>.<site>.<zone>. A wildcard matches exactly one label, which is why
# nesting stops at one level, and why certificate size grows with the number of
# services that nest rather than with hostnames.


def hostname_ok(h, name):
    if not isinstance(h, str) or not isinstance(name, str):
        return False
    if any(len(part) > 63 for part in h.split(".")):
        return False
    n = re.escape(name)
    return re.fullmatch(r"%s(-[a-z0-9-]+)?|%s\.%s" % (n, LABEL, n), h) is not None



MAX_FQDN = 253                                                                # RFC 1035 presentation length
MESH_RE = re.compile(r"^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.")         # 100.64.0.0/10
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
# `acme_delegate` — a hostname in a zone YOU control. The goatnet points each
# certificate name's _acme-challenge record at it, so you answer ACME DNS-01 there.
DELEGATE_RE = re.compile(r"^([a-z0-9_]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\.?$")
PEER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$")
# The status page's listing controls. `status.list` is the default
# for every hostname; `status.hostnames` overrides it, and a few row fields, per
# hostname. Only the status page reads `status:`, so none of this touches DNS,
# the certificate or the route.
LIFECYCLES = ["live", "planned", "retiring"]
PER_HOST_KEYS = {"list", "lifecycle", "health_path", "name", "desc", "link_path", "kind", "expect_codes"}


class Refuse(Exception):
    pass


def load(path):
    with open(path) as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise Refuse("%s: not a mapping" % path)
    keys = [k for k in data if k.startswith("external_service_")]
    if len(keys) != 1:
        raise Refuse("%s: must define exactly one external_service_* mapping, found %s" % (path, keys))
    body = data[keys[0]] or {}
    if not isinstance(body, dict):
        raise Refuse("%s: %s must be a mapping" % (path, keys[0]))
    return keys[0], body


def hostnames_of(ext):
    """`hostnames:` (default [name]) — one declaration, several labels."""
    hs = ext.get("hostnames") or [ext.get("name")]
    return hs if isinstance(hs, list) else [hs]


def status_problem(ext, hosts):
    """The first thing wrong with the status-page listing controls, or None."""
    st = ext.get("status")
    if st is None:
        return None
    if not isinstance(st, dict):
        return "`status` must be a mapping"
    if "list" in st and not isinstance(st["list"], bool):
        return "`status.list` is true or false"
    if "lifecycle" in st and st["lifecycle"] not in LIFECYCLES:
        return "`status.lifecycle` is one of %s" % LIFECYCLES
    per = st.get("hostnames", {})
    if not isinstance(per, dict):
        return "`status.hostnames` maps a `hostnames:` entry to its overrides"
    for h, o in per.items():
        if h not in hosts:
            return "`status.hostnames` names `%s`, which is not in `hostnames:` %s" % (h, hosts)
        if not isinstance(o, dict):
            return "`status.hostnames.%s` must be a mapping" % h
        extra = set(o) - PER_HOST_KEYS
        if extra:
            return "`status.hostnames.%s` has %s; allowed: %s" % (h, sorted(extra), sorted(PER_HOST_KEYS))
        if "list" in o and not isinstance(o["list"], bool):
            return "`status.hostnames.%s.list` is true or false" % h
        if "lifecycle" in o and o["lifecycle"] not in LIFECYCLES:
            return "`status.hostnames.%s.lifecycle` is one of %s" % (h, LIFECYCLES)
    return None


def tls_mode(ext):
    """`tls:` — edge (the goatnet terminates, default) or partner (you do)."""
    return str(ext.get("tls", "edge")).lower()


def check_present(var, ext, a):
    """The goatnet's checks before applying, same conditions, same message."""
    if not ext or not bool(ext.get("enabled", True)):
        raise Refuse("%s is not declared (or is enabled: false). A declaration is one file named"
                     " external-service-%s.yml holding one `%s:` mapping — docs/the-declaration.md has the schema."
                     % (var, var[len("external_service_"):].replace("_", "-"), var))
    mode = tls_mode(ext)
    hosts = hostnames_of(ext)
    edge = mode == "edge"
    ok = (
        isinstance(ext.get("name"), str) and NAME_RE.match(ext["name"])
        and isinstance(hosts, list) and len(hosts) > 0
        and all(hostname_ok(h, ext.get("name")) for h in hosts)
        and mode in ("edge", "partner")
        # edge: the goatnet proxies, so it needs a mesh backend. partner: it renders
        # no backend at all, so backend_url is not required — mesh_ip is.
        and (not edge or (isinstance(ext.get("backend_url"), str)
                          and re.match(r"^https?://", ext["backend_url"])
                          and MESH_RE.match(urlsplit(ext["backend_url"]).hostname or "")))
        and (edge or (isinstance(ext.get("mesh_ip"), str) and MESH_RE.match(ext["mesh_ip"])))
        # partner: the only publicly trusted certificate you can get for these names,
        # without serving anything publicly, is DNS-01 answered in a zone you control.
        and (edge or (isinstance(ext.get("acme_delegate"), str) and DELEGATE_RE.match(ext["acme_delegate"].lower())
                      and not in_zone(ext["acme_delegate"], a.site_dns_zone)))
        and ("acme_delegate" not in ext or not edge)
        and ("mesh_peer" not in ext or (isinstance(ext["mesh_peer"], str) and PEER_RE.match(ext["mesh_peer"])))
        and ext.get("door") in DOOR_VALUES
        and isinstance(ext.get("owner"), str) and len(ext["owner"].strip()) > 0
        and ("client" not in ext or (isinstance(ext["client"], dict) and "id" in ext["client"] and "secret_env" in ext["client"]))
        and ("retire_after" not in ext or DATE_RE.match(str(ext["retire_after"])))
    )
    if not ok:
        raise Refuse("%s: `name` is one lowercase DNS label; every entry of `hostnames` (default "
                     "[name]) is this service's own -- `<name>`, `<name>-<surface>`, or nested one "
                     "level as `<surface>.<name>` (so `api.northwind` and `northwind-api`, never `api`, "
                     "`demo.console.northwind` or another service's name) -- with no label over 63 "
                     "characters; "
                     "`tls` is edge or partner; in edge mode `backend_url` is "
                     "http(s)://<MESH IP>:<port> (a 100.64/10 address — the mesh is the outer gate, "
                     "never a LAN or public address); in partner mode `mesh_ip` is your host's "
                     "100.64/10 address, you terminate TLS yourself, and `acme_delegate` is a hostname "
                     "in a zone YOU control, outside the goatnet's zone (edge mode names none); "
                     "`mesh_peer`, when set, is your NetBird peer name; `door` is one of %s; `owner` is set; a "
                     "`client:` block needs `id` and `secret_env`; `retire_after` is YYYY-MM-DD."
                     % (var, DOOR_VALUES))
    problem = status_problem(ext, hosts)
    if problem:
        raise Refuse("%s: %s. The status-page controls are `status.list` (true/false, the default "
                     "for every hostname), `status.lifecycle` (%s) and `status.hostnames.<entry>` "
                     "with any of %s — docs/the-declaration.md, \"On the status page\"."
                     % (var, problem, " / ".join(LIFECYCLES), sorted(PER_HOST_KEYS)))
    for h in hosts:
        fq = "%s.%s.%s" % (h, a.site_id, a.site_dns_zone)
        if len(fq) > MAX_FQDN:
            raise Refuse("%s: hostname `%s` builds a name of %d characters under %s.%s; "
                         "a DNS name is at most %d. Nest less deeply, or shorten a label."
                         % (var, h, len(fq), a.site_id, a.site_dns_zone, MAX_FQDN))
    # A temporary service's guard tokens must not occur inside its own hostnames.
    # The goatnet's generated mesh zone lists every hostname, and the footprint
    # check scans it like any other file, so such a token fails that check on the
    # very pull request that adds the service. Existing temporary services avoid
    # it the same way: they guard on external-service-<name>, not on <name>.
    if "retire_after" in ext:
        stem = var[len("external_service_"):]
        tokens = ext.get("guard_tokens") or [stem.replace("_", "-"), stem, var]
        for t in [str(t) for t in tokens if str(t).strip()]:
            clash = [h for h in hosts if t in "%s.%s.%s" % (h, a.site_id, a.site_dns_zone)]
            if clash:
                raise Refuse("%s: guard token `%s` occurs in hostname `%s`. The goatnet's generated "
                             "mesh zone lists every hostname, so its footprint check would fail on the "
                             "pull request that adds this service. Set guard_tokens to names that appear "
                             "nowhere else, e.g. [external-service-%s, %s]."
                             % (var, t, clash[0], stem.replace("_", "-"), var))
    if "retire_after" in ext and str(ext["retire_after"]) < a.today:
        raise Refuse("%s declares retire_after %s, which has passed. Set enabled: false and ask for "
                     "it to be withdrawn, or move the date by agreement with the owner." % (var, ext["retire_after"]))


def in_zone(host, zone):
    h = host.lower().rstrip(".")
    return h == zone or h.endswith("." + zone)


def challenge_labels(hosts):
    """One public validation record per first label under the site: `<name>` (also *.<name>) and each flat name."""
    return sorted({h.split(".")[-1] for h in hosts})


def cert_names(hosts):
    out = []
    for h in hosts:
        n = ("*." + h.split(".", 1)[1]) if "." in h else h
        if n not in out:
            out.append(n)
    return out


def check_absent(var, ext):
    if ext and bool(ext.get("enabled", True)):
        raise Refuse("%s is still enabled. Withdrawing a live service is the owner's edit, not the platform "
                     "team's flag: set `enabled: false` in the declaration (or delete the file), then ask "
                     "for it to be withdrawn." % var)


def derive(var, ext, a):
    stem = var[len("external_service_"):]
    mode = tls_mode(ext)
    hosts = hostnames_of(ext)
    fqdns = ["%s.%s.%s" % (h, a.site_id, a.site_dns_zone) for h in hosts]
    fqdn = fqdns[0]
    tname = ext.get("traefik_name") or ("ext-" + str(ext.get("name")))
    client = ext.get("client") if isinstance(ext.get("client"), dict) else None
    st = ext.get("status") if isinstance(ext.get("status"), dict) else {}
    out = []
    out.append("what the goatnet prints back, for you to configure the service from:")
    out.append("  hostname:     %s" % ", ".join("https://" + f for f in fqdns))
    out.append("  issuer:       https://oauth2.%s.%s/   (trailing slash is load-bearing)" % (a.site_id, a.site_dns_zone))
    out.append("  jwks:         https://oauth2.%s.%s/.well-known/jwks.json" % (a.site_id, a.site_dns_zone))
    out.append("  issuer pin:   oauth2.%s.%s -> %s   (hosts on the mesh without mesh DNS)" % (a.site_id, a.site_dns_zone, a.mesh_ip_a))
    if client:
        out.append("  client_id:    %s" % client["id"])
        out.append("  redirect_uri: https://%s%s" % (fqdn, client.get("redirect_path", "/oauth2/callback")))
        out.append("  secret:       $%s  (same variable on both sides)" % client["secret_env"])
    else:
        out.append("  client:       none — the goatnet manages no OAuth2 client for this service.")
        out.append("                The service verifies the goatnet's tokens itself against the")
        out.append("                issuer and JWKS above; nothing to register, nothing to roll.")
    out.append("  door:         %s   (what the service's own fence decides; recorded, not enforced here)" % ext.get("door", "?"))
    if client:
        scopes = client.get("scopes") or ["openid", "profile", "email", "groups"]
        grants = ["authorization_code"] + (["refresh_token"] if "offline_access" in scopes else [])
        out.append("the OAuth2 client the goatnet registers for you (secret read from $%s):" % client["secret_env"])
        out.append("  client_id=%s client_name='%s (%s)' grant_types=%s response_types=[code]" % (client["id"], client["id"], a.site_id, grants))
        out.append("  scope='%s' redirect_uris=[https://%s%s]" % (" ".join(scopes), fqdn, client.get("redirect_path", "/oauth2/callback")))
        out.append("  token_endpoint_auth_method=client_secret_post skip_consent=true access_token_strategy=jwt audience=[%s]" % client["id"])
        if "token_lifespan" in client:
            out.append("  lifespans: id_token=%s access_token=%s  (pinned; your fence holds no refresh token)" % (client["token_lifespan"], client["token_lifespan"]))
    if mode == "edge":
        out.append("the goatnet's edge (one route carries every name):")
        nests = any("." in h for h in hosts)
        out.append("  certificate:  *.%s.%s  (covers every flat name; nothing added for them)" % (a.site_id, a.site_dns_zone))
        if nests:
            out.append("                *.%s.%s.%s  (added once, because this service nests)" % (ext.get("name"), a.site_id, a.site_dns_zone))
        out.append("  route   %s: priority 50, matches Host(%s), mesh-only, certificate issued by the goatnet"
                   % (tname, ", ".join("`%s`" % f for f in fqdns)))
        out.append("  backend %s: %s" % (tname, ext.get("backend_url")))
        out.append("the mesh DNS records (edge mode — every name resolves to the goatnet's edge):")
        for f in fqdns:
            out.append("  %s %s" % (a.mesh_ip_a, f))
    else:
        out.append("the goatnet's edge (tls: partner) — it publishes NOTHING here:")
        out.append("  no route, no backend, no certificate name. You terminate TLS on your own host")
        out.append("  with your own certificate, so the goatnet never issues one for these names.")
        out.append("  Its mesh-only allowlist is NOT your gate either: reachability control is yours.")
        out.append("the mesh DNS records (partner mode — every name resolves to YOUR host):")
        for f in fqdns:
            out.append("  %s %s" % (ext.get("mesh_ip", "?"), f))
        target = str(ext.get("acme_delegate", "?")).lower().rstrip(".")
        out.append("the PUBLIC DNS records (partner mode — certificate validation only, no address):")
        for l in challenge_labels(hosts):
            out.append("  _acme-challenge.%s.%s.%s  CNAME  %s" % (l, a.site_id, a.site_dns_zone, target))
        out.append("your certificate, from Let's Encrypt with the DNS-01 challenge (TXT records written at %s):" % target)
        out.append("  %s" % ", ".join("%s.%s.%s" % (n, a.site_id, a.site_dns_zone) for n in cert_names(hosts)))
        out.append("  lego follows the CNAME by default; acme.sh: --domain-alias %s" % target)
        if ext.get("mesh_peer"):
            out.append("  the goatnet publishes nothing unless the peer at %s is named %s" % (ext.get("mesh_ip", "?"), ext["mesh_peer"]))
    rows = []
    unlisted = []
    per = st.get("hostnames") or {}
    # Past the first, each row is suffixed by its own label so the page stays
    # readable. A nested label drops the service name it hangs under, because
    # "northwind-api-northwind" says the same thing twice; dots leave the id, which
    # anchors and selectors have to survive. A hostname with `list: false`
    # (its own, or the declaration's `status.list`) gets no row and no probe.
    name = str(ext.get("name"))
    for idx, (h, f) in enumerate(zip(hosts, fqdns)):
        o = per.get(h) or {}
        if not o.get("list", st.get("list", True)):
            unlisted.append(f)
            continue
        leaf = h[: -(len(name) + 1)] if idx and h.endswith("." + name) else h
        rid = str(st.get("id", name)) if idx == 0 else "%s-%s" % (st.get("id", name), leaf.replace(".", "-"))
        rnm = str(st.get("name", name)) if idx == 0 else "%s (%s)" % (st.get("name", name), leaf)
        life = o.get("lifecycle", st.get("lifecycle", "live"))
        rows.append(("|".join([
            rid, str(o.get("name", rnm)), f, "external", "", "",
            str(o.get("health_path", ext.get("health_path", "/"))), str(o.get("kind", st.get("kind", "ui"))),
            str(st.get("access", "public")), str(st.get("category", "app")), str(st.get("icon", "")),
            str(o.get("desc", st.get("desc", ""))), str(o.get("link_path", st.get("link_path", ""))),
            str(st.get("probe_front_door", True)).lower(), str(o.get("expect_codes", st.get("expect_codes", "2|3"))),
        ]), life))
    _unused = "|".join([
        str(st.get("id", ext.get("name"))), str(st.get("name", ext.get("name"))), fqdn, "external", "", "",
        str(ext.get("health_path", "/")), str(st.get("kind", "ui")), str(st.get("access", "public")),
        str(st.get("category", "app")), str(st.get("icon", "")), str(st.get("desc", "")), str(st.get("link_path", "")),
        str(st.get("probe_front_door", True)).lower(), str(st.get("expect_codes", "2|3")),
    ])
    out.append("the status-page rows, on the goatnet's External services page under \"%s\"" % ext.get("owner", "?"))
    out.append("  (one per listed hostname; a row the goatnet already publishes for a name wins):")
    for r, life in rows:
        out.append('  "%s"%s' % (r, "" if life == "live" else "   [%s: shown, not counted, not alerted on]" % life))
    for f in unlisted:
        out.append("  (not listed: %s — its DNS record and certificate name are unaffected)" % f)
    tokens = ext.get("guard_tokens") or [stem.replace("_", "-"), stem, var]
    kind = "TEMPORARY (retire_after %s): the footprint check FAILS on any of these outside the declaration" % ext["retire_after"] \
        if "retire_after" in ext else "permanent: the footprint check reports, never fails"
    out.append("the footprint check — %s:" % kind)
    out.append("  tokens: %s" % tokens)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("declaration")
    ap.add_argument("--state", choices=["present", "absent"], default="present")
    ap.add_argument("--site-id", default="zagros")
    ap.add_argument("--site-dns-zone", default="<zone>", help="the goatnet's DNS zone; placeholder by default")
    ap.add_argument("--mesh-ip-a", default="<edge mesh ip>", help="the goatnet edge's mesh IP; placeholder by default")
    ap.add_argument("--today", default=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"))
    ap.add_argument("--quiet", action="store_true", help="verdict only, no preview")
    a = ap.parse_args()
    try:
        var, ext = load(a.declaration)
        stem = var[len("external_service_"):].replace("_", "-")
        print("declaration: %s" % a.declaration)
        print("mapping:     %s   (file name: external-service-%s.yml — the two must agree)" % (var, stem))
        if a.state == "present":
            check_present(var, ext, a)
            print("verdict:     ACCEPTED for state=present (well-formed, enabled%s)"
                  % (", retire_after %s not passed" % ext["retire_after"] if "retire_after" in ext else ""))
        else:
            check_absent(var, ext)
            print("verdict:     ACCEPTED for state=absent (withdrawn in the declaration)")
            print("the goatnet would then: delete OAuth2 client %s; drop the edge route %s and its "
                  "certificate name; drop the mesh DNS record; drop the status-page row"
                  % ((ext.get("client") or {}).get("id", "(none)"), ext.get("traefik_name") or ("ext-" + str(ext.get("name")))))
    except Refuse as r:
        print("verdict:     REFUSED for state=%s" % a.state)
        print("reason:      %s" % r)
        return 1
    except (OSError, yaml.YAMLError) as e:
        print("verdict:     REFUSED — cannot read %s: %s" % (a.declaration, e))
        return 1
    if not a.quiet and a.state == "present":
        print()
        print("PREVIEW of what the goatnet derives (it does the real rendering; site=%s, zone=%s):" % (a.site_id, a.site_dns_zone))
        for line in derive(var, ext, a):
            print("  " + line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
