# Cloudflare Tunnel + Access migration runbook — `chezgilles.ovh`

Goal: put **hermes** and **openclaw** dashboards behind **Cloudflare Tunnel + Access**
(no public port, SSO + MFA, any-device browser access) while keeping every other
service working exactly as today. Free Cloudflare plan throughout.

**Time:** ~30–45 min hands-on, plus a wait for nameserver propagation (mins–hours).
You can stop after Phase 3 and finish later — the site keeps working the whole time.

> ⚠️ **The one thing that can hurt you: mail.** You self-host mail on this VPS
> (`MX → chezgilles.ovh`, ports 25/587/993 listening, DKIM selector `mail`).
> A few records **must stay "DNS only" (grey cloud)** or mail dies. They're
> flagged 🔴 below. Nothing else is risky.

---

## ✅ Completed — final state (2026-06-16)

The migration is **done and live**. Final state, beyond the original goal:

- **Nameservers** moved OVH → Cloudflare (`lamar`/`sofia.ns.cloudflare.com`). Mail
  records kept DNS-only; Cloudflare Email Routing was disabled (it had hijacked MX).
- **Wildcard cert** (`*.chezgilles.ovh`) renews via Cloudflare **DNS-01**
  (`caddy-dns/cloudflare` plugin, token in `cloudflare.env`).
- **hermes** + **openclaw** behind **Cloudflare Tunnel `hermes-vps`** + Access.
  Both services rebound to loopback; Caddy basic_auth + ufw rules removed.
- **Access auth = Google OAuth only.** The email OTP IdP was deleted. Policy:
  allow `gilles.closset@gmail.com`, require Google, `mfa_disabled: true`
  (Access apps: hermes, openclaw, finance share the reusable "main email policy").
- **finance.chezgilles.ovh** is now ALSO behind Access (whole domain). It is the
  only **proxied** (orange-cloud) host → its DNS record is `A 135.125.106.210`
  proxied, zone SSL/TLS mode **Full**. The finance app's own login was **removed**
  (relies on Access); see the finance repo + the origin-lock note in Phase 7.
- **Docker iptables-bypass hardening:** ports that Docker had published to
  `0.0.0.0` (bypassing UFW) were rebound to `127.0.0.1`: neo4j Bolt 7687,
  portainer 9000/9443, supabase kong 8000/8443, supabase pooler 5432/6543.
- **coolify.chezgilles.ovh** `A 217.182.66.124` (DNS-only) points at the *other*
  VPS; `boardgamebeats.ovh` was released. Coolify keeps its own Traefik cert +
  login (not behind Access).

Useful IDs (Cloudflare): account `914ab3d9b12de910ebddc3f40451d992`, team
`square-cherry-4288.cloudflareaccess.com`, tunnel `hermes-vps`
`d4dfd161-443e-446c-97d4-c84d6e064316`, reusable policy
`a702ae14-aded-482f-8c05-3507ba765a39`, Google IdP
`c90106bb-e955-46a7-8441-232fa37bddfd`.

---

## Current state (inventory taken 2026-06-12)

- **Registrar/DNS today:** OVH — nameservers `dns10.ovh.net` / `ns10.ovh.net`
- **VPS public IP:** `135.125.106.210`
- **Mail:** self-hosted on the VPS. `MX 10 chezgilles.ovh`. DKIM selector = `mail`.

### Records that MUST exist in Cloudflare after import (verify each one)

