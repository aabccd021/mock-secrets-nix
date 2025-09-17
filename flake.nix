{

  nixConfig.allow-import-from-derivation = false;

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

  outputs =
    { self, ... }@inputs:
    let

      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

      treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.prettier.enable = true;
      };

      packages.formatting = treefmtEval.config.build.check self;

      packages.generate-age = pkgs.writeShellApplication {
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

      packages.generate-ed25519 = pkgs.writeShellApplication {
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

      nixosModules.default =
        { lib, ... }:
        {
          options.mock-secrets = lib.mkOption {
            readOnly = true;
            default = {
              age.alice.public = builtins.readFile ./secrets/age-alice-public.txt;
              age.alice.private = builtins.readFile ./secrets/age-alice-private.txt;
              ed25519.alice.public = builtins.readFile ./secrets/ed25519-alice-public.txt;
              ed25519.alice.private = builtins.readFile ./secrets/ed25519-alice-private.txt;
              ed25519.bob.public = builtins.readFile ./secrets/ed25519-bob-public.txt;
              ed25519.bob.private = builtins.readFile ./secrets/ed25519-bob-private.txt;
            };
          };
        };

    in

    {
      packages.x86_64-linux = packages;
      checks.x86_64-linux = packages;
      formatter.x86_64-linux = treefmtEval.config.build.wrapper;
      nixosModules = nixosModules;
    };
}
