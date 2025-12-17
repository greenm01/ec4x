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
      let
        pythonEnv = pkgs.python311.withPackages (ps: with ps; [
          # AI development
          pip
          virtualenv
          google-generativeai

          # Data Analysis Stack (Terminal-focused)
          polars       # Fast DataFrame library
          pyarrow      # Parquet I/O backend
          rich         # Beautiful terminal output
          tabulate     # ASCII/Markdown tables
          numpy        # Statistical functions
          scipy        # Advanced statistics
          click        # CLI framework
        ]);
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Nim development
            nim
            nimble

            # Database support
            sqlite

            # Python with packages
            pythonEnv
            aider-chat

            # Data exploration
            visidata

            # dev tools
            git
            git-filter-repo
            sqlite

          ];
          shellHook = ''
            export IN_NIX_SHELL=1
            export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:$PWD/bin:$LD_LIBRARY_PATH"

            # Fish shell compatibility - explicitly add nix store paths to PATH
            if [ -n "$FISH_VERSION" ]; then
              for p in ${pkgs.lib.makeBinPath (with pkgs; [
                nim nimble sqlite pythonEnv aider-chat visidata git git-filter-repo
              ])}; do
                fish -c "set -gx PATH $p \$PATH" 2>/dev/null || true
              done
              fish -c "set -gx LD_LIBRARY_PATH ${pkgs.stdenv.cc.cc.lib}/lib:$PWD/bin:\$LD_LIBRARY_PATH" 2>/dev/null || true
            fi

            echo "EC4X Development Shell"
            echo "======================"
            echo "Nim version: $(nim --version | head -1)"
            echo "Nimble version: $(nimble --version)"
            echo "Python version: $(python3.11 --version)"
            echo ""
            echo "Build & Test:"
            echo "  nimble buildSimulation              - Build parallel simulation"
            echo "  ./bin/run_simulation -s 12345       - Run single game (seed 12345)"
            echo "  nimble testBalanceQuick             - Quick balance test (20 games)"
            echo ""
            echo "Advanced:"
            echo "  ./bin/run_simulation -s 42 -t 35 -p 4  - Custom params"
            echo "  python3.11 scripts/run_balance_test_parallel.py"
            echo "    --workers 8 --games 100 --turns 35"
            echo ""
            echo "Analysis:"
            echo "  python3.11 scripts/analysis/your_script.py"
            echo "  # Query SQLite databases in balance_results/diagnostics/"
            echo ""
            echo "─────────────────────────────────────────────"
          '';
        };
      });
}
