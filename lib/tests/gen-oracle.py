"""Generate oracle-data.json with expected values from Python's ipaddress.

oracle.nix compares the library against these values, so the expectations do
not depend on the library's own code.

Usage: python3 gen-oracle.py > oracle-data.json
"""

import ipaddress
import json
from typing import Any

type Network = ipaddress.IPv4Network | ipaddress.IPv6Network
type Address = ipaddress.IPv4Address | ipaddress.IPv6Address

MAX_INT = 2**63 - 1

NETS6 = [
    "2001:db8::/32",
    "fd00:fd12:3456:7890::/56",
    "::/0",
    "fe80::/10",
    "dead:cafe:beef::/48",
    "2001:db8:1:2::/64",
    "::1/128",
    "fd00::/120",
]
# 62, 63 and 64 host bits around the point where capacity saturates.
NETS_CAPACITY = ["::/66", "::/65", "::/64", "::/1", "::/0"]
NETS4 = [
    "10.0.0.0/8",
    "192.168.1.0/24",
    "172.16.0.0/12",
    "0.0.0.0/0",
    "1.2.3.4/32",
    "127.0.0.0/8",
    "10.1.2.0/24",
    "255.255.255.254/31",
]
HOST_INDICES = [0, 1, 2, 255, -1, -2, 65536]
ADDRS6 = [
    "2001:db8::1",
    "2001:db9::1",
    "fe80::1",
    "febf::1",
    "fec0::",
    "::1",
    "dead:cafe:beef::5",
]
ADDRS4 = ["10.1.2.3", "127.0.0.1", "192.168.1.200", "172.31.255.255", "172.32.0.0"]


def from_int(version: int, value: int) -> Address:
    cls = ipaddress.IPv4Address if version == 4 else ipaddress.IPv6Address
    return cls(value)


def network(text: str) -> Network:
    return ipaddress.ip_network(text, strict=False)


def make_network(version: int, value: int, prefix: int) -> Network:
    return ipaddress.ip_network((from_int(version, value), prefix), strict=False)


def addr_text(addr: Address) -> str:
    text = addr.compressed
    # Python 3.13 prints IPv4-mapped IPv6 addresses in dotted form, which the
    # library does not. Such inputs must not appear in the tables.
    assert addr.version == 4 or "." not in text, text
    return text


def host_bits(net: Network) -> int:
    return net.max_prefixlen - net.prefixlen


def host_mask(net: Network) -> int:
    return (1 << host_bits(net)) - 1


def capacity(net: Network) -> int:
    return min(1 << host_bits(net), MAX_INT)


def host(net_text: str, index: int) -> str | None:
    net = network(net_text)
    if not -capacity(net) <= index < capacity(net):
        return None
    value = int(net.network_address) | (index & host_mask(net))
    return addr_text(from_int(net.version, value))


def subnet(net_text: str, length: int, index: int) -> str:
    net = network(net_text)
    prefix = net.prefixlen + length
    shifted = index << (net.max_prefixlen - prefix)
    value = int(net.network_address) | (shifted & host_mask(net))
    return str(make_network(net.version, value, prefix))


def cidr_add(net_text: str, delta: int) -> str:
    net = network(net_text)
    size = 1 << host_bits(net)
    value = (int(net.network_address) + delta * size) % (1 << net.max_prefixlen)
    return str(make_network(net.version, value, net.prefixlen))


def ip_add(addr_text_in: str, delta: int) -> str:
    addr = ipaddress.ip_address(addr_text_in)
    value = (int(addr) + delta) % (1 << addr.max_prefixlen)
    return addr_text(from_int(addr.version, value))


def is_child(sub_text: str, net_text: str) -> bool:
    sub, net = network(sub_text), network(net_text)
    return (
        sub.version == net.version
        and sub.prefixlen > net.prefixlen
        and sub.subnet_of(net)  # type: ignore[arg-type]
    )


def merge(inputs: list[str]) -> str:
    """Longest prefix, at most the shortest input prefix, that contains the
    address of every input. Host bits of an input count as part of it."""
    addrs = [ipaddress.ip_address(i.split("/")[0]) for i in inputs]
    prefixes = [
        int(i.split("/")[1]) if "/" in i else a.max_prefixlen
        for i, a in zip(inputs, addrs, strict=True)
    ]
    first = addrs[0]
    for length in range(min(prefixes), -1, -1):
        net = make_network(first.version, int(first), length)
        if all(a in net for a in addrs):
            return str(net)
    raise AssertionError(inputs)


