{
  description = "Run the Windows version of LINE on Linux with Wine";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      line-wine-script = pkgs.writeShellApplication {
        name = "line-wine";
        runtimeInputs = with pkgs; [
          coreutils
          findutils
          gnugrep
          wineWow64Packages.stable
        ];
        text = ''
                    set -o pipefail

                    data_home="''${XDG_DATA_HOME:-$HOME/.local/share}"
                    export WINEPREFIX="''${LINE_WINEPREFIX:-$data_home/line-wine}"
                    export WINEARCH=win64
                    export WINEDLLOVERRIDES="winemenubuilder.exe=d"

                    usage() {
                      cat <<'EOF'
          Usage:
            line-wine                         Start LINE
            line-wine --install LineInst.exe  Install or update LINE
            line-wine --winecfg               Open Wine configuration

          Environment:
            LINE_WINEPREFIX  Override the Wine prefix (default: $XDG_DATA_HOME/line-wine)
          EOF
                    }

                    initialise_prefix() {
                      if [[ ! -d "$WINEPREFIX/drive_c" ]]; then
                        mkdir -p "$WINEPREFIX"
                        wineboot --init
                        wineserver --wait
                      fi
                    }

                    find_line() {
                      local candidate
                      local wine_user="''${USER:-$(id -un)}"
                      local -a candidates=(
                        "$WINEPREFIX/drive_c/users/$wine_user/AppData/Local/LINE/bin/LineLauncher.exe"
                        "$WINEPREFIX/drive_c/users/$wine_user/AppData/Local/LINE/bin/LINE.exe"
                        "$WINEPREFIX/drive_c/Program Files/LINE/LINE.exe"
                        "$WINEPREFIX/drive_c/Program Files (x86)/LINE/LINE.exe"
                      )

                      for candidate in "''${candidates[@]}"; do
                        if [[ -f "$candidate" ]]; then
                          printf '%s\n' "$candidate"
                          return 0
                        fi
                      done

                      find "$WINEPREFIX/drive_c/users" -type f \
                        \( -iname 'LineLauncher.exe' -o -iname 'LINE.exe' \) \
                        -print -quit 2>/dev/null
                    }

                    case "''${1:-}" in
                      --help|-h)
                        usage
                        exit 0
                        ;;
                      --winecfg)
                        initialise_prefix
                        exec winecfg
                        ;;
                      --install)
                        if [[ $# -ne 2 ]]; then
                          echo "error: --install requires the path to LineInst.exe" >&2
                          usage >&2
                          exit 2
                        fi
                        installer="$(realpath "$2")"
                        if [[ ! -f "$installer" ]]; then
                          echo "error: installer not found: $installer" >&2
                          exit 1
                        fi
                        initialise_prefix
                        wine "$installer"
                        wineserver --wait
                        exit 0
                        ;;
                      "")
                        initialise_prefix
                        line_exe="$(find_line)"
                        if [[ -z "$line_exe" ]]; then
                          echo "LINE is not installed in $WINEPREFIX" >&2
                          echo "Run: line-wine --install /path/to/LineInst.exe" >&2
                          exit 1
                        fi
                        exec wine "$line_exe"
                        ;;
                      *)
                        echo "error: unknown argument: $1" >&2
                        usage >&2
                        exit 2
                        ;;
                    esac
        '';
      };

      desktopItem = pkgs.makeDesktopItem {
        name = "line-wine";
        desktopName = "LINE (Wine)";
        comment = "Run the Windows version of LINE using Wine";
        exec = "line-wine";
        icon = "wine";
        categories = [
          "Network"
          "InstantMessaging"
        ];
        terminal = false;
      };

      line-wine = pkgs.symlinkJoin {
        name = "line-wine";
        paths = [
          line-wine-script
          desktopItem
        ];
      };
    in
    {
      packages.${system} = {
        inherit line-wine;
        default = line-wine;
      };

      apps.${system} = {
        line-wine = {
          type = "app";
          program = "${line-wine}/bin/line-wine";
          meta.description = "Run the Windows version of LINE using Wine";
        };
        default = self.apps.${system}.line-wine;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ line-wine ];
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
