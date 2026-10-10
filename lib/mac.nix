# MAC address arithmetic. A MAC is a 48-bit integer; arithmetic wraps mod 2^48.
let
  inherit (builtins)
    bitAnd
    genList
    substring
    match
    sort
    hashString
    foldl'
    throw
    ;

  mask48 = 281474976710655; # 2^48 - 1
  digits = "0123456789abcdef";
  nibbles = builtins.listToAttrs (
    genList (i: {
      name = substring i 1 digits;
      value = i;
    }) 16
  );
  lower = builtins.replaceStrings [ "A" "B" "C" "D" "E" "F" ] [ "a" "b" "c" "d" "e" "f" ];
  octetVal = s: nibbles.${substring 0 1 (lower s)} * 16 + nibbles.${substring 1 1 (lower s)};

  parse =
    s:
    let
      m = match "([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2})" s;
    in
    if m == null then throw "mac: bad address '${s}'" else foldl' (acc: o: acc * 256 + octetVal o) 0 m;

  pow2 = k: if k == 0 then 1 else 2 * pow2 (k - 1);

  octet = n: substring (n / 16) 1 digits + substring (bitAnd n 15) 1 digits;
  format =
    n: builtins.concatStringsSep ":" (genList (i: octet (bitAnd (n / pow2 (8 * (5 - i))) 255)) 6);

  toInt = x: if builtins.isInt x then x else parse x;

  add = delta: mac: bitAnd (toInt delta + toInt mac) mask48;
  subtract = delta: mac: bitAnd (toInt mac - toInt delta) mask48;
  diff = a: b: bitAnd (toInt a - toInt b) mask48;

  # force the locally administered range by replacing the second nibble with 2
  addPrivate =
    base: offset:
    let
      s = format (add offset base);
    in
    substring 0 1 s + "2" + substring 2 (-1) s;

  # Stable hash-based assignment with linear probing (see assignIps).
  assignMacs =
    base0: size: reserved: hosts:
    let
      base = toInt base0;
      cap = pow2 size;
      init = builtins.listToAttrs (
        map (x: {
          name = toString (if builtins.isInt x then x else diff x base);
          value = true;
        }) reserved
      );
      nInit = builtins.length (builtins.attrNames init);
      nHosts = builtins.length hosts;
      sortedHosts = sort builtins.lessThan hosts;
      hash8 =
        str:
        foldl' (a: i: a * 256 + octetVal (substring (2 * i) 2 str)) 0 [
          0
          1
          2
          3
        ];
      hashElem =
        x:
        let
          d = hashString "sha256" x;
          m = cap - 1;
        in
        bitAnd (hash8 d) (m / 4294967296) * 4294967296
        + bitAnd (hash8 (substring 8 8 d)) (bitAnd m 4294967295);
      probe = used: v: if used ? ${toString v} then probe used (bitAnd (cap - 1) (v + 1)) else v;
      step =
        st: x:
        let
          v = probe st.used (hashElem x);
        in
        {
          assigned = st.assigned // {
            ${x} = format (add v base);
          };
          used = st.used // {
            ${toString v} = true;
          };
        };
    in
    if size < 2 || size > 62 then
      throw "assignMacs: size=${toString size} is not in [2, 62]"
    else if bitAnd (cap - 1) base != 0 then
      throw "assignMacs: the ${toString size} least significant bits of the base must be 0"
    else if nHosts > cap - nInit then
      throw "assignMacs: too many hosts"
    else
      (foldl' step {
        assigned = { };
        used = init;
      } sortedHosts).assigned;
in
{
  inherit
    parse
    format
    add
    subtract
    diff
    addPrivate
    assignMacs
    ;
}
