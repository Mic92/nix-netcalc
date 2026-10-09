let
  v = import ./default.nix;
  eq =
    name: a: b:
    if a == b then true else throw "FAIL ${name}: got ${builtins.toJSON a}, want ${builtins.toJSON b}";
  c = v.parse;
in
builtins.all (x: x) [
  (eq "fmt1" (v.format (c "2001:0db8:0:0:0:0:0:1/64")) "2001:db8::/64")
  (eq "fmt2" (v.formatAddr (v.parseAddr "::")) "::")
  (eq "fmt3" (v.formatAddr (v.parseAddr "::1")) "::1")
  (eq "fmt4" (v.formatAddr (v.parseAddr "1:0:0:2:0:0:0:3")) "1:0:0:2::3")
  (eq "fmt5" (v.formatAddr (v.parseAddr "1:0:2:3:4:5:6:7")) "1:0:2:3:4:5:6:7")
  (eq "fmt6" (v.formatAddr (v.parseAddr "FE80::ABCD")) "fe80::abcd")
  (eq "netmask" (v.netmask (c "::/37")) "ffff:ffff:f800::")
  (eq "last" (v.formatAddr (v.host (-1) "2001:db8::/32")) "2001:db8:ffff:ffff:ffff:ffff:ffff:ffff")
  (eq "contains" (v.contains (c "2001:db8::/32") (c "2001:db8:1::/48")) true)
  (eq "notcontains" (v.contains (c "2001:db8:1::/48") (c "2001:db8::/32")) false)
  (eq "overlap" (v.overlaps (c "2001:db8::/32") (c "2001:db9::/32")) false)
  (eq "addr" (v.containsAddr (c "fe80::/10") (v.parseAddr "febf::1")) true)
  (eq "subnets"
    (map (i: v.format (v.subnet 2 i "2001:db8::/32")) [
      0
      1
      2
      3
    ])
    [
      "2001:db8::/34"
      "2001:db8:4000::/34"
      "2001:db8:8000::/34"
      "2001:db8:c000::/34"
    ]
  )
  (eq "subnet-host-bits"
    (map (i: v.format (v.subnet 1 i "::ffff:ffff:ffff:ffff/65")) [
      0
      1
    ])
    [
      "::8000:0:0:0/66"
      "::c000:0:0:0/66"
    ]
  )
  (eq "agg"
    (v.parseAggregate [
      "10::/17"
      "10:8000::/17"
      "10::/20"
      "2001:db8::/33"
      "2001:db8:8000::/33"
      "3::/16"
    ])
    [
      "3::/16"
      "10::/16"
      "2001:db8::/32"
    ]
  )
  (eq "size" (v.size (c "::/120")) 8)
  (eq "assign-order" (v.assignIps "fd00::/112" [ ] [ "a" "b" "c" ]) (
    v.assignIps "fd00::/112" [ ] [ "c" "a" "b" ]
  ))
  (eq "assign-stable" (builtins.removeAttrs (v.assignIps "fd00::/112" [ ] [ "a" "b" "c" "d" ]) [
    "d"
  ]) (v.assignIps "fd00::/112" [ ] [ "a" "b" "c" ]))
  (eq "assign-unique" (builtins.length (
    builtins.attrNames (
      builtins.listToAttrs (
        map (a: {
          name = a;
          value = 1;
        }) (builtins.attrValues (v.assignIps "fd00::/120" [ ] (map toString (builtins.genList (i: i) 100))))
      )
    )
  )) 100)
  (eq "assign-reserved" (builtins.any (a: a == "fd00::" || a == "fd00::ff") (
    builtins.attrValues (v.assignIps "fd00::/120" [ ] (map toString (builtins.genList (i: i) 100)))
  )) false)
  (eq "assign-in-net" (builtins.all (a: v.containsAddr (v.parse "fd00::/112") (v.parseAddr a)) (
    builtins.attrValues (v.assignIps "fd00::/112" [ ] [ "a" "b" "c" ])
  )) true)
  (eq "assign-reserve-ip" (builtins.any (a: a == "fd00::5") (
    builtins.attrValues (
      v.assignIps "fd00::/120" [ "fd00::5" ] (map toString (builtins.genList (i: i) 100))
    )
  )) false)
  (eq "host-oob" (builtins.tryEval (v.host 256 "fd00::/120")).success false)
  (eq "host-neg" (v.formatAddr (v.host (-1) "fd00::/120")) "fd00::ff")
  (eq "bad-v4" (builtins.tryEval (v.parseAddr "::1.2.3.256")).success false)
]
