# Differential tests against duairc's netu.nix (reference implementation).
let
  v = import ../../default.nix;
  raw = (import ./reference.nix).lib.net;
  # net.nix (oddlama) wraps host with a range check; reproduce it here
  ref = raw // {
    cidr = raw.cidr // {
      host =
        i: n:
        let
          cap = raw.cidr.capacity n;
          result = raw.cidr.host i n;
          intOk = builtins.isInt i -> (i >= -cap && i < cap);
        in
        assert intOk;
        result;
    };
  };
  # the reference prints some addresses IPv4-style (::0.1.0.0); compare as addresses
  norm =
    x:
    if
      builtins.isString x
      && builtins.match "[0-9a-fA-F:.]+(/[0-9]+)?" x != null
      && builtins.match ".*:.*" x != null
    then
      let
        m = builtins.match "([^/]*)(/.*)?" x;
      in
      fa (v.parseAddr (builtins.head m))
      + (if builtins.elemAt m 1 == null then "" else builtins.elemAt m 1)
    else
      x;
  eq =
    name: a0: b0:
    let
      a = norm a0;
      b = norm b0;
    in
    if a == b then
      true
    else
      throw "PARITY FAIL ${name}: ours ${builtins.toJSON a}, ref ${builtins.toJSON b}";
  fa = v.formatAddr;
  fc = v.format;
  nets = [
    "2001:db8::/32"
    "fd00:fd12:3456:7890::/56"
    "::/0"
    "fe80::/10"
    "dead:cafe:beef::/48"
    "2001:db8:1:2::/64"
    "::1/128"
    "fd00::/120"
  ];
  hostsN = [
    0
    1
    2
    255
    (-1)
    (-2)
    65536
  ];
  cases = builtins.concatMap (n: map (i: { inherit n i; }) hostsN) nets;
