#!/usr/bin/env bats

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  FIXTURES="$SCRIPT_DIR/tests/fixtures"
  source "$SCRIPT_DIR/lib/tailscale-discover.sh"
}

@test "discover_desktop_hostname returns Self.HostName" {
  result="$(discover_desktop_hostname < "$FIXTURES/tailscale-status.json")"
  [ "$result" = "hammer-desktop" ]
}

@test "discover_desktop_ipv4 returns first IPv4 from TailscaleIPs" {
  result="$(discover_desktop_ipv4 < "$FIXTURES/tailscale-status.json")"
  [ "$result" = "100.64.10.42" ]
}

@test "discover_peer_ipv4 returns the matching peer IPv4" {
  result="$(discover_peer_ipv4 miguels-s24 < "$FIXTURES/tailscale-status.json")"
  [ "$result" = "100.83.211.53" ]
}

@test "discover_peer_ipv4 fails for unknown peer" {
  run bash -c 'source '"$SCRIPT_DIR"'/lib/tailscale-discover.sh; discover_peer_ipv4 ghost < '"$FIXTURES"'/tailscale-status.json'
  [ "$status" -ne 0 ]
}

@test "discover_peer_ipv4 matches DNSName short form when HostName contains spaces" {
  # Real-world case: a phone with HostName "Miguel's S24 v2" gets a sanitized
  # magic-DNS short label. Operators type the short form; the lookup must
  # match it against DNSName, not just HostName.
  result="$(discover_peer_ipv4 miguels-s24-v2 < "$FIXTURES/tailscale-status.json")"
  [ "$result" = "100.83.211.99" ]
}
