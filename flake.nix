{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { self, nixpkgs, sops-nix, ... }: {
    nixosConfigurations = {
      media-services = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          sops-nix.nixosModules.sops
          ./nixos/common.nix
          ./nixos/hosts/media-services/configuration.nix
        ];
      };
      infrastructure = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          sops-nix.nixosModules.sops
          ./nixos/common.nix
          ./nixos/hosts/infrastructure/configuration.nix
        ];
      };
    };
  };
}
