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

    system-manager = {
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

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
        ...
      }: {
        _module.args.pkgs = import inputs.nixpkgs-unstable {
          inherit system;
          overlays = [inputs.devshell.overlays.default];
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

                users.groups.dylan.gid = 5000;
                users.users.dylan = {
                  isNormalUser = true;
                  uid = 5000;
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

                  users.dylan = _: {
                    home.stateVersion = "26.05";
                    programs.fish.enable = true;
                    home.file.".ssh/authorized_keys".source = ./homelab.pub;
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
