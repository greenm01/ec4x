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
            # Nim development
            nim
            nimble
            # Database support
            sqlite
            # dev tools
            git
            git-filter-repo
            # Python for aider
            python311
            python311Packages.pip
            stdenv.cc.cc.lib
          ];
          shellHook = ''
            export IN_NIX_SHELL=1
            export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:$PWD/bin:$LD_LIBRARY_PATH"

            # Create aider venv with nix's Python 3.11
            if [ ! -d .aider-venv ]; then
              ${pkgs.python311}/bin/python3.11 -m venv .aider-venv
              .aider-venv/bin/pip install aider-chat
            fi

            # Load Gemini API key
            if [ -f ~/.config/aider/gemini_key ]; then
              export GEMINI_API_KEY=$(cat ~/.config/aider/gemini_key)
            fi

            # Add aider to PATH
            export PATH="$PWD/.aider-venv/bin:$PATH"

            # Fish shell compatibility
            if [ -n "$FISH_VERSION" ]; then
              for p in ${pkgs.lib.makeBinPath (with pkgs; [
                nim nimble sqlite git git-filter-repo python311
              ])}; do
                fish -c "set -gx PATH $p \$PATH" 2>/dev/null || true
              done
              fish -c "set -gx PATH $PWD/.aider-venv/bin \$PATH" 2>/dev/null || true
              fish -c "set -gx LD_LIBRARY_PATH ${pkgs.stdenv.cc.cc.lib}/lib:$PWD/bin:\$LD_LIBRARY_PATH" 2>/dev/null || true
              [ -n "$GEMINI_API_KEY" ] && fish -c "set -gx GEMINI_API_KEY $GEMINI_API_KEY" 2>/dev/null || true
            fi

            echo "EC4X Development Shell"
            echo "======================"
            echo "Nim version: $(nim --version | head -1)"
            echo "Nimble version: $(nimble --version)"
            echo ""
            echo "Build & Test:"
            echo "  nimble buildSimulation              - Build parallel simulation"
            echo "  ./bin/run_simulation -s 12345       - Run single game (seed 12345)"
            echo "  nimble testBalanceQuick             - Quick balance test (20 games)"
            echo ""
            echo "AI Assistant:"
            echo "  aider --model gemini/gemini-2.0-flash-exp"
            echo ""
            echo "─────────────────────────────────────────────"
          '';
        };
      });
}
