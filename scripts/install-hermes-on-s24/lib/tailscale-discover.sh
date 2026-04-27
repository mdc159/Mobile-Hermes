#!/usr/bin/env bash
# tailscale-discover.sh — pure functions over `tailscale status --json` output.

discover_desktop_hostname() {
  jq -r '.Self.HostName // empty'
}

discover_desktop_ipv4() {
  jq -r '.Self.TailscaleIPs[]? | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"))' | head -n1
}

discover_peer_ipv4() {
  local peer_name="$1"
  local result
  # Match against HostName OR the leading label of DNSName (the magic-DNS
  # short form). Tailscale derives the short form by lowercasing+slugifying
  # HostName, so a phone named "Miguel's S24" has DNSName starting with
  # "miguels-s24" — that's what we want users to type.
  result=$(jq -r --arg name "$peer_name" '
    .Peer // {} | to_entries[]
    | select(.value.HostName == $name
             or (.value.DNSName // "" | split(".")[0]) == $name)
    | .value.TailscaleIPs[]?
    | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"))' | head -n1)
  if [ -z "$result" ]; then
    echo "no IPv4 found for peer $peer_name" >&2
    return 1
  fi
  printf '%s' "$result"
}

# Convenience: cache desktop hostname to disk so repeated runs don't re-query.
cache_desktop_hostname() {
  local cache_file="$1"
  if [ -f "$cache_file" ] && [ -s "$cache_file" ]; then
    cat "$cache_file"
    return 0
  fi
  local name
  name=$(tailscale status --json | discover_desktop_hostname)
  if [ -z "$name" ]; then
    echo "could not discover desktop Tailscale hostname" >&2
    return 1
  fi
  printf '%s' "$name" > "$cache_file"
  printf '%s' "$name"
}
