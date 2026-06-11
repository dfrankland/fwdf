#!/bin/bash

set -euo pipefail

# Initial bind-mount /local/nix onto /nix so nix installs into /local/nix.
# system-manager will set up the persistent systemd mount unit on activation.
sudo mkdir -p /local/nix /nix
mountpoint -q /nix || sudo mount --bind /local/nix /nix

# install nix (idempotent — the installer refuses to re-run when /nix/receipt.json exists)
if [ ! -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  curl -sSf -L https://install.lix.systems/lix | sh -s -- install --no-confirm
fi
# shellcheck source=/dev/null
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# Activate system-manager: creates dylan, sets up mounts, runs home-manager.
system=$(nix eval --raw --impure --expr "builtins.currentSystem")
nix run --accept-flake-config "github:numtide/system-manager" -- switch \
  --flake "github:dfrankland/fwdf#fwdf-$system" --sudo

# Drop into dylan's session.
exec sudo -u dylan -i
