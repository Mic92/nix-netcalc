# nix-netcalc

IPv4, IPv6 and MAC address calculator in pure Nix. It uses builtins only, so
there is no `nixpkgs.lib` dependency.

```nix
let
  net = import ./default.nix;
in
net.format (net.subnet 4 15 "10.1.2.0/24")   # => "10.1.2.240/28"
```

## Concepts

Nix has only signed 64-bit integers, so an address is stored as four 32-bit
words. Every function accepts the type it needs in the most convenient form:

| Argument | Accepted forms |
|---|---|
| **cidr** | string (`"10.0.0.0/8"`) or a record returned by `parse` and friends |
| **address** | string (`"::1"`), or a value returned by `parseAddr`, `host`, `ip`, `ipAdd`, … |
| **offset / delta** | integer, or an address (added as a number) |

- A bare address such as `"10.1.2.3"` is a host route (`/32`, or `/128` for IPv6).
- Functions that return **cidrs** return records. Turn them into strings with `format`.
- Functions that return **addresses** return values you turn into strings with
  `formatAddr`.
- Functions that return **numbers or booleans** return them directly.
- Errors are `throw`s: bad input, out-of-range `host`, mixed families, and so on.
- IPv4 and IPv6 never mix. Cross-family `contains`, `child` and `overlaps`
  return `false`. `merge`, `mergev4` and `mergev6` throw for the wrong family.
- Output is RFC 5952: `2001:db8::1`, lowercase, longest zero run compressed.

## Parsing and formatting

### `parse :: string -> cidr`
Parses a network. Host bits are cleared.

```nix
net.format (net.parse "2001:db8::1/32")    # "2001:db8::/32"
net.format (net.parse "192.168.1.77/24")   # "192.168.1.0/24"
net.format (net.parse "10.1.2.3")          # "10.1.2.3/32"
```

### `parseHost :: string -> cidr`
Same as `parse` but keeps host bits. Use it for interface addresses.

```nix
net.format (net.parseHost "192.168.1.77/24")   # "192.168.1.77/24"
```

### `parseAddr :: string -> address`

```nix
net.formatAddr (net.parseAddr "2001:0DB8:0:0:0:0:0:1")   # "2001:db8::1"
net.formatAddr (net.parseAddr "::ffff:1.2.3.4")          # "::ffff:102:304" (embedded IPv4)
```

### `format :: cidr -> string`, `formatAddr :: address -> string`

## Inspecting a network

All of these take a cidr string or record.

| Function | Result | Example |
|---|---|---|
| `netmask c` | string | `netmask "172.16.0.0/12"` → `"255.240.0.0"`; `netmask "2001:db8::/37"` → `"ffff:ffff:f800::"` |
| `length c` | int | `length "10.1.2.3/20"` → `20` |
| `ip c` | address | `formatAddr (ip "192.168.1.100/24")` → `"192.168.1.100"` |
| `size c` | int, host bits | `size "10.0.0.0/8"` → `24` |
| `capacity c` | int, 2^host bits, saturates at `9223372036854775807` | `capacity "172.16.0.0/12"` → `1048576` |
| `isv4 x` / `isv6 x` | bool | `isv4 "10.0.0.1/8"` → `true` |

The first and last address of a network are `host 0 c` and `host (-1) c`.
`length` and `ip` keep host bits, so `ip "192.168.1.100/24"` is the original
address, not the network address.

## Relations

```nix
net.contains   (net.parse "10.0.0.0/8") (net.parse "10.1.0.0/16")   # true (also true for equal networks)
net.child      "10.10.10.0/24" "10.0.0.0/8"                         # true
net.child      "10.0.0.0/8"    "10.0.0.0/8"                         # false: child is strict
net.overlaps   (net.parse "10.0.0.0/8") (net.parse "10.1.0.0/16")   # true
net.containsAddr (net.parse "fe80::/10") (net.parseAddr "febf::1")  # true
```

`contains`, `overlaps` and `containsAddr` take **records** (use `parse`).
`child` takes strings or records.

## Building cidrs

```nix
net.format (net.make 40 "dead:cafe:beef::feed:face:f00d")   # "dead:cafe:be00::/40"
net.format (net.make 24 "192.168.0.150")                    # "192.168.0.0/24"
net.format (net.make 99 "192.168.0.150")                    # "192.168.0.150/32" (length is clamped)
net.format (net.canonicalize "192.168.1.100/24")            # "192.168.1.0/24"
```

## Hosts

### `host :: int|address -> cidr -> address`
The n-th address of a network. Negative numbers count from the end. Out-of-range
indices throw.

