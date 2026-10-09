{
  description = "IPv4, IPv6 and MAC address calculator in pure Nix";

  outputs = _: {
    lib = import ./default.nix;
  };
}
