{
  description = "EC4X Nim & Data Science Shell";

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
            # 1. Nim Core
            nim
            nimble
            
            # 2. Python (for Polars scripts)
            python311
            python311Packages.pip
            
            # 3. System Tools
            sqlite
            git
            
            # 4. Critical for Polars/Nim binaries
            stdenv.cc.cc.lib
          ];

          shellHook = ''
            # Ensures compiled Nim and Python wheels (Polars) can find C++ libs
            export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH"
            
            # Keep your API key available for Gemini/AI tools
            [ -f ~/.config/aider/gemini_key ] && export GEMINI_API_KEY=$(cat ~/.config/aider/gemini_key)

            echo "🚀 EC4X Environment Active"
            echo "Nim $(nim --version | head -n1) | Python $(python --version)"
            echo "Polars ready (via LD_LIBRARY_PATH)"
          '';
        };
      });
}