```nix
net.formatAddr (net.host 5 "192.168.1.0/24")               # "192.168.1.5"
net.formatAddr (net.host (-1) "192.168.1.0/24")            # "192.168.1.255"
net.formatAddr (net.host 10000 "dead:cafe:beef::/64")      # "dead:cafe:beef::2710"
net.host 256 "192.168.1.0/24"                              # error: lies outside
```

### `hostCidr :: int|address -> cidr -> cidr`
Like `host`, but keeps the prefix length.

```nix
net.format (net.hostCidr 2 "192.168.1.0/24")   # "192.168.1.2/24"
```

## Subnets

### `subnet :: int -> int|address -> cidr -> cidr`
`subnet len n c` returns the n-th subnet that is `len` bits longer than `c`.

```nix
net.format (net.subnet 4 15 "10.1.2.0/24")                  # "10.1.2.240/28"
net.format (net.subnet 16 162 "fd00:fd12:3456:7890::/56")   # "fd00:fd12:3456:7800:a200::/72"
```

To list every subnet, map over the index:

```nix
map (i: net.format (net.subnet 2 i "192.168.0.0/24")) (builtins.genList (i: i) 4)
# [ "192.168.0.0/26" "192.168.0.64/26" "192.168.0.128/26" "192.168.0.192/26" ]
```

### `cidrAdd :: int|address -> cidr -> cidr`
Shifts a network by n networks of its own size. It wraps at the address width.

```nix
net.format (net.cidrAdd 2 "127.0.0.0/8")      # "129.0.0.0/8"
net.format (net.cidrAdd (-2) "127.0.0.0/8")   # "125.0.0.0/8"
```

## Address arithmetic

```nix
net.formatAddr (net.ipAdd 100 "10.0.0.1")                   # "10.0.0.101"
net.formatAddr (net.ipAdd 100 "dead:cafe:beef::")           # "dead:cafe:beef::64"
net.formatAddr (net.ipSubtract 1 "10.0.0.0")                # "9.255.255.255"
net.formatAddr (net.ipAdd 1 "255.255.255.255")              # "0.0.0.0" (wraps)
net.ipDiff "10.0.0.101" "10.0.0.1"                          # 100
net.ipDiff "10.0.0.1" "10.0.0.101"                          # -100
```

`ipDiff` throws if the difference does not fit a 64-bit integer.

## Merging and aggregating

### `mergev4`, `mergev6 :: [cidr|address] -> cidr|null`
The smallest network that contains everything in the list. Bare addresses count
as host routes. Returns `null` for the empty list.

```nix
net.format (net.mergev4 [ "192.168.1.1/24" "192.168.6.1/32" ])                   # "192.168.0.0/21"
net.format (net.mergev6 [ "fd00:dead:cafe::/64" "fd00:fd12:3456:7890::/56" ])    # "fd00:c000::/18"
```

### `merge :: [cidr|address] -> { cidrv4; cidrv6; }`
Splits a mixed list by family and merges each part.

```nix
let m = net.merge [ "10.0.0.1" "10.0.0.2" "fd00::1" "fd00::2" ]; in
[ (net.format m.cidrv4) (net.format m.cidrv6) ]   # [ "10.0.0.0/30" "fd00::/126" ]
```

### `aggregate :: [cidr(record)] -> [cidr]`, `parseAggregate :: [string] -> [string]`
Route aggregation: sorts, drops networks covered by another and merges sibling
networks into their parent. IPv4 and IPv6 may be mixed. IPv4 sorts first.

```nix
net.parseAggregate [ "10.0.0.0/25" "10.0.0.128/25" "10.0.1.0/24" "192.168.0.0/24" "10.0.0.5/32" ]
# [ "10.0.0.0/23" "192.168.0.0/24" ]
```

It scales roughly as n log n: about 4 s for 100k networks, including parsing.

## Stable address assignment

### `assignIps :: cidr -> [int|address] -> [string] -> { name = "address"; }`
Gives each name a semi-stable address by hashing it with sha256 and probing
linearly on collisions.

- The result does not depend on the order of the list.
- Adding a name does not change the addresses of existing names.
- The first address, the last address and anything in the reserved list are never
  assigned. Reserved entries are offsets or addresses.
- It needs 2 to 62 host bits. It throws if there are more hosts than free
  addresses and traces a warning above 30% utilisation, because stability
  degrades.

```nix
net.assignIps "192.168.100.0/24" [ ] [ "a" "b" "c" ]
# { a = "192.168.100.202"; b = "192.168.100.74"; c = "192.168.100.226"; }

net.assignIps "192.168.100.0/24" [ 202 "192.168.100.74" ] [ "a" "b" "c" ]
# { a = "192.168.100.203"; b = "192.168.100.75"; c = "192.168.100.226"; }
```

## MAC addresses (`net.mac`)

