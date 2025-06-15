{

  nixConfig.allow-import-from-derivation = false;

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.sops-nix.url = "github:Mic92/sops-nix";

  outputs =
    { self, ... }@inputs:
    let
      lib = inputs.nixpkgs.lib;

      collectInputs =
        is:
        pkgs.linkFarm "inputs" (
          builtins.mapAttrs (
            name: i:
            pkgs.linkFarm name {
              self = i.outPath;
              deps = collectInputs (lib.attrByPath [ "inputs" ] { } i);
            }
          ) is
        );

      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

      libs.secrets = import ./secrets;

      treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
      };

      formatter = treefmtEval.config.build.wrapper;

      devShells.default = pkgs.mkShellNoCC {
        buildInputs = [ pkgs.nixd ];
      };

      scripts.generate-age = pkgs.writeShellApplication {
        name = "generate-age";
        runtimeInputs = [ pkgs.age ];
        text = ''
          if [ $# -ne 1 ]; then
            echo "Error: Please provide an identifier as argument"
            echo "Usage: $0 <identifier>"
            exit 1
          fi

          trap 'cd $(pwd)' EXIT
          repo_root=$(git rev-parse --show-toplevel)
          cd "$repo_root" || exit

          identifier="$1"

          private_key_file="./secrets/age-$identifier-private.txt"
          public_key_file="./secrets/age-$identifier-public.txt"

          age-keygen -o "$private_key_file"
          age-keygen -y "$private_key_file" > "$public_key_file"
        '';
      };

      scripts.generate-ed25519 = pkgs.writeShellApplication {
        name = "generate-ed25519";
        runtimeInputs = [ pkgs.openssh ];
        text = ''
          if [ $# -ne 1 ]; then
            echo "Error: Please provide an identifier as argument"
            echo "Usage: $0 <identifier>"
            exit 1
          fi

          trap 'cd $(pwd)' EXIT
          repo_root=$(git rev-parse --show-toplevel)
          cd "$repo_root" || exit

          identifier="$1"

          private_key_file="./secrets/ed25519-$identifier-private.txt"
          public_key_file="./secrets/ed25519-$identifier-public.txt"

          ssh-keygen -t ed25519 -f "$private_key_file" -N "" -C "$identifier" -q
          mv "$private_key_file.pub" "$public_key_file"
        '';
      };

      packages =
        scripts
        // devShells
        // {
          formatting = treefmtEval.config.build.check self;
          formatter = formatter;
          allInputs = collectInputs inputs;
        };

    in

    {

      packages.x86_64-linux = packages // rec {
        gcroot = pkgs.linkFarm "gcroot" packages;
        default = gcroot;
      };

      checks.x86_64-linux = packages;
      formatter.x86_64-linux = formatter;
      devShells.x86_64-linux = devShells;
      lib = libs;

    };
}