in
builtins.all (x: x) (
  # host (including which indices are rejected)
  map (
    c:
    let
      r = builtins.tryEval (ref.cidr.host c.i c.n);
      o = builtins.tryEval (builtins.deepSeq (fa (v.host c.i c.n)) true);
    in
    if r.success != o.success then
      throw "PARITY FAIL host acceptance ${toString c.i} ${c.n}"
    else if r.success then
      eq "host ${toString c.i} ${c.n}" (fa (v.host c.i c.n)) r.value
    else
      true
  ) cases
  ++ map (n: eq "netmask ${n}" (v.netmask n) (ref.cidr.netmask n)) nets
  ++ map (n: eq "length ${n}" (v.length n) (ref.cidr.length n)) nets
  ++ map (n: eq "size ${n}" (v.size n) (ref.cidr.size n)) nets
  ++ map (n: eq "capacity ${n}" (v.capacity n) (ref.cidr.capacity n)) nets
  ++ map (
    n: eq "hostCidr ${n}" (fc (v.hostCidr 3 n)) "${ref.cidr.host 3 n}/${toString (ref.cidr.length n)}"
  ) (builtins.filter (n: n != "::1/128") nets)
  ++ map (
    n:
    eq "canon ${n}" (fc (v.canonicalize "${raw.cidr.host 5 n}/${toString (ref.cidr.length n)}")) (
      ref.cidr.make (ref.cidr.length n) (raw.cidr.host 5 n)
    )
  ) nets
  # subnet
  ++
    builtins.concatMap
      (
        n:
        map
          (
            a:
            eq "subnet ${toString a.l} ${toString a.i} ${n}" (fc (v.subnet a.l a.i n)) (
              ref.cidr.subnet a.l a.i n
            )
          )
          [
            {
              l = 4;
              i = 15;
            }
            {
              l = 16;
              i = 162;
            }
            {
              l = 8;
              i = 3;
            }
            {
              l = 1;
              i = 1;
            }
            {
              l = 0;
              i = 0;
            }
            {
              l = 24;
              i = 12345;
            }
          ]
      )
      [
        "2001:db8::/32"
        "fd00:fd12:3456:7890::/56"
        "dead:cafe::/40"
      ]
  # cidr.add: the reference is broken for IPv6 (shifts an address attrset as an
  # int), so check hand-derived values instead
  ++ map (t: eq "cidrAdd ${toString t.d} ${t.n}" (fc (v.cidrAdd t.d t.n)) t.want) [
    {
      d = 1;
      n = "2001:db8::/32";
      want = "2001:db9::/32";
    }
    {
      d = -1;
      n = "2001:db8::/32";
      want = "2001:db7::/32";
    }
    {
      d = 0;
      n = "2001:db8::/32";
      want = "2001:db8::/32";
    }
    {
      d = 2;
      n = "fd00:fd12:3456:7890::/56";
      want = "fd00:fd12:3456:7a00::/56";
    }
    {
      d = 1;
      n = "2001:db8:1:2::/64";
      want = "2001:db8:1:3::/64";
    }
    {
      d = 1;
      n = "ff00::/8";
      want = "::/8";
    }
    {
      d = -1;
      n = "::/8";
      want = "ff00::/8";
    }
    {
      d = 1;
      n = "::/0";
      want = "::/0";
    }
  ]
  # ip arithmetic: reference is broken (implementations.ip is undefined), so use
  # values computed independently with Python's ipaddress module
  ++ map (t: eq "ip.add ${toString t.d} ${t.a}" (fa (v.ipAdd t.d t.a)) t.want) [
    {
      a = "dead:cafe:beef::";
      d = 0;
      want = "dead:cafe:beef::";
    }
    {
      a = "dead:cafe:beef::";
      d = 1;
      want = "dead:cafe:beef::1";
    }
    {
      a = "dead:cafe:beef::";
      d = 100;
      want = "dead:cafe:beef::64";
    }
    {
      a = "dead:cafe:beef::";
      d = -1;
      want = "dead:cafe:beee:ffff:ffff:ffff:ffff:ffff";
    }
    {
      a = "dead:cafe:beef::";
      d = 4294967296;
      want = "dead:cafe:beef::1:0:0";
    }
    {
      a = "dead:cafe:beef::";
      d = 4294967295;
      want = "dead:cafe:beef::ffff:ffff";
    }
    {
      a = "::ffff:ffff";
      d = 0;
      want = "::ffff:ffff";
    }
    {
      a = "::ffff:ffff";
      d = 1;
      want = "::1:0:0";
    }
    {
      a = "::ffff:ffff";
      d = 100;
      want = "::1:0:63";
    }
    {
      a = "::ffff:ffff";
      d = -1;
      want = "::ffff:fffe";
    }
    {
      a = "::ffff:ffff";
      d = 4294967296;
      want = "::1:ffff:ffff";
    }
    {
      a = "::ffff:ffff";
      d = 4294967295;
      want = "::1:ffff:fffe";
    }
    {
      a = "::ffff:ffff:ffff:ffff";
      d = 0;
      want = "::ffff:ffff:ffff:ffff";
    }
    {
      a = "::ffff:ffff:ffff:ffff";
      d = 1;
      want = "0:0:0:1::";
    }
    {
      a = "::ffff:ffff:ffff:ffff";
      d = 100;
      want = "::1:0:0:0:63";
    }
    {
      a = "::ffff:ffff:ffff:ffff";
      d = -1;
      want = "::ffff:ffff:ffff:fffe";
    }
    {
      a = "::ffff:ffff:ffff:ffff";
      d = 4294967296;
      want = "::1:0:0:ffff:ffff";
    }
    {
      a = "::ffff:ffff:ffff:ffff";
      d = 4294967295;
      want = "::1:0:0:ffff:fffe";
    }
    {
      a = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff";
      d = 0;
      want = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff";
    }
    {
      a = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff";
      d = 1;
      want = "::";
    }
    {
      a = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff";
      d = 100;
      want = "::63";
    }
    {
      a = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff";
      d = -1;
      want = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:fffe";
    }
    {
      a = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff";
      d = 4294967296;
      want = "::ffff:ffff";
    }
    {
      a = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff";
      d = 4294967295;
      want = "::ffff:fffe";
    }
  ]
  ++ map (t: eq "ip.sub ${toString t.d} ${t.a}" (fa (v.ipSubtract t.d t.a)) t.want) [
    {
      a = "dead:cafe:beef::";
      d = 0;
      want = "dead:cafe:beef::";
    }
    {
      a = "dead:cafe:beef::";
      d = 1;
      want = "dead:cafe:beee:ffff:ffff:ffff:ffff:ffff";
    }
    {
      a = "dead:cafe:beef::";
      d = 100;
      want = "dead:cafe:beee:ffff:ffff:ffff:ffff:ff9c";
    }
    {
      a = "dead:cafe:beef::";
      d = 4294967296;
      want = "dead:cafe:beee:ffff:ffff:ffff::";
    }
    {
      a = "::ffff:ffff";
      d = 0;
      want = "::ffff:ffff";
    }
    {
      a = "::ffff:ffff";
      d = 1;
      want = "::ffff:fffe";
    }
    {
      a = "::ffff:ffff";
      d = 100;
      want = "::ffff:ff9b";
    }
    {
      a = "::ffff:ffff";
      d = 4294967296;
      want = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff";
    }
    {
      a = "::ffff:ffff:ffff:ffff";
      d = 0;
      want = "::ffff:ffff:ffff:ffff";
    }
    {
      a = "::ffff:ffff:ffff:ffff";
      d = 1;
      want = "::ffff:ffff:ffff:fffe";
    }
    {
      a = "::ffff:ffff:ffff:ffff";
      d = 100;
      want = "::ffff:ffff:ffff:ff9b";
    }
    {
      a = "::ffff:ffff:ffff:ffff";
      d = 4294967296;
      want = "::ffff:fffe:ffff:ffff";
    }
    {
      a = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff";
      d = 0;
      want = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff";
    }
    {
      a = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff";
      d = 1;
      want = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:fffe";
    }
    {
      a = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff";
      d = 100;
      want = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ff9b";
    }
    {
      a = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff";
      d = 4294967296;
      want = "ffff:ffff:ffff:ffff:ffff:fffe:ffff:ffff";
    }
  ]
  ++ map (t: eq "ip.diff ${t.a} ${t.b}" (v.ipDiff t.a t.b) t.want) [
    {
      a = "dead:cafe:beef::2710";
      b = "dead:cafe:beef::";
      want = 10000;
    }
    {
      a = "dead:cafe:beef::";
      b = "dead:cafe:beef::2710";
      want = -10000;
    }
    {
      a = "::1:0:0:0";
      b = "::";
      want = 281474976710656;
    }
    {
      a = "::";
      b = "::1";
      want = -1;
    }
  ]
  ++ [
    (eq "mergedoc" (fc (
      v.mergev6 [
        "fd00:dead:cafe::/64"
        "fd00:fd12:3456:7890::/56"
      ]
    )) "fd00:c000::/18")
    (eq "embedded" (fa (v.parseAddr "::ffff:1.2.3.4")) "::ffff:102:304")
    (eq "embedded-ref" (fa (v.parseAddr "64:ff9b::192.0.2.33")) "64:ff9b::c000:221")
    (eq "child" (v.child "2001:db8:1::/48" "2001:db8::/32") (
      ref.cidr.child "2001:db8:1::/48" "2001:db8::/32"
    ))
    (eq "child-eq" (v.child "2001:db8::/32" "2001:db8::/32") (
      ref.cidr.child "2001:db8::/32" "2001:db8::/32"
    ))
    (eq "child-no" (v.child "2001:db9::/48" "2001:db8::/32") (
      ref.cidr.child "2001:db9::/48" "2001:db8::/32"
    ))
    (eq "contains" (v.containsAddr (v.parse "fe80::/10") (v.parseAddr "febf::1")) (
      ref.cidr.contains "febf::1" "fe80::/10"
    ))
  ]
  # mergev6 vs ref (from net.nix wrapper logic, reimplemented with ref primitives)
  ++ (
    let
      refMerge =
        addrs_:
        let
          addrs = map (x: if builtins.match ".*/.*" x != null then x else "${x}/128") addrs_;
          ip = x: builtins.head (builtins.split "/" x);
          start = builtins.foldl' (a: b: if b < a then b else a) 128 (map ref.cidr.length addrs);
          lens = builtins.genList (i: start - i) (start + 1);
          first = ip (builtins.head addrs);
          best = builtins.head (
            builtins.filter (
              len: builtins.all (x: ref.cidr.contains (ip x) (ref.cidr.make len first)) addrs
            ) lens
          );
        in
        ref.cidr.make best first;
      sets = [
        [
          "fd00:dead:cafe::/64"
          "fd00:fd12:3456:7890::/56"
        ]
        [
          "2001:db8::1"
          "2001:db8::2"
        ]
        [ "2001:db8::1" ]
        [
          "2001:db8:1::/48"
          "2001:db8:2::/48"
          "2001:db8:3::/48"
        ]
        [
          "::1"
          "8000::1"
        ]
        [
          "2001:db8:0:0:1::5/64"
          "2001:db8::/32"
        ]
      ];
    in
    map (s: eq "merge ${builtins.toJSON s}" (fc (v.mergev6 s)) (refMerge s)) sets
  )
)