def tables() -> dict[str, list[list[Any]]]:
    nets = NETS6 + NETS4 + NETS_CAPACITY
    host_rows = [[n, i, host(n, i)] for n in nets for i in HOST_INDICES]
    accessor_rows = [
        [
            n,
            addr_text(network(n).netmask),
            network(n).prefixlen,
            host_bits(network(n)),
            capacity(network(n)),
        ]
        for n in nets
    ]
    canonical_rows = []
    for n in nets:
        net = network(n)
        offset = 5 if host_bits(net) > 3 else 0
        member = addr_text(from_int(net.version, int(net.network_address) + offset))
        text = f"{member}/{net.prefixlen}"
        canonical_rows.append([text, str(net)])

    subnet_args6 = [(4, 15), (16, 162), (8, 3), (1, 1), (0, 0), (24, 12345)]
    subnet_args4 = [(4, 15), (8, 3), (1, 1), (0, 0), (4, 2)]
    subnet_rows = [
        [n, length, i, subnet(n, length, i)]
        for n in ["2001:db8::/32", "fd00:fd12:3456:7890::/56", "dead:cafe::/40"]
        for length, i in subnet_args6
    ] + [
        [n, length, i, subnet(n, length, i)]
        for n in ["10.1.2.0/24", "172.16.0.0/12", "10.0.0.0/8"]
        for length, i in subnet_args4
    ]

    deltas = [0, 1, 2, -1, -2, 1000]
    add_nets6 = [
        "2001:db8::/32",
        "fd00:fd12:3456:7890::/56",
        "2001:db8:1:2::/64",
        "ff00::/8",
        "::/0",
    ]
    add_nets4 = [
        "127.0.0.0/8",
        "255.0.0.0/8",
        "10.1.2.0/24",
        "0.0.0.0/0",
        "192.168.0.0/16",
        "255.255.255.0/24",
        "128.0.0.0/1",
    ]
    # Deltas large enough to wrap around the whole address space.
    wrap_deltas = [2**24, 2**31, 2**32, -(2**32)]
    cidr_add_rows = [
        [n, d, cidr_add(n, d)]
        for n in add_nets6 + add_nets4
        for d in deltas + wrap_deltas
    ]

    contains_rows = [
        [n, a, ipaddress.ip_address(a) in network(n)]
        for n in nets
        for a in ADDRS6 + ADDRS4
    ]

    child_pairs = [
        ("2001:db8:1::/48", "2001:db8::/32"),
        ("2001:db8::/32", "2001:db8::/32"),
        ("2001:db9::/48", "2001:db8::/32"),
        ("10.10.10.0/24", "10.0.0.0/8"),
        ("127.0.0.0/8", "10.0.0.0/8"),
        ("10.0.0.0/8", "10.0.0.0/8"),
        ("10.0.0.0/8", "::/0"),
        ("::/64", "0.0.0.0/0"),
    ]
    child_rows = [[s, n, is_child(s, n)] for s, n in child_pairs]

    add_addrs6 = [
        "dead:cafe:beef::",
        "::ffff:ffff",
        "::ffff:ffff:ffff:ffff",
        "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
    ]
    add_addrs4 = ["10.0.0.1", "255.255.255.255", "0.0.0.0", "192.168.1.1"]
    add_rows = [
        [a, d, ip_add(a, d)]
        for a in add_addrs6 + add_addrs4
        for d in [0, 1, 100, -1, 4294967295, 4294967296]
    ]
    subtract_rows = [
        [a, d, ip_add(a, -d)]
        for a in add_addrs6 + add_addrs4
        for d in [0, 1, 100, 4294967296]
    ]

    diff_pairs = [
        ("dead:cafe:beef::2710", "dead:cafe:beef::"),
        ("dead:cafe:beef::", "dead:cafe:beef::2710"),
        ("::1:0:0:0", "::"),
        ("::", "::1"),
        ("10.0.0.101", "10.0.0.1"),
        ("10.0.0.1", "10.0.0.101"),
        ("255.255.255.255", "0.0.0.0"),
        ("0.0.0.0", "255.255.255.255"),
    ]
    diff_rows = []
    for a, b in diff_pairs:
        diff = int(ipaddress.ip_address(a)) - int(ipaddress.ip_address(b))
        assert -MAX_INT <= diff <= MAX_INT
        diff_rows.append([a, b, diff])

    merge_sets = [
        ["fd00:dead:cafe::/64", "fd00:fd12:3456:7890::/56"],
        ["2001:db8::1", "2001:db8::2"],
        ["2001:db8::1"],
        ["2001:db8:1::/48", "2001:db8:2::/48", "2001:db8:3::/48"],
        ["::1", "8000::1"],
        ["2001:db8:0:0:1::5/64", "2001:db8::/32"],
        ["192.168.1.1/24", "192.168.6.1/32"],
        ["10.0.0.1", "10.0.0.2"],
        ["10.0.0.1"],
        ["10.0.0.0/8", "11.0.0.0/8"],
        ["0.0.0.1", "255.255.255.254"],
    ]
    merge_rows = [[m, merge(m)] for m in merge_sets]

    return {
        "host": host_rows,
        "accessors": accessor_rows,
        "canonicalize": canonical_rows,
        "subnet": subnet_rows,
        "cidrAdd": cidr_add_rows,
        "contains": contains_rows,
        "child": child_rows,
        "ipAdd": add_rows,
        "ipSubtract": subtract_rows,
        "ipDiff": diff_rows,
        "merge": merge_rows,
    }


def main() -> None:
    # One row per line keeps diffs of the checked-in data readable.
    print("{")
    items = tables().items()
    for n, (name, rows) in enumerate(items, start=1):
        print(f"  {json.dumps(name)}: [")
        for m, row in enumerate(rows, start=1):
            print(f"    {json.dumps(row)}{',' if m < len(rows) else ''}")
        print(f"  ]{',' if n < len(items) else ''}")
    print("}")


if __name__ == "__main__":
    main()
