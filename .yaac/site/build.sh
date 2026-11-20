#!/usr/bin/env bash
# Builds the commit this checkout is at into the yaac site's volume and
# swaps the result in as current/, for serve.sh to run. The fluxer-site
# workflow's build step. The site's release limit has to cover a cold build
# (about 45 minutes); later builds only redo what changed.
#
# Everything slow to rebuild lives on the volume ($YAAC_VOLUME_DIR):
#   src/      a persistent clone this checkout's commit is checked out into.
#             git checkout only rewrites files that changed, so target/,
#             node_modules/, _build/ and the nested wasm/NIF target dirs keep
#             their mtimes and cargo, rebar3 and pnpm rebuild incrementally.
#   cache/    pnpm store, Go module and build caches, rebar3 cache, the
#             third-party download cache and cargo's registry.
#   build/    build.sh's output dir; the release is moved to current/.
#   current/  the unpacked release serve.sh runs.
# The release workspace's own checkout is thrown away with it, so nothing is
# built there.
set -euo pipefail

log() { printf '==> [site build] %s\n' "$*" >&2; }
die() { printf 'site build: %s\n' "$*" >&2; exit 1; }

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
problems=()
site_have_volume || problems+=("$site_no_volume")
[ -n "${TOOLCHAIN:-}" ] && [ -d "$TOOLCHAIN/bin" ] && [ -n "${NATIVE:-}" ] \
    || problems+=("no toolchain (TOOLCHAIN=${TOOLCHAIN:-unset}, NATIVE=${NATIVE:-unset}): the project image should be built from Dockerfile.yaac")
if [ "${#problems[@]}" -gt 0 ]; then
    printf 'site build: %s\n' "${problems[@]}" >&2
    exit 1
fi
log "$(nproc) CPUs, $(free -g | awk '/^Mem:/{print $2}')G memory, volume: $(df -h "$vol" | awk 'NR==2{print $2" ("$4" free)"}')"

repo="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
src="$vol/src"
cache="$vol/cache"
out="$vol/build"
sha="$(git -C "$repo" rev-parse HEAD)"

# 1. Check the commit out into the persistent clone.
log "syncing $sha into $src"
[ -d "$src/.git" ] || git init -q "$src"
# Each release mounts the volume in a new pod, so inode, device and ctime
# never match the index. A forced checkout rewrites every such file, which
# gives the whole tree new mtimes and rebuilds everything. Compare only
# mtime and size, and refresh the index (by content where those differ)
# so the checkout rewrites just the files that really changed.
git -C "$src" config core.checkStat minimal
git -C "$src" config core.trustctime false
git -C "$src" update-index -q --refresh >/dev/null 2>&1 || true
git -C "$src" fetch -q --no-tags "$repo" HEAD
git -C "$src" -c advice.detachedHead=false checkout -q --force --detach FETCH_HEAD
# Drop untracked files a previous commit's tree left behind, but keep ignored
# ones: those are the build caches.
git -C "$src" clean -q -fd
[ "$(git -C "$src" rev-parse HEAD)" = "$sha" ] || die "$src is not at $sha after checkout"

# 2. Point every cache that would otherwise live in $HOME at the volume.
mkdir -p "$cache"
export XDG_CACHE_HOME="$cache/xdg"
export FLUXER_DIST_CACHE="$cache/dist-downloads"
export PNPM_STORE_DIR="$cache/pnpm-store"
export GOMODCACHE="$cache/go-mod"
export GOCACHE="$cache/go-build"
export REBAR_CACHE_DIR="$cache/rebar3"
# build.sh pins CARGO_HOME to $TOOLCHAIN/cargo, which is in the image; keep
# the crate registry and git checkouts on the volume instead.
for d in registry git; do
    link="$TOOLCHAIN/cargo/$d"
    [ -L "$link" ] && [ "$(readlink "$link")" = "$cache/cargo/$d" ] && continue
    mkdir -p "$cache/cargo/$d"
    if [ -d "$link" ] && [ ! -L "$link" ]; then
        cp -a --no-clobber "$link/." "$cache/cargo/$d/" 2>/dev/null || true
        rm -rf "$link"
    fi
    ln -sfn "$cache/cargo/$d" "$link"
done

cd "$src"

# 3. The image is a warm cache of the toolchain and native deps; both scripts
# are no-ops when the pins match and rebuild only what moved otherwise.
log "checking the toolchain and native deps"
make toolchain native-deps

# 4. Build the release. Packing (at a fast zstd level) is kept because it
# also verifies the layout and writes share/VERSION.
rm -f "$out"/fluxer-*.tar.zst "$out"/SHA256SUMS
export ZSTD_LEVEL="${ZSTD_LEVEL:-1}"
start=$SECONDS
log "building"
tools/dist/build.sh "$out"
rm -f "$out"/fluxer-*.tar.zst "$out"/SHA256SUMS
log "built in $((SECONDS - start))s"

built=("$out"/fluxer-linux-*)
[ "${#built[@]}" -eq 1 ] && [ -x "${built[0]}/bin/fluxerd" ] || die "expected one release under $out"
printf '%s\n' "$sha" >"${built[0]}/share/COMMIT"

# Swap it in as current/. Nothing runs from current/ during a build: the
# previous release stopped before this one started.
rm -rf "$vol/current.old" "$vol/placeholder"
[ ! -e "$vol/current" ] || mv "$vol/current" "$vol/current.old"
mv "${built[0]}" "$vol/current"
rm -rf "$vol/current.old"
log "release $(cat "$vol/current/share/VERSION") ($sha) is ready in $vol/current"
