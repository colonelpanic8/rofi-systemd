{
  description = "Development shell for rofi-systemd";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllLinuxSystems = f:
        nixpkgs.lib.genAttrs linuxSystems (system: f system);
    in
    {
      checks = forAllLinuxSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          commonPackages = with pkgs; [
            bash
            coreutils
            gnugrep
            gnused
            jq
            rofi
            shellcheck
            systemd
            util-linux
          ];
        in
        {
          shellcheck = pkgs.runCommand "rofi-systemd-shellcheck" { nativeBuildInputs = commonPackages; } ''
            cp ${./rofi-systemd} rofi-systemd
            cp ${./tests/test-rofi-systemd.sh} test-rofi-systemd.sh
            chmod +x rofi-systemd test-rofi-systemd.sh
            shellcheck rofi-systemd test-rofi-systemd.sh
            mkdir -p "$out"
          '';

          tests = pkgs.runCommand "rofi-systemd-tests" { nativeBuildInputs = commonPackages; } ''
            cp -r ${./.} source
            chmod -R +w source
            cd source
            chmod +x rofi-systemd tests/test-rofi-systemd.sh
            bash tests/test-rofi-systemd.sh
            mkdir -p "$out"
          '';
        }
      );

      devShells = forAllLinuxSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              bash
              coreutils
              gawk
              gnugrep
              gnused
              jq
              rofi
              shellcheck
              shfmt
              systemd
              util-linux
            ];
          };
        }
      );
    };
}
