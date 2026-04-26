#!/usr/bin/env python3
"""Set BootOrder so a specific Boot#### entry is first.

The virt-fw-vars CLI exposes --append-boot-filepath (creates Boot#### + appends
to BootOrder), but it does NOT expose a "make this entry first in BootOrder"
operation. This helper fills that gap by using the virt.firmware Python API
directly (EfiVar.set_boot_order). Called from lamboot-repair as
repair.nvram.set_first.

Args (positional):
    VARS_FILE        — path to OVMF VARS (regular file or block device)
    HEAD_INDEX_HEX   — Boot#### number (4 hex chars, e.g. "0007") to move
                       to the head of BootOrder

Exit codes:
    0  — success (BootOrder updated and VARS saved)
    1  — generic failure
    2  — Boot#### not present in NVRAM
    3  — entry already at head; nothing to do
"""
from __future__ import annotations

import struct
import sys


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        sys.stderr.write(
            "usage: _nvram_set_first_boot.py VARS_FILE HEAD_INDEX_HEX\n"
            "  e.g. _nvram_set_first_boot.py /dev/zvol/POOL/vm-NN-disk-2 0007\n"
        )
        return 1

    vars_path = argv[1]
    head_hex = argv[2].strip()
    if len(head_hex) != 4 or not all(c in "0123456789abcdefABCDEF" for c in head_hex):
        sys.stderr.write(f"error: HEAD_INDEX_HEX must be 4 hex chars; got {head_hex!r}\n")
        return 1
    head_idx = int(head_hex, 16)

    try:
        from virt.firmware.varstore import edk2
        from virt.firmware.efi import efivar  # noqa: F401  (registers types)
    except ImportError as exc:
        sys.stderr.write(f"error: virt.firmware not importable: {exc}\n"
                         "  install python3-virt-firmware (Debian/Ubuntu)\n")
        return 1

    try:
        store = edk2.Edk2VarStore(vars_path)
    except Exception as exc:  # virt.firmware raises plain Exception in some versions
        sys.stderr.write(f"error: failed to open VARS at {vars_path}: {exc}\n")
        return 1

    varlist = store.get_varlist()

    # Discover all Boot#### entries currently in NVRAM
    existing_boot_indexes: list[int] = []
    for name in varlist.keys():
        if len(name) == 8 and name.startswith("Boot") and \
                all(c in "0123456789abcdefABCDEF" for c in name[4:]):
            existing_boot_indexes.append(int(name[4:], 16))

    if head_idx not in existing_boot_indexes:
        existing_names = ",".join(f"Boot{i:04X}" for i in sorted(existing_boot_indexes))
        sys.stderr.write(
            f"error: Boot{head_hex.upper()} not present in NVRAM\n"
            f"  available: {existing_names or '(none)'}\n"
        )
        return 2

    # Read current BootOrder (if any) so we can preserve relative order
    bo = varlist.get("BootOrder")
    current: list[int] = []
    if bo is not None and bo.data:
        # BootOrder is a packed array of little-endian uint16
        for off in range(0, len(bo.data), 2):
            (item,) = struct.unpack_from("=H", bo.data, off)
            current.append(item)
    else:
        # No BootOrder var — synthesize from sorted Boot#### entries
        current = sorted(existing_boot_indexes)

    if current and current[0] == head_idx:
        sys.stderr.write(f"info: Boot{head_hex.upper()} already at head of BootOrder\n")
        return 3

    # Move head_idx to front; preserve order of the rest
    new_order = [head_idx] + [i for i in current if i != head_idx]

    # Append any Boot#### that exists in NVRAM but is missing from BootOrder
    # (so existing entries stay reachable after the reorder)
    for i in existing_boot_indexes:
        if i not in new_order:
            new_order.append(i)

    # Set BootOrder. EfiVar.set_boot_order packs little-endian uint16 array.
    if bo is None:
        bo = varlist.create("BootOrder")
    bo.set_boot_order(new_order)

    # Persist
    store.write_varstore(vars_path, varlist)

    sys.stderr.write(
        f"info: BootOrder updated; head=Boot{head_hex.upper()}; "
        f"new order = {','.join(f'{i:04X}' for i in new_order)}\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
