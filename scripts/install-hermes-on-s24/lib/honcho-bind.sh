#!/usr/bin/env bash
# honcho-bind.sh — prints the configuration changes the user must apply
# to expose Honcho on Tailscale safely. NEVER modifies any file or service.

print_recommendation() {
  local desktop_ts_ip="$1"
  local phone_host="$2"

  cat <<EOF
==========================================================================
Honcho exposure recommendation
==========================================================================

The phone "$phone_host" needs to reach Honcho on this desktop's Tailscale
interface (tailscale0, $desktop_ts_ip:18000). Honcho currently binds to 127.0.0.1.

PREFERRED — enable Honcho auth + Tailscale ACL:
  1. In honcho's config (.env or systemd unit), set:
       AUTH_USE_AUTH=true
       AUTH_JWT_SECRET=<rotate to a fresh long random string>
       HOST=$desktop_ts_ip       # bind to Tailscale interface only
  2. Mint a phone-only token via Honcho's keys API; copy the value into
     the desktop /home/hammer/Documents/repos/hermaper/.env as
     HONCHO_AUTH_TOKEN=...
  3. In your Tailscale ACL (https://login.tailscale.com/admin/acls),
     restrict access:
       {
         "acls": [
           {"action": "accept",
            "src": ["$phone_host"],
            "dst": ["$desktop_ts_ip:18000"]}
         ]
       }
  4. Restart Honcho.

ACCEPTABLE FALLBACK — keep AUTH_USE_AUTH=false (private lab posture).
  All four conditions MUST be true:
    - HOST=$desktop_ts_ip (NEVER 0.0.0.0).
    - Tailscale ACL allows only $phone_host -> $desktop_ts_ip:18000.
    - No external/shared tailnet users can reach this desktop node.
    - Postgres :5433 stays bound to localhost.

ALTERNATIVE — Tailscale Serve:
  Instead of rebinding Honcho, run:
    tailscale serve --bg --tcp 18000 tcp://localhost:18000
  This exposes the local Honcho into the tailnet without changing the
  app's bind address. ACLs still apply.

==========================================================================
The install script will not modify Honcho. Apply one of the options above
manually, then press ENTER to continue.
EOF
}
