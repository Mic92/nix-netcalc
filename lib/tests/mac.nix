let
  m = import ../mac.nix;
  eq =
    name: a: b:
    if a == b then true else throw "FAIL ${name}: got ${builtins.toJSON a}, want ${builtins.toJSON b}";
in
builtins.all (x: x) [
  (eq "rt" (m.format (m.parse "FE:ed:fa:ce:f0:0d")) "fe:ed:fa:ce:f0:0d")
  (eq "add" (m.format (m.add 100 "fe:ed:fa:ce:f0:0d")) "fe:ed:fa:ce:f0:71")
  (eq "add-mac" (m.format (m.add "fe:ed:fa:00:00:00" "00:00:00:ce:f0:0d")) "fe:ed:fa:ce:f0:0d")
  (eq "wrap" (m.format (m.add 1 "ff:ff:ff:ff:ff:ff")) "00:00:00:00:00:00")
  (eq "sub" (m.format (m.subtract 100 "fe:ed:fa:ce:f0:71")) "fe:ed:fa:ce:f0:0d")
  (eq "sub-wrap" (m.format (m.subtract 1 "00:00:00:00:00:00")) "ff:ff:ff:ff:ff:ff")
  (eq "diff" (m.diff "fe:ed:fa:ce:f0:71" "fe:ed:fa:ce:f0:0d") 100)
  (eq "private" (m.addPrivate "00:11:22:33:44:55" 1) "02:11:22:33:44:56")
  (eq "bad" (builtins.tryEval (m.parse "zz:ed:fa:ce:f0:0d")).success false)
  (eq "bad2" (builtins.tryEval (m.parse "fe:ed:fa:ce:f0")).success false)
  (
    let
      a = m.assignMacs "11:22:33:00:00:00" 24 [ ] [ "a" "b" "c" ];
    in
    eq "assign-in-range" (builtins.all (x: builtins.substring 0 9 x == "11:22:33:") (
      builtins.attrValues a
    )) true
  )
  (eq "assign-order" (m.assignMacs "11:22:33:00:00:00" 24 [ ] [ "a" "b" "c" ]) (
    m.assignMacs "11:22:33:00:00:00" 24 [ ] [ "c" "b" "a" ]
  ))
  (eq "assign-stable" (builtins.removeAttrs (m.assignMacs "11:22:33:00:00:00" 24
    [ ]
    [ "a" "b" "c" "d" ]
  ) [ "d" ]) (m.assignMacs "11:22:33:00:00:00" 24 [ ] [ "a" "b" "c" ]))
  (eq "assign-reserved" (builtins.elem "11:22:33:1b:bd:ca" (
    builtins.attrValues (m.assignMacs "11:22:33:00:00:00" 24 [ "11:22:33:1b:bd:ca" ] [ "a" "b" "c" ])
  )) false)
]
