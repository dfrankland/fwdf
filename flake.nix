{
  description = "fwdf system-manager + home-manager configuration for dylan";

  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs-unstable";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # NB: do not override system-manager's nixpkgs input — keeping their pin
    # lets us hit the cache.numtide.com prebuilt of system-manager-engine.
    system-manager.url = "github:numtide/system-manager";

    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem = {
        system,
        pkgs,
        lib,
        ...
      }: {
        _module.args.pkgs = import inputs.nixpkgs-unstable {
          inherit system;
          overlays = [inputs.devshell.overlays.default];
        };

        packages = lib.optionalAttrs pkgs.stdenv.isLinux {
          default = pkgs.writeShellScriptBin "fwdf" ''
            set -euo pipefail
            system=$(${pkgs.nix}/bin/nix eval --raw --impure --expr 'builtins.currentSystem')
            ${pkgs.system-manager}/bin/system-manager switch \
              --flake "github:dfrankland/fwdf#fwdf-$system" --sudo

            # userborn won't rewrite an existing user's shell (the sandbox
            # provisions dylan with /bin/bash before we run), so force it.
            sudo usermod -s ${pkgs.fish}/bin/fish dylan

            sudo systemctl daemon-reload
            sudo systemctl restart home-manager-dylan.service

            # If we have a real tty, drop straight into dylan's session.
            # Otherwise (e.g. curl | bash, where stdin is a pipe), instruct
            # the user to do it themselves — an interactive shell with no
            # tty just exits.
            if [ -t 0 ]; then
              exec sudo su - dylan
            else
              echo
              echo "Setup complete. Run 'sudo su - dylan' to enter dylan's session."
            fi
          '';
        };

        formatter = pkgs.alejandra;

        checks.formatting = pkgs.runCommand "check-formatting" {nativeBuildInputs = [pkgs.alejandra];} ''
          alejandra --check ${./.}
          touch $out
        '';

        checks.shellcheck = pkgs.runCommand "check-shellcheck" {nativeBuildInputs = [pkgs.shellcheck];} ''
          shellcheck ${./setup.sh}
          touch $out
        '';

        checks.taplo = pkgs.runCommand "check-taplo" {nativeBuildInputs = [pkgs.taplo];} ''
          taplo fmt --check ${./devshell.toml}
          touch $out
        '';

        devShells.default = pkgs.devshell.fromTOML ./devshell.toml;
      };

      flake = let
        linuxSystems = [
          "x86_64-linux"
          "aarch64-linux"
        ];

        mkSystem = system:
          inputs.system-manager.lib.makeSystemConfig {
            modules = [
              inputs.home-manager.nixosModules.home-manager
              ({pkgs, ...}: {
                nixpkgs.hostPlatform = system;

                # Userborn creates the dylan user declaratively on activation.
                services.userborn.enable = true;

                # System-manager configures nix.conf and the daemon, using lix.
                nix.enable = true;
                nix.package = pkgs.lix;
                nix.settings = {
                  extra-substituters = ["https://cache.numtide.com"];
                  extra-trusted-public-keys = [
                    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
                  ];
                };

                users.groups.dylan = {};
                users.users.dylan = {
                  isNormalUser = true;
                  group = "dylan";
                  home = "/home/dylan";
                  createHome = true;
                  shell = "${pkgs.fish}/bin/fish";
                };

                systemd.tmpfiles.rules = [
                  "d /local/nix 0755 root root - -"
                  "d /local/dylan 0755 dylan dylan - -"
                  "d /local/dylan/.cache 0755 dylan dylan - -"
                  "d /local/dylan/.state 0755 dylan dylan - -"
                ];

                systemd.mounts = [
                  {
                    what = "/local/nix";
                    where = "/nix";
                    type = "none";
                    options = "bind";
                    wantedBy = ["local-fs.target"];
                  }
                  {
                    what = "/local/dylan/.cache";
                    where = "/home/dylan/.cache";
                    type = "none";
                    options = "bind";
                    wantedBy = ["local-fs.target"];
                  }
                  {
                    what = "/local/dylan/.state";
                    where = "/home/dylan/.state";
                    type = "none";
                    options = "bind";
                    wantedBy = ["local-fs.target"];
                  }
                ];

                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  backupFileExtension = "bak";

                  users.dylan = {lib, ...}: {
                    home.stateVersion = "26.05";
                    programs.fish.enable = true;

                    # sshd StrictModes rejects a symlinked authorized_keys whose
                    # target lives in /nix/store (group-writable), so copy the
                    # file out of the store on activation instead of letting
                    # home.file create a symlink.
                    home.activation.installAuthorizedKeys = lib.hm.dag.entryAfter ["writeBoundary"] ''
                      install -d -m 700 "$HOME/.ssh"
                      install -m 600 ${./homelab.pub} "$HOME/.ssh/authorized_keys"
                    '';
                  };
                };
              })
            ];
          };
      in {
        systemConfigs = builtins.listToAttrs (map (system: {
            name = "fwdf-${system}";
            value = mkSystem system;
          })
          linuxSystems);
      };
    };
}
