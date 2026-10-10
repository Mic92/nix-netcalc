# Single entry point: nix-instantiate --eval --strict lib/tests
# Evaluates to true if every suite passes; otherwise the failing assertion is
# thrown with the name of its suite.
let
  suites = {
    ipv4 = import ./ipv4.nix;
    ipv6 = import ./ipv6.nix;
    mac = import ./mac.nix;
    parity = import ./parity.nix;
  };
in
builtins.all (x: x) (
  builtins.attrValues (
    builtins.mapAttrs (name: result: builtins.addErrorContext "in test suite '${name}'" result) suites
  )
)
