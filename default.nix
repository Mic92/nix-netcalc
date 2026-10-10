# Fast IPv4/IPv6/MAC calculator in pure Nix (builtins only).
# An address is 4 x 32-bit words (big endian), so every operation fits in
# Nix's signed 64-bit ints and uses only bitAnd/bitOr/bitXor.
# IPv4 lives in the low word (upper words zero) and its prefix is stored
# offset by 96, so one set of 128-bit routines serves both families.
# A CIDR is { addr = [w0 w1 w2 w3]; prefix = n; v4 = bool; }.
let
  inherit (builtins)
    elemAt
    head
    length
    genList
    foldl'
    filter
    sort
    concatStringsSep
    stringLength
    substring
    split
    isList
    bitAnd
    bitOr
    bitXor
    concatLists
    ;

  stringToCharacters = s: genList (i: substring i 1 s) (stringLength s);

  full = 4294967295; # 0xFFFFFFFF

  pow2Table = genList (i: if i == 0 then 1 else 2 * elemAt pow2Table (i - 1)) 33;
  pow2 = k: elemAt pow2Table k;

  clamp =
    lo: hi: x:
    if x < lo then
      lo
    else if x > hi then
      hi
    else
      x;

  # mask of the first n bits of a 32-bit word
  wordMask = n: full - (pow2 (32 - clamp 0 32 n) - 1);
  # lazy table: each mask is computed once, on first use
  maskTable = genList (p: genList (i: wordMask (p - 32 * i)) 4) 129;
  maskWords = p: elemAt maskTable p;
  invMaskTable = genList (p: map (m: bitXor m full) (elemAt maskTable p)) 129;

  zipWords =
    f: a: b:
    genList (i: f (elemAt a i) (elemAt b i)) 4;

  hexVal = {
    "0" = 0;
    "1" = 1;
    "2" = 2;
    "3" = 3;
    "4" = 4;
    "5" = 5;
    "6" = 6;
    "7" = 7;
    "8" = 8;
    "9" = 9;
    a = 10;
    b = 11;
    c = 12;
    d = 13;
    e = 14;
    f = 15;
    A = 10;
    B = 11;
    C = 12;
    D = 13;
    E = 14;
    F = 15;
  };
  hexChars = stringToCharacters "0123456789abcdef";

  # Two-hex-digit to byte lookup, for all case combinations.
  # A hextet is two table hits on a zero-padded string.
  byteTable =
    let
      digits = [
        "0"
        "1"
        "2"
        "3"
        "4"
        "5"
        "6"
        "7"
        "8"
        "9"
        "a"
        "b"
        "c"
        "d"
        "e"
        "f"
        "A"
        "B"
        "C"
        "D"
        "E"
        "F"
      ];
      val = d: hexVal.${d};
    in
    builtins.listToAttrs (
      concatLists (
        map (
          h:
          map (l: {
            name = h + l;
            value = val h * 16 + val l;
          }) digits
        ) digits
      )
    );

  parseHextet =
    s:
    let
      n = stringLength s;
      p = substring n 4 ("0000" + s);
    in
    if n < 1 || n > 4 then
      throw "ipv6: bad group '${s}'"
    else
      (byteTable.${substring 0 2 p} or (throw "ipv6: bad group '${s}'")) * 256
      + (byteTable.${substring 2 2 p} or (throw "ipv6: bad group '${s}'"));

  groups =
    s: if s == "" then [ ] else map parseHextet (builtins.filter builtins.isString (split ":" s));

  hextetsToWords = h: genList (i: elemAt h (2 * i) * 65536 + elemAt h (2 * i + 1)) 4;

  # "::ffff:1.2.3.4" -> "::ffff:102:304"
  expandV4 =
    s:
    let
      m = builtins.match "(.*:)([0-9]+)\\.([0-9]+)\\.([0-9]+)\\.([0-9]+)" s;
    in
    if m == null then
      s
    else
      let
        o = map builtins.fromJSON (builtins.tail m);
        a = elemAt o 0;
        b = elemAt o 1;
        c = elemAt o 2;
        d = elemAt o 3;
      in
      if builtins.any (x: x > 255) o then
        throw "ipv6: bad IPv4 part in '${s}'"
      else
        head m + hex (a * 256 + b) + ":" + hex (c * 256 + d);

  parseAddr6 =
    s0:
    let
      s = expandV4 s0;
      m = builtins.match "([^:]*(:[^:]+)*)?::([^:]*(:[^:]+)*)?" s;
    in
    if m == null then
      let
        g = groups s;
      in
      if length g != 8 then throw "ipv6: bad address '${s}'" else hextetsToWords g
    else
      let
        l = groups (
          let
            x = head m;
          in
          if x == null then "" else x
        );
        r = groups (
          let
            x = elemAt m 2;
          in
          if x == null then "" else x
        );
        fill = 8 - length l - length r;
      in
      if fill < 1 then
        throw "ipv6: bad '::' in '${s}'"
      else
        hextetsToWords (l ++ genList (_: 0) fill ++ r);

  hex = n: if n < 16 then elemAt hexChars n else hex (n / 16) + elemAt hexChars (bitAnd n 15);

  wordsToHextets =
    w:
    concatLists (
      map (x: [
        (x / 65536)
        (bitAnd x 65535)
      ]) w
    );

  # RFC 5952: compress longest run (>=2) of zero groups, first on ties.
  formatV6 =
    w:
    let
      h = wordsToHextets w;
      scan =
        foldl'
          (
            st: i:
            let
              z = elemAt h i == 0;
              run = if z then st.run + 1 else 0;
              start = if z && st.run == 0 then i else st.start;
              better = z && run > st.len;
            in
            {
              inherit run start;
              bestStart = if better then start else st.bestStart;
              len = if better then run else st.len;
            }
          )
          {
            run = 0;
            start = 0;
            bestStart = 0;
            len = 0;
          }
          (genList (i: i) 8);
      str = xs: concatStringsSep ":" (map hex xs);
    in
    if scan.len < 2 then
      str h
    else
      str (genList (i: elemAt h i) scan.bestStart)
      + "::"
      + str (genList (i: elemAt h (scan.bestStart + scan.len + i)) (8 - scan.bestStart - scan.len));

  isV4Str = s: builtins.match ".*:.*" s == null;
  v4mask = [
    0
    0
    0
    full
  ];
  off = v4: if v4 then 96 else 0;
  maxLen = v4: if v4 then 32 else 128;
  # IPv4 values carry a tag. IPv6 values are plain word lists.
  wrap =
    v4: w:
    if v4 then
      {
        v4 = true;
        addr = w;
      }
    else
      w;
  unwrap = x: if isList x then x else x.addr;
  isV4 =
    x:
    if builtins.isString x then
      isV4Str x
    else if isList x then
      false
    else
      x.v4 or false;

  parseV4 =
    s:
    let
      m = builtins.match "(0|[1-9][0-9]{0,2})\\.(0|[1-9][0-9]{0,2})\\.(0|[1-9][0-9]{0,2})\\.(0|[1-9][0-9]{0,2})" s;
    in
    if m == null then
      throw "ipv4: bad address '${s}'"
    else
      let
        o = map builtins.fromJSON m;
      in
      if builtins.any (x: x > 255) o then
        throw "ipv4: octet out of range in '${s}'"
      else
        [
          0
          0
          0
          (foldl' (a: x: a * 256 + x) 0 o)
        ];

  parseAddr = s: if isV4Str s then wrap true (parseV4 s) else parseAddr6 s;
  addrWords = s: unwrap (parseAddr s);

  formatV4 =
    w:
    let
      x = elemAt w 3;
    in
    concatStringsSep "." (
      map toString [
        (x / 16777216)
        (bitAnd (x / 65536) 255)
        (bitAnd (x / 256) 255)
        (bitAnd x 255)
      ]
    );
  formatAddr =
    x:
    if isList x then
      formatV6 x
    else if x.v4 then
      formatV4 x.addr
    else
      formatV6 x.addr;

  networkWords = addr: p: zipWords bitAnd addr (maskWords p);

  mkCidr = v4: addr: prefix: { inherit v4 addr prefix; };
  makeI =
    v4: p: w:
    mkCidr v4 (networkWords w p) p;

  parseWith =
    keep: s:
    let
      m = builtins.match "([^/]*)(/([0-9]+))?" s;
    in
    if m == null then
      throw "bad cidr '${s}'"
    else
      let
        v4 = isV4Str (head m);
        ext = if elemAt m 2 == null then maxLen v4 else builtins.fromJSON (elemAt m 2);
        p = ext + off v4;
        w = addrWords (head m);
      in
      if ext > maxLen v4 then
        throw "bad prefix length in '${s}'"
      else
        mkCidr v4 (if keep then w else networkWords w p) p;
  parse = parseWith false;
  # keeps host bits (for interface addresses)
  parseHost = parseWith true;

  format = c: formatAddr (wrap c.v4 c.addr) + "/" + toString (c.prefix - off c.v4);

  contains =
    outer: inner:
    outer.v4 == inner.v4
    && outer.prefix <= inner.prefix
    && networkWords inner.addr outer.prefix == outer.addr;

  overlaps = a: b: contains a b || contains b a;

  containsAddr = c: a: isV4 a == c.v4 && networkWords (toWords a) c.prefix == c.addr;

  get = w: i: if i < 0 || i > 3 then 0 else elemAt w i;

  # 128-bit shifts. Every intermediate stays below 2^32, so nothing overflows.
  shl =
    w: k:
    let
      q = k / 32;
      r = k - q * 32;
    in
    genList (
      i: bitOr (bitAnd (get w (i + q)) (pow2 (32 - r) - 1) * pow2 r) (get w (i + q + 1) / pow2 (32 - r))
    ) 4;
  shr =
    w: k:
    let
      q = k / 32;
      r = k - q * 32;
    in
    genList (
      i: bitOr (get w (i - q) / pow2 r) (bitAnd (get w (i - q - 1)) (pow2 r - 1) * pow2 (32 - r))
    ) 4;

  addWords =
    a: b:
    (foldl'
      (
        acc: i:
        let
          t = elemAt a i + elemAt b i + acc.carry;
        in
        {
          carry = if t > full then 1 else 0;
          out = [ (bitAnd t full) ] ++ acc.out;
        }
      )
      {
        carry = 0;
        out = [ ];
      }
      [
        3
        2
        1
        0
      ]
    ).out;
  negWords =
    w:
    addWords (map (x: bitXor x full) w) [
      0
      0
      0
      1
    ];
  subWords = a: b: addWords a (negWords b);

  # sign-extended 64-bit int -> 128-bit
  fromInt =
    n:
    let
      lo = bitAnd n full;
      ext = if n < 0 then full else 0;
    in
    [
      ext
      ext
      (bitAnd ((n - lo) / 4294967296) full)
      lo
    ];
  toInt =
    w:
    let
      w0 = get w 0;
      w1 = get w 1;
      w2 = get w 2;
      w3 = get w 3;
    in
    if w0 == 0 && w1 == 0 && w2 < 2147483648 then
      w2 * 4294967296 + w3
    else if w0 == full && w1 == full && w2 >= 2147483648 then
      (w2 - 4294967296) * 4294967296 + w3
    else
      throw "difference does not fit in a 64-bit integer";

  # int | "addr" | tagged/plain address -> words
  toWords =
    x:
    if builtins.isInt x then
      fromInt x
    else if builtins.isString x then
      addrWords x
    else
      unwrap x;
  toCidr = x: if builtins.isString x then parse x else x;
  toHostCidr = x: if builtins.isString x then parseHost x else x;

  hostBits = c: 128 - c.prefix;
  # 2^k for k up to 62
  bitLeft = k: if k <= 32 then pow2 k else pow2 (k - 32) * 4294967296;
  maxInt = 9223372036854775807;
  capacity =
    c:
    let
      k = hostBits (toCidr c);
    in
    if k > 62 then maxInt else bitLeft k;

  # Unchecked: the index is masked to the host bits, so -1 is the last address.
  hostUnchecked =
    n: c: zipWords bitOr (zipWords bitAnd (toWords n) (elemAt invMaskTable c.prefix)) c.addr;

  host =
    n: c0:
    let
      c = toCidr c0;
      cap = capacity c;
      result = wrap c.v4 (hostUnchecked n c);
    in
    if builtins.isInt n && !(n >= -cap && n < cap) then
      throw "host ${toString n} lies outside of ${format c}"
    else if !builtins.isInt n && !containsAddr c result then
      throw "host lies outside of ${format c}"
    else
      result;

  hostCidr =
    n: c0:
    let
      c = toCidr c0;
    in
    c // { addr = unwrap (host n c); };

  make =
    len: ip:
    let
      v4 = isV4 ip;
    in
    makeI v4 (clamp 0 (maxLen v4) len + off v4) (toWords ip);

  canonicalize =
    x:
    let
      c = toHostCidr x;
    in
    c // { addr = networkWords c.addr c.prefix; };

  # shift a network by n networks of its own size (wraps at the address width)
  cidrAdd =
    delta: c0:
    let
      c = toCidr c0;
      k = hostBits c;
      r = shl (addWords (toWords delta) (shr c.addr k)) k;
    in
    c // { addr = if c.v4 then zipWords bitAnd r v4mask else r; };

  # n-th subnet that is `len` bits longer than c
  subnet =
    len: n: c0:
    let
      c = toCidr c0;
      p = c.prefix + len;
    in
    if len < 0 || p > 128 then
      throw "bad subnet length ${toString len}"
    else if builtins.isInt n && len < 63 && !(n >= -(bitLeft len) && n < bitLeft len) then
      throw "subnet ${toString n} lies outside of ${format c}"
    else
      c
      // {
        addr = hostUnchecked (shl (toWords n) (128 - p)) c;
        prefix = p;
      };

  child =
    sub: c:
    let
      s = toCidr sub;
      o = toCidr c;
    in
    s.v4 == o.v4 && s.prefix > o.prefix && networkWords s.addr o.prefix == o.addr;

  fit = v4: r: if v4 then zipWords bitAnd r v4mask else r;
  ipAdd =
    delta: ip:
    let
      v4 = isV4 ip;
    in
    wrap v4 (fit v4 (addWords (toWords delta) (toWords ip)));
  ipSubtract =
    delta: ip:
    let
      v4 = isV4 ip;
    in
    wrap v4 (fit v4 (subWords (toWords ip) (toWords delta)));
  ipDiff = a: b: toInt (subWords (toWords a) (toWords b));

  clz32 =
    w:
    let
      go =
        lo: hi: # smallest k with 2^k > w
        if lo == hi then
          lo
        else
          let
            mid = (lo + hi) / 2;
          in
          if pow2 mid > w then go lo mid else go (mid + 1) hi;
    in
    32 - go 0 32;
  clz =
    w:
    if get w 0 != 0 then
      clz32 (get w 0)
    else if get w 1 != 0 then
      32 + clz32 (get w 1)
    else if get w 2 != 0 then
      64 + clz32 (get w 2)
    else if get w 3 != 0 then
      96 + clz32 (get w 3)
    else
      128;

  # Smallest network containing every given cidr/address (host bits count as
  # addresses). A bare address is a host route. Returns null for the empty list.
  mergeCidrs =
    cs0:
    let
      cs = map toHostCidr cs0;
      h = head cs;
      diffBits = foldl' (acc: c: zipWords bitOr acc (zipWords bitXor c.addr h.addr)) [ 0 0 0 0 ] cs;
      minPrefix = foldl' (m: c: if c.prefix < m then c.prefix else m) 128 cs;
      z = clz diffBits;
    in
    if cs == [ ] then
      null
    else if builtins.any (c: c.v4 != h.v4) cs then
      throw "merge: cannot mix IPv4 and IPv6"
    else
      makeI h.v4 (if z < minPrefix then z else minPrefix) h.addr;
  onlyFamily =
    v4: name: cs:
    if builtins.all (c: isV4 c == v4) cs then mergeCidrs cs else throw "${name}: wrong address family";

  # Stable hash-based address assignment with linear probing.
  # The order of `hosts` does not matter.
  # `reserved` holds offsets or addresses.
  assignIps =
    net0: reserved: hosts:
    let
      net = toCidr net0;
      size = hostBits net;
      cap = capacity net;
      baseAddr = host 0 net;
      init = builtins.attrNames (
        builtins.listToAttrs (
          map
            (v: {
              name = toString v;
              value = null;
            })
            (
              [
                0
                (cap - 1)
              ]
              ++ map (x: if builtins.isInt x then x else ipDiff x baseAddr) reserved
            )
        )
      );
      nHosts = length hosts;
      nInit = length init;
      sortedHosts =
        (
          if (nInit + nHosts) > 0.3 * cap then
            builtins.trace "assignIps: hash stability may be degraded since utilization is >30%"
          else
            x: x
        )
          (sort builtins.lessThan hosts);
      hash8 =
        str:
        foldl' (a: i: a * 256 + byteTable.${substring (2 * i) 2 str}) 0 [
          0
          1
          2
          3
        ];
      hashElem =
        x:
        let
          d = builtins.hashString "sha256" x;
          m = cap - 1;
        in
        bitAnd (hash8 d) (m / 4294967296) * 4294967296 + bitAnd (hash8 (substring 8 8 d)) (bitAnd m full);
      probe = used: v: if used ? ${toString v} then probe used (bitAnd (cap - 1) (v + 1)) else v;
      step =
        st: x:
        let
          v = probe st.used (hashElem x);
        in
        {
          assigned = st.assigned // {
            ${x} = formatAddr (wrap net.v4 (hostUnchecked v net));
          };
          used = st.used // {
            ${toString v} = true;
          };
        };
    in
    if size < 2 || size > 62 then
      throw "assignIps: host bits ${toString size} not in [2, 62]"
    else if nHosts > cap - nInit then
      throw "assignIps: too many hosts (${toString nHosts}) for capacity ${toString cap} with ${toString nInit} reserved"
    else
      (foldl' step {
        assigned = { };
        used = builtins.listToAttrs (
          map (v: {
            name = v;
            value = true;
          }) init
        );
      } sortedHosts).assigned;

  parent =
    c:
    c
    // {
      addr = networkWords c.addr (c.prefix - 1);
      prefix = c.prefix - 1;
    };
  sibling =
    a: b:
    a.v4 == b.v4
    && a.prefix == b.prefix
    && a.prefix > off a.v4
    && a.addr != b.addr
    && parent a == parent b;

  # Sort, drop covered networks and merge siblings into supernets.
  # The stack is a linked list of cells, so push and pop are O(1).
  # A plain `[ c ] ++ stack` would copy the stack each time (quadratic).
  aggregate =
    cs:
    let
      sorted = map (x: x.c) (
        sort (a: b: a.k < b.k) (
          map (c: {
            k = [ (if c.v4 then 0 else 1) ] ++ c.addr ++ [ c.prefix ];
            inherit c;
          }) cs
        )
      );
      push =
        stack: c:
        if stack == null then
          {
            n = 1;
            inherit c;
            rest = null;
          }
        else if contains stack.c c then
          stack
        else if sibling stack.c c then
          push stack.rest (parent stack.c)
        else
          {
            n = stack.n + 1;
            inherit c;
            rest = stack;
          };
      top = foldl' push null sorted;
      cells =
        if top == null then
          [ ]
        else
          builtins.genericClosure {
            startSet = [
              {
                key = top.n;
                cell = top;
              }
            ];
            operator =
              e:
              if e.cell.rest == null then
                [ ]
              else
                [
                  {
                    key = e.cell.rest.n;
                    cell = e.cell.rest;
                  }
                ];
          };
      len = length cells;
    in
    genList (i: (elemAt cells (len - 1 - i)).cell.c) len;
in
{
  inherit
    parse
    parseHost
    parseAddr
    formatAddr
    format
    contains
    overlaps
    containsAddr
    aggregate
    ;
  netmask =
    c:
    let
      x = toCidr c;
      m = maskWords x.prefix;
    in
    formatAddr (wrap x.v4 (fit x.v4 m));
  inherit
    host
    hostCidr
    make
    canonicalize
    child
    capacity
    subnet
    assignIps
    cidrAdd
    ipAdd
    ipSubtract
    ipDiff
    ;
  merge = cs: {
    cidrv4 = mergeCidrs (filter isV4 cs);
    cidrv6 = mergeCidrs (filter (x: !isV4 x) cs);
  };
  mergev4 = onlyFamily true "mergev4";
  mergev6 = onlyFamily false "mergev6";
  length =
    c:
    let
      h = toHostCidr c;
    in
    h.prefix - off h.v4;
  ip =
    c:
    let
      h = toHostCidr c;
    in
    wrap h.v4 h.addr;
  isv4 = isV4;
  isv6 = x: !isV4 x;
  # number of host bits
  size = c: hostBits (toCidr c);
  parseAggregate = l: map format (aggregate (map parse l));
  mac = import ./lib/mac.nix;
}
