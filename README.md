# nix-netcalc

IPv4, IPv6 and MAC address arithmetic in pure Nix.

The library depends on `builtins` only. Addresses are stored as four 32-bit
words, so all arithmetic stays within Nix's signed 64-bit integers. It is
several times faster than the `netu.nix` library it is modelled on.

## Usage

With flakes:

```nix
{
  inputs.nix-netcalc.url = "github:Mic92/nix-netcalc";

  outputs = { nix-netcalc, ... }: {
    subnet = nix-netcalc.lib.format (nix-netcalc.lib.subnet 4 15 "10.1.2.0/24");
  };
}
```

With [npins](https://github.com/andir/npins):

```console
$ npins add github Mic92 nix-netcalc -b main
```

```nix
let net = import (import ./npins).nix-netcalc; in
net.format (net.subnet 4 15 "10.1.2.0/24")
```

With `fetchTarball`:

```nix
let
  net = import (builtins.fetchTarball {
    url = "https://github.com/Mic92/nix-netcalc/archive/<commit>.tar.gz";
    sha256 = "<hash>";
  });
in
net.format (net.subnet 4 15 "10.1.2.0/24")
```

All three evaluate to `"10.1.2.240/28"`.

## Conventions

A *cidr* argument is a string such as `"10.0.0.0/8"` or a record returned by
`parse`. An *address* is a string or a value returned by `parseAddr`. A bare
address is a host route. Output follows RFC 5952.

Functions that return a cidr or an address return a value, not a string. Pass
it to `format` or `formatAddr`. Invalid input is reported with `throw`.

IPv4 and IPv6 are distinct families. Comparing across families returns `false`.

## Parsing

`parse c` parses a network and clears its host bits. `parseHost c` keeps them.
`parseAddr a` parses an address, including embedded IPv4 such as
`::ffff:1.2.3.4`.

```nix
net.format (net.parse "192.168.1.77/24")       # "192.168.1.0/24"
net.format (net.parseHost "192.168.1.77/24")   # "192.168.1.77/24"
net.formatAddr (net.parseAddr "2001:0DB8::1")  # "2001:db8::1"
```

## Inspecting

| Function | Returns |
|---|---|
| `length c` | The prefix length. |
| `ip c` | The address, host bits included. |
| `netmask c` | The netmask as a string. |
| `size c` | The number of host bits. |
| `capacity c` | The number of addresses, saturating at `2^63 - 1`. |
| `isv4 x`, `isv6 x` | Whether `x` is an IPv4 or IPv6 address or cidr. |

```nix
net.netmask "172.16.0.0/12"        # "255.240.0.0"
net.capacity "172.16.0.0/12"       # 1048576
```

## Relations

`contains a b` returns whether `b` lies within `a`, and `containsAddr c a` does
the same for an address. `child sub c` is the strict form: it is `false` when
both have the same prefix length. `overlaps a b` returns whether either
contains the other. `contains`, `containsAddr` and `overlaps` take records;
`child` takes either.

```nix
net.child "10.10.10.0/24" "10.0.0.0/8"                              # true
net.containsAddr (net.parse "fe80::/10") (net.parseAddr "febf::1")  # true
```

## Hosts and subnets

`host n c` returns the `n`-th address of `c`. Negative `n` counts from the end.

`hostCidr n c` is `host` that keeps the prefix length. `make len a` returns the
network of length `len` containing `a`. `canonicalize c` clears the host bits
of a cidr that has them.

`subnet len n c` returns the `n`-th subnet of `c` that is `len` bits longer.
`cidrAdd n c` moves `c` by `n` networks of its own size, wrapping at the end
of the address space.

```nix
net.formatAddr (net.host (-1) "192.168.1.0/24")        # "192.168.1.255"
net.format (net.subnet 4 15 "10.1.2.0/24")             # "10.1.2.240/28"
net.format (net.cidrAdd 2 "127.0.0.0/8")               # "129.0.0.0/8"
net.format (net.make 40 "dead:cafe:beef::feed:f00d")   # "dead:cafe:be00::/40"
```

`host` and `subnet` throw if `n` is out of range.

## Address arithmetic

`ipAdd n a` and `ipSubtract n a` add to or subtract from an address, wrapping
at the family's width. `ipDiff a b` returns `a - b` as an integer.

```nix
net.formatAddr (net.ipAdd 100 "10.0.0.1")        # "10.0.0.101"
net.ipDiff "10.0.0.1" "10.0.0.101"               # -100
```

`ipDiff` throws if the result does not fit in 64 bits.

## Merging

`mergev4 l` and `mergev6 l` return the smallest network containing every
element of `l`, or `null` if `l` is empty. `merge l` partitions a mixed list
and returns `{ cidrv4; cidrv6; }`.

`aggregate l` removes networks covered by another and merges adjacent
siblings. It accepts both families and runs in `O(n log n)`.
`parseAggregate` does the same on strings.

```nix
net.format (net.mergev6 [ "fd00:dead:cafe::/64" "fd00:fd12:3456:7890::/56" ])
# "fd00:c000::/18"

net.parseAggregate [ "10.0.0.0/25" "10.0.0.128/25" "10.0.0.5/32" ]
# [ "10.0.0.0/24" ]
```

## Assigning addresses

`assignIps c reserved names` maps every name to an address in `c` by hashing
it with SHA-256 and probing linearly on collision. The result does not depend
on the order of `names`, and adding a name does not move existing ones. The
first and last address and everything in `reserved` are skipped.

```nix
net.assignIps "192.168.100.0/24" [ ] [ "a" "b" "c" ]
# { a = "192.168.100.202"; b = "192.168.100.74"; c = "192.168.100.226"; }
```

`assignIps` throws unless `c` has 2 to 62 host bits, or if there are more names
than free addresses. It traces a warning above 30% utilisation, where
stability degrades.

## MAC addresses

`net.mac` mirrors the address functions on 48-bit integers. `mac.parse` and
`mac.format` convert between strings and integers. `mac.add`, `mac.subtract`
and `mac.diff` return integers and wrap modulo 2^48. `mac.addPrivate base n`
returns `base + n` with the second nibble replaced by `2`, which yields a locally administered address. `mac.assignMacs base
bits reserved names` is `assignIps` over `[base, base + 2^bits)`.

```nix
net.mac.format (net.mac.add 100 "fe:ed:fa:ce:f0:0d")   # "fe:ed:fa:ce:f0:71"
net.mac.addPrivate "00:11:22:33:44:55" 1               # "02:11:22:33:44:56"
```

## Compatibility

Every function of duairc's `netu.nix`, as used by oddlama's
[nixos-extra-modules](https://github.com/oddlama/nixos-extra-modules), has an
equivalent here, except the NixOS option types and arithmetic that mixes
address kinds. `contains` there is `containsAddr` here.

`overlaps`, `aggregate` and the cidr form of `contains` are additions.

## Development

```console
$ nix-instantiate --eval --strict lib/tests.nix
$ nix-instantiate --eval --strict lib/v4-tests.nix
$ nix-instantiate --eval --strict lib/mac-tests.nix
$ nix-instantiate --eval --strict lib/parity.nix
```

Each prints `true` on success. `lib/parity.nix` and `lib/v4-tests.nix` fetch
`netu.nix` at a pinned commit and need network access on the first run. That
version's `ip.add`, `ip.subtract`, `ip.diff` and `cidr.add` are broken, so the
tests check those against values computed with Python's `ipaddress`.

`lib/bench.nix` and `lib/bench-ref.nix` benchmark this library and compare it
with `netu.nix`.

## License

MIT
