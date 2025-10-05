{
  description = "Frontier Zig prototype";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        src = pkgs.lib.cleanSource ./.;

        frontierZig = pkgs.stdenv.mkDerivation {
          pname = "frontier-zig";
          version = "0.0.1";
          inherit src;

          nativeBuildInputs = with pkgs; [ zig just bash ];

          dontConfigure = true;
          buildPhase = ''
            runHook preBuild
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-global-cache
            export ZIG_LOCAL_CACHE_DIR=$TMPDIR/zig-local-cache
            zig build --build-file zig/build.zig --prefix $out
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            runHook postInstall
          '';

          doCheck = false;
        };

        ciScript = pkgs.writeShellApplication {
          name = "frontier-zig-ci";
          runtimeInputs = with pkgs; [ bash git zig just ];
          text = ''
            set -euo pipefail
            exec ${./scripts/ci.sh}
          '';
        };

      in
      {
        packages = {
          default = frontierZig;
          frontier-zig = frontierZig;
          ci = ciScript;
        };

        checks = {
          build = frontierZig;
          ci = pkgs.runCommand "frontier-zig-ci-check" { buildInputs = [ ciScript ]; } ''
            export FRONTIER_ZIG_CI_ROOT=${src}
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-global-cache
            export ZIG_LOCAL_CACHE_DIR=$TMPDIR/zig-local-cache
            ${ciScript}/bin/frontier-zig-ci
            touch $out
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            zig
            just
            git
            bashInteractive
            bun
            rustc
            cargo
            pkg-config
            sqlite
          ];

          shellHook = ''
            echo "Frontier Zig development environment"
            echo "Commands:" 
            echo "  just run      - build and run the prototype"
            echo "  just ci       - run project checks"
            echo "  nix run .#ci  - run CI pipeline"
          '';
        };

        apps.default = flake-utils.lib.mkApp {
          drv = frontierZig;
        };

        apps.ci = flake-utils.lib.mkApp {
          drv = ciScript;
        };
      }
    );
}
