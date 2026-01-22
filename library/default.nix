{
  self,
  defaultStateVersion ? "25.05",
}: {
  generateVMAImage = import "${self}/library/generateVMAImage" {
    inherit defaultStateVersion self;
  };
  makeConfiguration = import "${self}/library/makeConfiguration.nix" {
    inherit defaultStateVersion self;
  };
  makeDualExport = import "${self}/library/makeDualExport.nix" {
    inherit defaultStateVersion self;
  };
  forAllSystems = self.inputs.nixpkgsStable.lib.genAttrs [
    "x86_64-linux"
    "aarch64-linux"
  ];
}