# usage: nix-instantiate --eval --strict bench-ref.nix --arg n 5000 --argstr op parse --argstr impl ours|ref
{ n ? 5000, op ? "parse", impl ? "ours" }:
let
  ours = import ./default.nix;
  ref = (import ./reference.nix).lib.net;
  idx = builtins.genList (i: i) n;
  mk6 = i: "2001:db8:${toString (i / 9000 + 1)}:${toString (i - (i / 9000) * 9000 + 1)}::/64";
  mk4 = i: "10.${toString (i / 65536)}.${toString (i / 256 - (i / 65536) * 256)}.${toString (i - (i / 256) * 256)}/32";
  in6 = map mk6 idx;
  in4 = map mk4 idx;
  sink = x: builtins.deepSeq x 0;
  net6 = "2001:db8::/32";
  net4 = "10.0.0.0/8";
  ops = {
    ours = {
      parse6 = sink (map ours.parse in6);
      parse4 = sink (map ours.parse in4);
      contains6 = let o = ours.parse net6; in sink (map (s: ours.contains o (ours.parse s)) in6);
      contains6Str = sink (map (s: ours.contains (ours.parse net6) (ours.parse s)) in6);
      containsAddr4 = let o = ours.parse net4; in sink (map (s: ours.containsAddr o (ours.parseAddr (builtins.head (builtins.match "([^/]*)/.*" s)))) in4);
      host6 = sink (map (i: ours.formatAddr (ours.host i "2001:db8::/64")) idx);
      host4 = sink (map (i: ours.formatAddr (ours.host i "10.0.0.0/8")) idx);
      subnet6 = sink (map (i: ours.format (ours.subnet 16 i net6)) idx);
      netmask6 = sink (map (i: ours.netmask "2001:db8::/${toString (i - (i / 128) * 128)}") idx);
      merge6 = sink (ours.format (ours.mergev6 in6));
    };
    ref = {
      parse6 = sink (map (s: ref.cidr.make 64 (builtins.head (builtins.match "([^/]*)/.*" s))) in6);
      parse4 = sink (map (s: ref.cidr.make 32 (builtins.head (builtins.match "([^/]*)/.*" s))) in4);
      contains6 = sink (map (s: ref.cidr.contains (builtins.head (builtins.match "([^/]*)/.*" s)) net6) in6);
      contains6Str = sink (map (s: ref.cidr.contains (builtins.head (builtins.match "([^/]*)/.*" s)) net6) in6);
      containsAddr4 = sink (map (s: ref.cidr.contains (builtins.head (builtins.match "([^/]*)/.*" s)) net4) in4);
      host6 = sink (map (i: ref.cidr.host i "2001:db8::/64") idx);
      host4 = sink (map (i: ref.cidr.host i "10.0.0.0/8") idx);
      subnet6 = sink (map (i: ref.cidr.subnet 16 i net6) idx);
      netmask6 = sink (map (i: ref.cidr.netmask "2001:db8::/${toString (i - (i / 128) * 128)}") idx);
      merge6 = sink (ref.cidr.make 0 "::");
    };
  };
in
ops.${impl}.${op}
