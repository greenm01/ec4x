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

            # Python AI development
            python311
            python311Packages.pip
            python311Packages.virtualenv
            aider-chat
            python311Packages.google-generativeai

            # Data Analysis Stack (Terminal-focused)
            python311Packages.polars       # Fast DataFrame library (already present)
            python311Packages.pyarrow      # Parquet I/O backend
            python311Packages.rich         # Beautiful terminal output
            python311Packages.tabulate     # ASCII/Markdown tables
            python311Packages.numpy        # Statistical functions
            python311Packages.scipy        # Advanced statistics
            python311Packages.click        # CLI framework

            # dev tools
            git
            git-filter-repo 
            
          ];
          shellHook = ''
            export IN_NIX_SHELL=1
            export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH"

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
              exec fish -C "function fish_greeting; end"
            fi
          '';
        };
      });
}
