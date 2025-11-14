{
  description = "EC4X Nim development shell";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nim
            nimble
          ];
          shellHook = ''
            echo "EC4X Nim development shell"
            echo "Nim version: $(nim --version | head -1)"
            echo "Nimble version: $(nimble --version)"
            echo ""
            echo "Available commands:"
            echo "  nimble install -d  - Install dependencies"
            echo "  nimble build       - Build all components"
            echo "  nimble test        - Run tests"
            echo "  nimble tasks       - Show all available tasks"
            echo ""
            echo "Quick start:"
            echo "  nimble build"
            echo "  ./bin/moderator new my_game"
            echo "  ./bin/client offline --players=4"
            echo ""

            # Launch fish if available (suppress greeting)
            if command -v fish >/dev/null 2>&1; then
              exec fish -C "function fish_greeting; end"
            fi
          '';
        };
      });
}