| Type | Name | Value | Cloud |
|------|------|-------|-------|
| A | `chezgilles.ovh` (root) | `135.125.106.210` | 🔴 **DNS only** (MX target + mail) |
| A | `www` | `135.125.106.210` | grey ok |
| A | `mail` | `135.125.106.210` | 🔴 **DNS only** |
| A | `smtp` | `135.125.106.210` | 🔴 **DNS only** |
| A | `imap` | `135.125.106.210` | 🔴 **DNS only** |
| A | `webmail` | `135.125.106.210` | DNS only (or orange if you want CF in front) |
| A | `autodiscover` / `autoconfig` | `135.125.106.210` | 🔴 **DNS only** |
| MX | `chezgilles.ovh` | `10 chezgilles.ovh.` | n/a |
| TXT | `chezgilles.ovh` (SPF) | `v=spf1 ip4:135.125.106.210 include:mx.ovh.com -all` | n/a |
| TXT | `mail._domainkey` (DKIM) | `v=DKIM1; k=rsa; p=MIIBIjAN…` (full key) | n/a |
| TXT | `_dmarc` | `v=DMARC1; p=none; adkim=s; aspf=s; rua=mailto:postmaster@chezgilles.ovh; fo=1; pct=100` | n/a |
| A | `flowise` `langfuse` `n8n` `neo4j` `ollama` `searxng` `supabase` `webui` `portainer` `opencode` `finance` | `135.125.106.210` | grey (DNS only) for now |
| A/CNAME | `hermes` `openclaw` | *(will become tunnel CNAMEs in Phase 5 — leave/delete)* | orange later |

> The OVH junk TXT `"1|www.chezgilles.ovh"` is an OVH-platform redirect marker —
> safe to **not** recreate. The `include:mx.ovh.com` in SPF stays (OVH relay).
> The DKIM value shown by `dig` is truncated; trust Cloudflare's import or copy the
> full record from your mail server, then verify with `dig` after cutover.

---

## Phase 0 — Pre-flight (do now, zero risk)

- [ ] **Lower TTLs at OVH** on the records you'll touch (set to 5 min / 300s) so a
      rollback propagates fast. Optional but nice.
- [ ] Save this file + note the rollback plan (bottom of doc).
- [ ] Confirm you can log into both **OVH** (registrar) and create a **Cloudflare** account.

## Phase 1 — Add the zone to Cloudflare (no cutover yet, site unaffected)

- [ ] Create a free account at dash.cloudflare.com.
- [ ] **Add a site** → `chezgilles.ovh` → choose the **Free** plan.
- [ ] Cloudflare auto-scans OVH and imports existing records. Wait for it to finish.
- [ ] **Verify every row in the table above exists.** Add any it missed (especially
      `mail._domainkey` DKIM, SPF, DMARC, MX).
- [ ] Set the 🔴 records to **DNS only (grey cloud)**. Easiest safe default:
      **grey-cloud EVERYTHING for now.** We only turn on the orange cloud for
      `hermes`/`openclaw` later, via the tunnel.
- [ ] Cloudflare shows two nameservers to use (e.g. `xxx.ns.cloudflare.com`). **Note them.**
- [ ] ❗ **Do NOT change nameservers yet.** Nothing is live on Cloudflare until you do.
lamar.ns.cloudflare.com
sofia.ns.cloudflare.com
Delete your other nameservers:
dns10.ovh.net
ns10.ovh.net

## Phase 2 — Cert change ✅ DONE — wildcard kept via Cloudflare DNS-01

The `caddy-ovh` image has been rebuilt with the `caddy-dns/cloudflare` plugin.
The Caddyfile TLS block now reads `dns cloudflare {env.CLOUDFLARE_API_TOKEN}` and
`cloudflare.env` holds the scoped API token (Zone / DNS / Edit, chezgilles.ovh only).

The existing wildcard cert (`*.chezgilles.ovh`, issued 2026-04-25) is served from
`caddy-data` and is **valid until 2026-07-24**. Caddy will auto-renew ~30 days before
expiry = **around 2026-06-24**. That renewal uses the Cloudflare DNS-01 path, which
only works once the zone is served by Cloudflare nameservers.

⚠️ **Complete Phase 3 (NS cutover) before 2026-06-24** or the renewal will fail.
If you miss the window, force re-obtain after the NS cutover with:
```
docker exec caddy caddy certificates delete --all
docker restart caddy
```

## Phase 3 — Nameserver cutover at OVH  ⏱️ the real "go" moment

