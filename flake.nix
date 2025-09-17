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
        runtimeInputs = [
          pkgs.age
          pkgs.jq
          pkgs.moreutils
        ];
        text = ''
          json_file="$(git rev-parse --show-toplevel)/secrets.json"

          private_key=$(age-keygen)
          public_key=$(printf "%s" "$private_key" | age-keygen -y)

          jq --arg id "$1" --arg private "$private_key" --arg public "$public_key" \
          '.age[$id] = {private: $private, public: $public}' "$json_file" | sponge "$json_file"
        '';
      };

      packages.generate-ed25519 = pkgs.writeShellApplication {
        name = "generate-ed25519";
        runtimeInputs = [
          pkgs.openssh
          pkgs.jq
          pkgs.moreutils
        ];
        text = ''
          json_file="$(git rev-parse --show-toplevel)/secrets.json"

          tmpdir=$(mktemp -d)
          trap 'rm -rf "$tmpdir"' EXIT
          cd "$tmpdir" || exit

          ssh-keygen -t ed25519 -f ./temp_key -N "" -C "$1" -q

          jq --arg id "$1" --arg private "$(cat ./temp_key)" --arg public "$(cat ./temp_key.pub)" \
          '.ed25519[$id] = {private: $private, public: $public}' "$json_file" | sponge "$json_file"
        '';
      };

    in

    {
      packages.x86_64-linux = packages;
      checks.x86_64-linux = packages;
      formatter.x86_64-linux = treefmtEval.config.build.wrapper;
    };
}
