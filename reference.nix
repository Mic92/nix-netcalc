# duairc's netu.nix (via oddlama/nixos-extra-modules), fetched for the parity
# tests instead of being vendored.
(import "${
  builtins.fetchTarball {
    url = "https://github.com/oddlama/nixos-extra-modules/archive/f097b474fcb5db7dfd52263c055c9e6caeb13d62.tar.gz";
    sha256 = "sha256-b3rJDKxzsf7p4wI698iBi2PInDPRH3KwjdqOk/SahKk=";
  }
}/lib/netu.nix" { })