A MAC is a 48-bit integer. Arithmetic wraps. `parse` accepts upper or lower case.

| Function | Example |
|---|---|
| `mac.parse s` → int | `mac.parse "00:00:00:00:01:00"` → `256` |
| `mac.format n` → string | `mac.format 256` → `"00:00:00:00:01:00"` |
| `mac.add delta mac` | `mac.format (mac.add 100 "fe:ed:fa:ce:f0:0d")` → `"fe:ed:fa:ce:f0:71"` |
| `mac.subtract delta mac` | `mac.format (mac.subtract 100 "fe:ed:fa:ce:f0:71")` → `"fe:ed:fa:ce:f0:0d"` |
| `mac.diff a b` → int | `mac.diff "fe:ed:fa:ce:f0:71" "fe:ed:fa:ce:f0:0d"` → `100` |
| `mac.addPrivate base offset` | `mac.addPrivate "00:11:22:33:44:55" 1` → `"02:11:22:33:44:56"` (forces a locally administered address) |

`delta` and `mac` accept an integer or a MAC string. `mac.add`, `mac.subtract`
and `mac.diff` all return integers, so pass the result of `add` or `subtract` to
`mac.format` to get a string. `addPrivate` returns a string directly.

### `mac.assignMacs :: mac -> int -> [int|mac] -> [string] -> { name = "mac"; }`
The same hash-and-probe scheme as `assignIps`, in the range
`[base, base + 2^size)`. The low `size` bits of `base` must be zero.

```nix
net.mac.assignMacs "11:22:33:00:00:00" 24 [ ] [ "a" "b" "c" ]
# { a = "11:22:33:1b:bd:ca"; b = "11:22:33:39:59:4a"; c = "11:22:33:50:7a:e2"; }
```

## Behaviour notes

- **Sorting:** `aggregate` orders by family, address and then prefix length.
- **Cross-family arithmetic:** `ipAdd`, `ipSubtract` and `ipDiff` take the family
  of the address argument. A delta given as an address is added as a number.

## Coverage of duairc's `netu.nix` / oddlama's `net.nix`

| Reference | Here |
|---|---|
| `net.ip.add` / `subtract` / `diff` | `ipAdd` / `ipSubtract` / `ipDiff` |
| `net.ip.isv4` / `isv6` | `isv4` / `isv6` |
| `net.cidr.add` | `cidrAdd` |
| `net.cidr.child` | `child` |
| `net.cidr.contains` | `containsAddr` |
| `net.cidr.capacity` | `capacity` |
| `net.cidr.host` | `host` |
| `net.cidr.hostCidr` | `hostCidr` |
| `net.cidr.ip` | `ip` |
| `net.cidr.length` | `length` |
| `net.cidr.make` | `make` |
| `net.cidr.canonicalize` | `canonicalize` |
| `net.cidr.netmask` | `netmask` |
| `net.cidr.size` | `size` |
| `net.cidr.subnet` | `subnet` |
| `net.cidr.mergev4` / `mergev6` / `merge` | `mergev4` / `mergev6` / `merge` |
| `net.cidr.assignIps` | `assignIps` |
| `net.mac.add` / `subtract` / `diff` | `mac.add` / `mac.subtract` / `mac.diff` |
| `net.mac.addPrivate` / `assignMacs` | `mac.addPrivate` / `mac.assignMacs` |
| parsers and builders | `parse`, `parseHost`, `parseAddr`, `format`, `formatAddr`, `mac.parse`, `mac.format` |

Not covered: the NixOS option types (`types.net`) and mixed-type arithmetic
such as adding a MAC to an IPv4 address.

Beyond the reference: `overlaps`, `contains` on cidrs, and `aggregate`.

## Tests

```sh
nix-instantiate --eval --strict tests.nix      # IPv6
nix-instantiate --eval --strict v4-tests.nix   # IPv4
nix-instantiate --eval --strict mac-tests.nix  # MAC
nix-instantiate --eval --strict parity.nix     # IPv6, against duairc's netu.nix
```

Each prints `true` on success and throws a descriptive error on failure.
`parity.nix` and `v4-tests.nix` compare against duairc's `netu.nix`, which they
fetch at a pinned commit of
[oddlama/nixos-extra-modules](https://github.com/oddlama/nixos-extra-modules)
(see `reference.nix`) and need network access on the first run.
In that version `ip.add`, `ip.subtract`, `ip.diff` and `cidr.add` are broken, so those functions are tested against values computed with Python's
`ipaddress` module.

## Benchmarking

```sh
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/s.json \
  nix-instantiate --eval --strict bench.nix --arg n 50000 --argstr op aggregate
```

`op` is one of `noop`, `parse`, `format`, `contains` or `aggregate`.

## License

MIT, see `LICENSE`.
