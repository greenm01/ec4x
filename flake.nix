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
            git
            nushell  # Add nushell to available packages
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
            
            # Try nushell first, fallback to current shell, then bash
            if command -v nu >/dev/null 2>&1; then
              echo "Starting nushell..."
              exec nu
            elif [ -n "$SHELL" ] && [ -x "$SHELL" ]; then
              echo "Nushell not available, using current shell: $SHELL"
              exec "$SHELL"
            else
              echo "Using bash fallback"
              exec ${pkgs.bash}/bin/bash
            fi
          '';
        };
      });
}