- [ ] In OVH: **Domain names → chezgilles.ovh → DNS servers** → replace the OVH
      nameservers with the **two Cloudflare nameservers** from Phase 1.
- [ ] Wait until Cloudflare shows the zone **Active** (email from CF; usually minutes,
      up to a few hours). Check: `dig +short NS chezgilles.ovh` → Cloudflare names.
- [ ] **🔴 MAIL SMOKE TEST (do this before anything else):**
  - `dig +short MX chezgilles.ovh` → `10 chezgilles.ovh.`
  - `dig +short TXT chezgilles.ovh` → SPF unchanged
  - `dig +short TXT mail._domainkey.chezgilles.ovh` → DKIM key present
  - `dig +short TXT _dmarc.chezgilles.ovh` → DMARC present
  - **Send yourself an email** to your `@chezgilles.ovh` address and **send one out**
    from it. Confirm both work. If mail breaks → see Rollback.

## Phase 4 — Verify cert after NS cutover ✅ DONE (pre-wired)

No Caddyfile changes needed — the wildcard TLS block was already updated to
`dns cloudflare {env.CLOUDFLARE_API_TOKEN}` in Phase 2. After the NS cutover in
Phase 3, Caddy will automatically renew via Cloudflare DNS-01 on the next cycle.

- [ ] After NS cutover propagates, wait ~30 s then: `docker logs caddy 2>&1 | grep -i "cert\|acme\|obtain\|error"` — confirm no errors.
- [ ] Visit each service (`n8n.`, `supabase.`, `flowise.`, `finance.`, …) and confirm the padlock is valid.
- [ ] *(If the cert is already near expiry or just expired, force renewal:)*
      ```
      docker exec caddy caddy certificates delete --all
      docker restart caddy
      ```

## Phase 5 — Install cloudflared + create the tunnel (on the VPS)

- [ ] Install cloudflared (host package, **not** docker, so it can reach `127.0.0.1`):
      `https://pkg.cloudflare.com` → add repo → `sudo apt install cloudflared`.
- [ ] `cloudflared tunnel login`  → opens a browser link; authorize `chezgilles.ovh`.
- [ ] `cloudflared tunnel create hermes-vps`  → note the **tunnel UUID** + creds file
      path (`~/.cloudflared/<UUID>.json`).
- [ ] Create `~/.cloudflared/config.yml`:
      ```yaml
      tunnel: <UUID>
      credentials-file: /home/gilles/.cloudflared/<UUID>.json
      ingress:
        - hostname: hermes.chezgilles.ovh
          service: http://127.0.0.1:9119
          originRequest:
            httpHostHeader: localhost   # ⚠️ required: hermes' host-check rejects other Host values
        - hostname: openclaw.chezgilles.ovh
          service: http://127.0.0.1:18789
        - service: http_status:404
      ```
- [ ] Create the DNS routes (makes the orange CNAMEs in Cloudflare automatically):
      ```
      cloudflared tunnel route dns hermes-vps hermes.chezgilles.ovh
      cloudflared tunnel route dns hermes-vps openclaw.chezgilles.ovh
      ```
      (If old `hermes`/`openclaw` A records exist in CF, delete them first.)
- [ ] Run it as a service: `sudo cloudflared service install` then
      `sudo systemctl enable --now cloudflared`.

## Phase 6 — Cloudflare Access policies (the actual security) ✅ DONE

As implemented:
- **Zero Trust** team `square-cherry-4288.cloudflareaccess.com`.
- **Authentication = Google OAuth only.** The One-Time-PIN IdP was deleted, so the
  email-code path no longer appears. (Beware: a policy with `mfa_disabled: false`
  but no second factor configured fails with "No authentication methods set up" —
  the policies use `mfa_disabled: true`.)
- **Access applications** (self-hosted): `hermes.chezgilles.ovh`,
  `openclaw.chezgilles.ovh`, `finance.chezgilles.ovh` — all share one reusable
  policy: **Allow**, Include → email `gilles.closset@gmail.com`, Require → Google
  login method, `mfa_disabled: true`.
