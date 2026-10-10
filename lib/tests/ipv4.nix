let
  v = import ../../default.nix;
  eq =
    name: a: b:
    if a == b then true else throw "FAIL ${name}: got ${builtins.toJSON a}, want ${builtins.toJSON b}";
  fc = v.format;
  fa = v.formatAddr;
  c = v.parse;
  fails = e: !(builtins.tryEval (builtins.deepSeq e true)).success;
in
builtins.all (x: x) [
  (eq "rt" (fc (c "192.168.1.77/24")) "192.168.1.0/24")
  (eq "bare" (fc (c "10.1.2.3")) "10.1.2.3/32")
  (eq "netmask" (v.netmask "192.168.0.0/24") "255.255.255.0")
  (eq "netmask12" (v.netmask "172.16.0.0/12") "255.240.0.0")
  (eq "netmask0" (v.netmask "0.0.0.0/0") "0.0.0.0")
  (eq "last" (fa (v.host (-1) "192.168.1.0/24")) "192.168.1.255")
  (eq "contains" (v.containsAddr (c "127.0.0.0/8") (v.parseAddr "127.0.0.1")) true)
  (eq "not-contains" (v.containsAddr (c "192.168.0.0/16") (v.parseAddr "127.0.0.1")) false)
  (eq "family" (v.containsAddr (c "0.0.0.0/0") (v.parseAddr "::1")) false)
  (eq "family2" (v.contains (c "::/0") (c "10.0.0.0/8")) false)
  (eq "overlaps" (v.overlaps (c "10.0.0.0/8") (c "10.1.0.0/16")) true)
  (eq "child" (v.child "10.10.10.0/24" "10.0.0.0/8") true)
  (eq "child-no" (v.child "127.0.0.0/8" "10.0.0.0/8") false)
  (eq "size" (v.size "127.0.0.0/8") 24)
  (eq "len" (v.length "10.1.2.3/20") 20)
  (eq "ip" (fa (v.ip "192.168.1.100/24")) "192.168.1.100")
  (eq "canon" (fc (v.canonicalize "192.168.1.100/24")) "192.168.1.0/24")
  (eq "make" (fc (v.make 24 "192.168.0.150")) "192.168.0.0/24")
  (eq "make-clamp" (fc (v.make 99 "192.168.0.150")) "192.168.0.150/32")
  (eq "hostCidr" (fc (v.hostCidr 2 "192.168.1.0/24")) "192.168.1.2/24")
  (eq "host" (fa (v.host 255 "192.168.1.0/24")) "192.168.1.255")
  (eq "host-neg" (fa (v.host (-1) "192.168.1.0/24")) "192.168.1.255")
  (eq "host-neg256" (fa (v.host (-256) "192.168.1.0/24")) "192.168.1.0")
  (eq "host-oob" (fails (v.host 256 "192.168.1.0/24")) true)
  (eq "host-oob-neg" (fails (v.host (-257) "192.168.1.0/24")) true)
  (eq "host-big" (fa (v.host 10000 "10.0.0.0/8")) "10.0.39.16")
  (eq "subnet" (fc (v.subnet 4 15 "10.1.2.0/24")) "10.1.2.240/28")
  (eq "subnet2" (fc (v.subnet 4 2 "172.16.0.0/12")) "172.18.0.0/16")
  (eq "subnets"
    (map (i: fc (v.subnet 2 i "192.168.0.0/24")) [
      0
      1
      2
      3
    ])
    [
      "192.168.0.0/26"
      "192.168.0.64/26"
      "192.168.0.128/26"
      "192.168.0.192/26"
    ]
  )
  (eq "add" (fc (v.cidrAdd 2 "127.0.0.0/8")) "129.0.0.0/8")
  (eq "add-neg" (fc (v.cidrAdd (-2) "127.0.0.0/8")) "125.0.0.0/8")
  (eq "add-wrap" (fc (v.cidrAdd 1 "255.0.0.0/8")) "0.0.0.0/8")
  (eq "ipadd" (fa (v.ipAdd 100 "10.0.0.1")) "10.0.0.101")
  (eq "ipadd-wrap" (fa (v.ipAdd 1 "255.255.255.255")) "0.0.0.0")
  (eq "ipsub-wrap" (fa (v.ipSubtract 1 "0.0.0.0")) "255.255.255.255")
  (eq "ipadd-neg" (fa (v.ipAdd (-1) "10.0.0.0")) "9.255.255.255")
  (eq "ipdiff" (v.ipDiff "10.0.0.101" "10.0.0.1") 100)
  (eq "ipdiff-neg" (v.ipDiff "10.0.0.1" "10.0.0.101") (-100))
  (eq "mergev4" (fc (
    v.mergev4 [
      "192.168.1.1/24"
      "192.168.6.1/32"
    ]
  )) "192.168.0.0/21")
  (eq "merge-single" (fc (v.mergev4 [ "10.0.0.1" ])) "10.0.0.1/32")
  (eq "merge-empty" (v.mergev4 [ ]) null)
  (eq "merge-split"
    (
      let
        m = v.merge [
          "10.0.0.1"
          "10.0.0.2"
          "fd00::1"
          "fd00::2"
        ];
      in
      [
        (fc m.cidrv4)
        (fc m.cidrv6)
      ]
    )
    [
      "10.0.0.0/30"
      "fd00::/126"
    ]
  )
  (eq "merge-wrong" (fails (v.mergev4 [ "::1" ])) true)
  (eq "merge-mixed" (fails (
    v.mergev6 [
      "::1"
      "10.0.0.1"
    ]
  )) true)
  (eq "agg"
    (v.parseAggregate [
      "10.0.0.0/25"
      "10.0.0.128/25"
      "10.0.1.0/24"
      "192.168.0.0/24"
      "10.0.0.5/32"
    ])
    [
      "10.0.0.0/23"
      "192.168.0.0/24"
    ]
  )
  (eq "agg-mixed"
    (v.parseAggregate [
      "2001:db8::/33"
      "2001:db8:8000::/33"
      "10.0.0.0/25"
      "10.0.0.128/25"
    ])
    [
      "10.0.0.0/24"
      "2001:db8::/32"
    ]
  )
  (eq "agg-0" (v.parseAggregate [
    "0.0.0.0/1"
    "128.0.0.0/1"
  ]) [ "0.0.0.0/0" ])
  (eq "v4-v6-no-merge"
    (v.parseAggregate [
      "0.0.0.0/0"
      "::/0"
    ])
    [
      "0.0.0.0/0"
      "::/0"
    ]
  )
  (eq "isv4" [ (v.isv4 "10.0.0.1/8") (v.isv6 "10.0.0.1") (v.isv6 "::1/128") ] [ true false true ])
  (eq "bad-octet" (fails (v.parse "10.0.0.256/8")) true)
  (eq "bad-short" (fails (v.parse "10.0.0/8")) true)
  (eq "bad-leading0" (fails (v.parse "10.00.0.1/8")) true)
  (eq "bad-prefix" (fails (v.parse "10.0.0.0/33")) true)
  (eq "assign-order" (v.assignIps "192.168.100.0/24" [ ] [ "a" "b" "c" ]) (
    v.assignIps "192.168.100.0/24" [ ] [ "c" "a" "b" ]
  ))
  (eq "assign-stable" (builtins.removeAttrs (v.assignIps "192.168.100.0/24" [ ] [ "a" "b" "c" "d" ]) [
    "d"
  ]) (v.assignIps "192.168.100.0/24" [ ] [ "a" "b" "c" ]))
  (eq "assign-in-net" (builtins.all (a: v.containsAddr (c "192.168.100.0/24") (v.parseAddr a)) (
    builtins.attrValues (v.assignIps "192.168.100.0/24" [ ] [ "a" "b" "c" ])
  )) true)
  (eq "assign-no-net-bcast" (builtins.any (a: a == "192.168.100.0" || a == "192.168.100.255") (
    builtins.attrValues (v.assignIps "192.168.100.0/24" [ ] (map toString (builtins.genList (i: i) 70)))
  )) false)
  (eq "assign-unique" (builtins.length (
    builtins.attrNames (
      builtins.listToAttrs (
        map
          (a: {
            name = a;
            value = 1;
          })
          (
            builtins.attrValues (v.assignIps "192.168.100.0/24" [ ] (map toString (builtins.genList (i: i) 70)))
          )
      )
    )
  )) 70)
  (eq "assign-reserved" (builtins.elem "192.168.100.5" (
    builtins.attrValues (
      v.assignIps "192.168.100.0/24" [ "192.168.100.5" ] (map toString (builtins.genList (i: i) 70))
    )
  )) false)
  (eq "mac-via-default" (v.mac.format (v.mac.add 1 "00:00:00:00:00:ff")) "00:00:00:00:01:00")
]
