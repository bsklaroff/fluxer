#!/usr/bin/env bash
# Runs the release in the yaac site's volume (current/, put there by build.sh)
# behind the site's proxy: plain HTTP on port 8080 (fluxerd's proxy edge
# mode), with every bit of state on the volume.
#
#   serve.sh            run fluxerd in the foreground (the serve step)
#   serve.sh health     exit 0 once every service is ready (its ready check)
#   serve.sh <cmd>...   any other fluxerd command against the same instance,
#                       e.g. `serve.sh ps` or `serve.sh logs api`
#
# Public address: FLUXER_DOMAIN (default localhost) and FLUXER_PUBLIC_ORIGIN
# (default https://$FLUXER_DOMAIN, or http://localhost:8080 for localhost).
# Set them, and any other FLUXER_* setting, in the project's environment, or
# put them in $YAAC_VOLUME_DIR/config/fluxer.env, which fluxerd reads first.
set -euo pipefail

die() { printf 'site serve: %s\n' "$*" >&2; exit 1; }

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
site_have_volume || die "$site_no_volume"
root="$vol/current"
[ -x "$root/bin/fluxerd" ] || die "no release in $root; run build.sh first"

config="$vol/config"
mkdir -p "$config/caddy.d" "$config/certs"
[ -f "$config/fluxer.env" ] || printf '# FLUXER_* settings for the yaac site, read by fluxerd before the process environment.\n' >"$config/fluxer.env"

export FLUXER_DATA_DIR="$vol/data"
export RUNTIME_DIRECTORY="${RUNTIME_DIRECTORY:-/tmp/fluxer-run}"
export FLUXER_EDGE_MODE="${FLUXER_EDGE_MODE:-proxy}"
# fluxerd binds its proxy edge to loopback by default; the site's proxy may
# reach the pod on its own address, so listen on every interface.
export FLUXER_EDGE_LISTEN_ADDRESS="${FLUXER_EDGE_LISTEN_ADDRESS:-0.0.0.0}"
# yaac's egress proxy answers every DNS lookup with 198.18.0.1, a range
# Fluxer refuses as special-use, so it could never reach an SSO provider.
export FLUXER_SSO_ALLOW_PRIVATE_ADDRESSES="${FLUXER_SSO_ALLOW_PRIVATE_ADDRESSES:-true}"
export FLUXER_DOMAIN="${FLUXER_DOMAIN:-localhost}"
if [ -z "${FLUXER_PUBLIC_ORIGIN:-}" ]; then
    if [ "$FLUXER_DOMAIN" = localhost ]; then
        export FLUXER_PUBLIC_ORIGIN=http://localhost:8080 FLUXER_PUBLIC_SCHEME=http FLUXER_PUBLIC_PORT=8080
    else
        export FLUXER_PUBLIC_ORIGIN="https://$FLUXER_DOMAIN"
    fi
fi
mkdir -p "$RUNTIME_DIRECTORY"

flags=(--config "$config/fluxer.env" --caddy-dir "$config/caddy.d" --certs-dir "$config/certs")
cmd="${1:-run}"
[ "$#" -eq 0 ] || shift
case "$cmd" in
run)
    echo "fluxer $(cat "$root/share/VERSION" 2>/dev/null) ($(cat "$root/share/COMMIT" 2>/dev/null)) at $FLUXER_PUBLIC_ORIGIN" >&2
    exec "$root/bin/fluxerd" run "${flags[@]}" "$@"
    ;;
health | ps | ctl | logs)
    exec "$root/bin/fluxerd" "$cmd" "$@"
    ;;
*)
    exec "$root/bin/fluxerd" "$cmd" "${flags[@]}" "$@"
    ;;
esac