- **Test:** open each URL in a browser → Access (Google) → service. A private
  window / phone shows the Access gate; an already-signed-in Google session
  passes through silently.

## Phase 7 — Lock down the now-private services ✅ DONE

Traffic for hermes/openclaw arrives only via the tunnel (localhost), so the
surface was shrunk:

- [x] **hermes:** `/etc/systemd/system/hermes-dashboard.service` now binds
      `--host 127.0.0.1 --port 9119 --no-open --skip-build` (dropped `0.0.0.0` and
      `--insecure`; the tunnel sets `httpHostHeader: localhost` to satisfy hermes'
      Host-check).
- [x] **openclaw:** ExecStart now includes `--bind loopback` (127.0.0.1:18789).
- [x] **ufw rules** for 9119/18789 removed; **hermes + openclaw Caddy blocks**
      removed (Access + tunnel replace Caddy basic_auth).

### Docker iptables-bypass hardening (added after the original plan)

Docker publishes ports by writing its own iptables rules that **bypass UFW**, so
anything mapped to `0.0.0.0` is internet-reachable by direct IP regardless of UFW.
Rebound to `127.0.0.1` in the compose files (external access goes via Caddy):
neo4j Bolt `7687`, portainer `9000/9443`, supabase kong `8000/8443`, supabase
pooler `5432/6543`. Recreate (not just restart) so the new binding takes:
`docker compose up -d portainer neo4j kong supavisor`.

### finance origin lock + app login removal (added after the original plan)

`finance.chezgilles.ovh` is the only **proxied** host, so port 443 stays
internet-facing for the DNS-only services — meaning the origin is reachable by
direct IP + Host header, which would **bypass Access**. Two-part fix:

- [x] **Caddy origin lock:** the `finance.chezgilles.ovh` vhost rejects any
      request whose `remote_ip` is not a Cloudflare edge range (→ `403`). Ranges
      from `cloudflare.com/ips-v4` + `/ips-v6`; refresh if Cloudflare changes them.
- [x] **Removed the finance app's own login** (it only hid the UI; the `/api/*`
      data routes had no backend auth anyway). Access is now the sole gate;
      assistant identity is scoped to the single username `user`
      (`FINANCE_USERNAME` env). See the `Finance_dashboard` repo.

Verify: `curl --resolve finance.chezgilles.ovh:443:135.125.106.210
https://finance.chezgilles.ovh/api/dashboard` → **403**; the same URL through
Cloudflare → **302** (Access).

## Phase 8 — Final verification ✅

- [x] All other services load over HTTPS with valid certs (Cloudflare DNS-01 wildcard).
- [ ] Mail send + receive still works (second test) — **re-run after any DNS change.**
- [x] hermes + openclaw + finance require Cloudflare Access login, any device, no client.

---

## Rollback (if anything breaks, especially mail)

The OVH zone is untouched during all of this, so rollback = point nameservers back:
1. **OVH → DNS servers →** restore `dns10.ovh.net` / `ns10.ovh.net`. Propagates in
   minutes if you lowered TTLs (Phase 0).
2. Revert the Caddyfile (re-add the `*.chezgilles.ovh { tls { dns ovh } }` block) →
   `docker restart caddy`.
3. `sudo systemctl disable --now cloudflared` if you want it fully gone.
Everything returns to today's working state.

## Notes / gotchas baked in from our setup
- Editing the Caddyfile requires `docker restart caddy` (not `reload`) — bind-mount inode.
- hermes' Host-header check rejects non-loopback Host values unless `--insecure`;
  that's why the tunnel sets `httpHostHeader: localhost` once we drop `--insecure`.
- Keep mail-related records 🔴 DNS-only — Cloudflare can't proxy SMTP/IMAP.
- Free tier: Tunnel = unlimited; Access = up to 50 users. Verify current limits before relying.
