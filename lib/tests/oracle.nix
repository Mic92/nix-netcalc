# Compares the library against oracle-data.json, whose expected values come
# from Python's ipaddress module (see gen-oracle.py).
let
  v = import ../../default.nix;
  d = builtins.fromJSON (builtins.readFile ./oracle-data.json);
  at = builtins.elemAt;
  eq =
    name: got: want:
    if got == want then
      true
    else
      throw "FAIL ${name}: got ${builtins.toJSON got}, want ${builtins.toJSON want}";
  fails = e: !(builtins.tryEval (builtins.deepSeq e true)).success;
  fa = v.formatAddr;
  fc = v.format;
  rows = name: f: map (r: builtins.addErrorContext "in oracle table '${name}'" (f r)) d.${name};
in
builtins.all (x: x) (
  rows "host" (
    r:
    let
      n = at r 0;
      i = at r 1;
      want = at r 2;
    in
    if want == null then
      eq "host ${toString i} ${n} is rejected" (fails (v.host i n)) true
    else
      eq "host ${toString i} ${n}" (fa (v.host i n)) want
  )
  ++ rows "accessors" (
    r:
    let
      n = at r 0;
    in
    builtins.all (x: x) [
      (eq "netmask ${n}" (v.netmask n) (at r 1))
      (eq "length ${n}" (v.length n) (at r 2))
      (eq "size ${n}" (v.size n) (at r 3))
      (eq "capacity ${n}" (v.capacity n) (at r 4))
    ]
  )
  ++ rows "canonicalize" (r: eq "canonicalize ${at r 0}" (fc (v.canonicalize (at r 0))) (at r 1))
  ++ rows "subnet" (
    r:
    let
      n = at r 0;
      l = at r 1;
      i = at r 2;
    in
    eq "subnet ${toString l} ${toString i} ${n}" (fc (v.subnet l i n)) (at r 3)
  )
  ++ rows "cidrAdd" (
    r:
    let
      n = at r 0;
      delta = at r 1;
      want = at r 2;
      got = v.cidrAdd delta n;
    in
    builtins.all (x: x) [
      (eq "cidrAdd ${toString delta} ${n}" (fc got) want)
      # The record must equal a freshly parsed network, not just print the same.
      (eq "cidrAdd ${toString delta} ${n} record" got (v.parse want))
    ]
  )
  ++ rows "contains" (
    r:
    let
      n = at r 0;
      a = at r 1;
    in
    eq "containsAddr ${a} ${n}" (v.containsAddr (v.parse n) (v.parseAddr a)) (at r 2)
  )
  ++ rows "child" (r: eq "child ${at r 0} ${at r 1}" (v.child (at r 0) (at r 1)) (at r 2))
  ++ rows "ipAdd" (
    r:
    let
      a = at r 0;
      delta = at r 1;
    in
    eq "ipAdd ${toString delta} ${a}" (fa (v.ipAdd delta a)) (at r 2)
  )
  ++ rows "ipSubtract" (
    r:
    let
      a = at r 0;
      delta = at r 1;
    in
    eq "ipSubtract ${toString delta} ${a}" (fa (v.ipSubtract delta a)) (at r 2)
  )
  ++ rows "ipDiff" (r: eq "ipDiff ${at r 0} ${at r 1}" (v.ipDiff (at r 0) (at r 1)) (at r 2))
  ++ rows "merge" (
    r:
    let
      inputs = at r 0;
      merged = if v.isv4 (builtins.head inputs) then v.mergev4 inputs else v.mergev6 inputs;
    in
    eq "merge ${builtins.toJSON inputs}" (fc merged) (at r 1)
  )
)
