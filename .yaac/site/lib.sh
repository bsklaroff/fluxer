# Sourced by the site scripts: finds the site's volume as $vol.
# yaac sets YAAC_VOLUME_DIR in agent sessions but not in a site release's
# steps, which get the volume at ~/volume.
vol="${YAAC_VOLUME_DIR:-}"
if [ -z "$vol" ] && grep -q " $HOME/volume " /proc/mounts; then
    vol="$HOME/volume"
fi
site_have_volume() { [ -n "$vol" ] && [ -d "$vol" ]; }
site_no_volume="no volume mounted (YAAC_VOLUME_DIR is unset and ~/volume is not a mount): give the site one with --volume"
