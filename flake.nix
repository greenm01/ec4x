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

            echo "EC4X Development Shell"
            echo "======================"
            echo "Nim version: $(nim --version | head -1)"
            echo "Nimble version: $(nimble --version)"
            echo "Python version: $(python3.11 --version)"
            echo ""
            echo "Available commands:"
            echo "  nimble install -d  - Install dependencies"
            echo "  nimble build       - Build all components"
            echo "  nimble test        - Run tests"
            echo "  nimble tasks       - Show all available tasks"
            echo ""
            echo "C API:"
            echo "  nimble buildCAPI                      - Build parallel C simulation"
            echo "  ./bin/run_simulation_c --turns 10     - Run parallel simulation"
            echo "  ./bin/run_c --turns 10 --seed 12345   - Convenience wrapper"
            echo ""
            echo "AI Training:"
            echo "  cd ai_training && ./setup_amd_ml.sh  - Setup ML environment"
            echo "  python3.11 training_daemon.py        - Start continuous training"
            echo ""
            echo "Quick start:"
            echo "  nimble build"
            echo "  ./bin/moderator new my_game"
            echo "  ./bin/client offline --players=4"
            echo ""

            # Launch fish if available (suppress greeting)
            if command -v fish >/dev/null 2>&1; then
              exec fish -C "function fish_greeting; end; set -x LD_LIBRARY_PATH $PWD/bin $LD_LIBRARY_PATH"
            fi
          '';
        };
      });
}
