{
  description = "garethstokes.github.io — Jekyll blog (github-pages classic builder)";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAll = nixpkgs.lib.genAttrs systems;
    in {
      devShells = forAll (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = [
              pkgs.ruby_3_3        # github-pages gem (Jekyll 3.10 + plugins) targets Ruby 3.x
              pkgs.bundler
              pkgs.git
              # toolchain for the gems' native extensions
              pkgs.gcc
              pkgs.gnumake
              pkgs.pkg-config
              # native libs those extensions link against
              pkgs.libffi          # ffi
              pkgs.libyaml         # psych
              pkgs.openssl         # eventmachine
              pkgs.zlib            # nokogiri / rb-inotify
              pkgs.libxml2         # nokogiri
              pkgs.libxslt         # nokogiri
            ];
            shellHook = ''
              # Keep gems inside the repo (vendor/bundle) rather than the global
              # gem dir, so the shell is hermetic and `nix develop` leaves no trace.
              export BUNDLE_PATH="vendor/bundle"
              export GEM_HOME="$PWD/vendor/bundle"

              # Build nokogiri against the system libxml2/libxslt above instead of
              # its vendored copies — the vendored build is fragile under Nix.
              export NOKOGIRI_USE_SYSTEM_LIBRARIES=1
              export BUNDLE_BUILD__NOKOGIRI="--use-system-libraries"

              echo "blog devshell — Ruby $(ruby --version | cut -d' ' -f2), bundler $(bundler --version | cut -d' ' -f3)"
              echo "  first run:  bundle install"
              echo "  serve:      bundle exec jekyll serve --drafts --livereload"
            '';
          };
        });
    };
}
