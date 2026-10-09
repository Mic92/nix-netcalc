# usage: nix-instantiate --eval --strict bench.nix --arg n 10000 --argstr op parse
{
  n ? 10000,
  op ? "parse",
}:
let
  v = import ./default.nix;
  idx = builtins.genList (i: i) n;
  mk = i: "2001:db8:${toString (i / 9000 + 1)}:${toString (i - (i / 9000) * 9000 + 1)}::/64";
  inputs = map mk idx;
  parsed = map v.parse inputs;
  noop = builtins.deepSeq inputs 0;
  sink = x: builtins.deepSeq x 0;
in
{
  inherit noop;
  parse = sink parsed;
  format = sink (map v.format parsed);
  contains = sink (map (c: v.contains (v.parse "2001:db8::/32") c) parsed);
  aggregate = sink (v.aggregate parsed);
  subnet = sink (map (i: v.subnet 16 i "2001:db8::/32") (builtins.genList (i: i) n));
}
.${op}
