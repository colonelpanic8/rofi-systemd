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
      devShells = forAllLinuxSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              gawk
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
