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

# Trust numtide's cache at the system level so the bootstrap's first
# `nix run` can fetch system-manager-engine without building from source
# and without the trusted-user warning. system-manager activation later
# rewrites nix.conf, but this stanza is idempotent for re-runs.
nix_conf=/etc/nix/nix.conf
if ! grep -q 'cache.numtide.com' "$nix_conf" 2>/dev/null; then
  sudo tee -a "$nix_conf" >/dev/null <<'EOF'

extra-substituters = https://cache.numtide.com
extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=
EOF
  sudo systemctl restart nix-daemon
fi

# Hand off to the bundled activation script: switch system-manager, force
# home-manager to run, drop into dylan. Using our flake's `default` package
# avoids fetching numtide's flake (which has nixConfig that trips the
# trusted-user check).
exec nix run "github:dfrankland/fwdf"
