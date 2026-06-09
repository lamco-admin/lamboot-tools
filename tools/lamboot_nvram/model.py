"""UEFI NVRAM boot-entry model: parse, classify, and decide removals.

Pure data logic (the part that justified Python over bash): parse the two boot
-entry sources — live ``efibootmgr -v`` and offline ``virt-fw-vars --print`` (a
stopped VM's efidisk) — into a typed model, then classify each ``Boot####`` for
hygiene. Shelling out to the actual tools lives in :mod:`lamboot_nvram.cli`; this
module is side-effect-free and unit-testable against captured output.

Classification categories (SPEC-LAMBOOT-BOOT-AUDIT-AND-HYGIENE §7):
  * ``duplicate``       — same loader on the same partition target; keep one
  * ``orphan-bootorder``— BootOrder references a Boot#### that doesn't exist
  * ``dangling``        — the target partition is not present (live only)
  * ``dead-os``         — \\EFI\\<vendor>\\ loader absent from any ESP (best-effort)

Absolute guards: BootCurrent and the head of BootOrder (the active default) are
never proposed for removal, and BootOrder is rewritten free of any deleted num.
"""
from __future__ import annotations

import dataclasses
import re
from typing import Optional

CAT_DUPLICATE = "duplicate"
CAT_ORPHAN_BOOTORDER = "orphan-bootorder"
CAT_DANGLING = "dangling"
CAT_DEAD_OS = "dead-os"
ALL_CATEGORIES = (CAT_DUPLICATE, CAT_ORPHAN_BOOTORDER, CAT_DANGLING, CAT_DEAD_OS)


@dataclasses.dataclass
class BootEntry:
    num: str                       # 4-hex, e.g. "0005"
    label: str
    active: bool = True            # the efibootmgr '*'
    loader_path: str = ""          # e.g. \EFI\LamBoot\lambootx64.efi
    part_guid: str = ""            # GPT partition GUID, when present
    part_nr: str = ""              # partition number, when present
    is_firmware: bool = False      # FvVol/FvFile builtin (never hygiene-removed)
    raw: str = ""

    def target_key(self) -> str:
        """Identity for de-duplication: same loader on the same partition."""
        part = self.part_guid or self.part_nr or "?"
        return f"{part.lower()}::{self.loader_path.lower()}"


@dataclasses.dataclass
class Nvram:
    boot_current: Optional[str]
    boot_order: "list[str]"
    entries: "list[BootEntry]"

    def by_num(self, num: str) -> Optional[BootEntry]:
        for e in self.entries:
            if e.num == num:
                return e
        return None


# ── Parsers ─────────────────────────────────────────────────────────────────

_HD = re.compile(r"HD\((\d+),GPT,([0-9a-fA-F-]+),", re.I)
_FILE = re.compile(r"/File\((\\[^)]*)\)", re.I)
_EFIBOOTMGR_ENTRY = re.compile(r"^Boot([0-9A-Fa-f]{4})(\*?)\s+(.*)$")


def parse_efibootmgr(text: str) -> Nvram:
    """Parse ``efibootmgr -v`` output (live efivarfs)."""
    boot_current = None
    boot_order: "list[str]" = []
    entries: "list[BootEntry]" = []
    for line in text.splitlines():
        if line.startswith("BootCurrent:"):
            boot_current = line.split(":", 1)[1].strip() or None
            continue
        if line.startswith("BootOrder:"):
            boot_order = [t.strip() for t in line.split(":", 1)[1].split(",") if t.strip()]
            continue
        m = _EFIBOOTMGR_ENTRY.match(line)
        if not m:
            continue
        num, star, rest = m.group(1).upper(), m.group(2), m.group(3)
        # Label is up to the first tab (device path follows); no tab -> all label.
        if "\t" in rest:
            label, devpath = rest.split("\t", 1)
        else:
            label, devpath = rest, ""
        is_fw = "FvVol(" in devpath or "FvFile(" in devpath
        hd = _HD.search(devpath)
        fp = _FILE.search(devpath)
        entries.append(BootEntry(
            num=num, label=label.strip(), active=(star == "*"),
            loader_path=(fp.group(1) if fp else ""),
            part_nr=(hd.group(1) if hd else ""),
            part_guid=(hd.group(2) if hd else ""),
            is_firmware=is_fw, raw=line,
        ))
    return Nvram(boot_current, boot_order, entries)


_VFW_ENTRY = re.compile(r"^Boot([0-9A-Fa-f]{4})\s*:\s*boot entry:\s*(.*)$")
_VFW_TITLE = re.compile(r'title="?([^"]*?)"?(?:\s+\w+=|$)')
_VFW_PART = re.compile(r"Partition\(nr=(\d+)\)", re.I)
_VFW_FILEPATH = re.compile(r"FilePath\((\\[^)]*)\)", re.I)
_VFW_GUID = re.compile(r"GPT,([0-9a-fA-F-]+)", re.I)


def parse_virtfw(text: str) -> Nvram:
    """Parse ``virt-fw-vars --print`` output (offline efidisk/OVMF_VARS image)."""
    boot_current = None
    boot_order: "list[str]" = []
    entries: "list[BootEntry]" = []
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("BootCurrent"):
            mm = re.search(r":\s*([0-9A-Fa-f]{4})", s)
            boot_current = mm.group(1).upper() if mm else None
            continue
        if s.startswith("BootOrder"):
            boot_order = [t.strip().upper() for t in re.findall(r"[0-9A-Fa-f]{4}", s.split(":", 1)[1])]
            continue
        m = _VFW_ENTRY.match(s)
        if not m:
            continue
        num, rest = m.group(1).upper(), m.group(2)
        is_fw = "FvName(" in rest or "FvFileName(" in rest or "FvVol(" in rest
        title = _VFW_TITLE.search(rest)
        part = _VFW_PART.search(rest)
        guid = _VFW_GUID.search(rest)
        fp = _VFW_FILEPATH.search(rest)
        entries.append(BootEntry(
            num=num, label=(title.group(1).strip() if title else ""), active=True,
            loader_path=(fp.group(1) if fp else ""),
            part_nr=(part.group(1) if part else ""),
            part_guid=(guid.group(1) if guid else ""),
            is_firmware=is_fw, raw=line,
        ))
    return Nvram(boot_current, boot_order, entries)


# ── Classification ──────────────────────────────────────────────────────────

@dataclasses.dataclass
class Candidate:
    num: str
    label: str
    category: str
    reason: str
    keep_num: str = ""   # for duplicates: the entry retained


def protected_nums(nv: Nvram) -> "set[str]":
    """Never propose these for removal: BootCurrent + the default (BootOrder head)."""
    p: "set[str]" = set()
    if nv.boot_current:
        p.add(nv.boot_current.upper())
    if nv.boot_order:
        p.add(nv.boot_order[0].upper())
    return p


def classify(
    nv: Nvram,
    categories: "tuple[str, ...]" = ALL_CATEGORIES,
    present_partuuids: "Optional[set[str]]" = None,
) -> "list[Candidate]":
    """Return removal candidates, honoring the absolute protection guards.

    ``present_partuuids`` (lowercased GPT PARTUUIDs that exist on the system)
    enables the ``dangling`` check; pass None to skip it (e.g. offline mode where
    the live partition table isn't available).
    """
    protected = protected_nums(nv)
    real = [e for e in nv.entries if not e.is_firmware]
    out: "list[Candidate]" = []

    if CAT_DUPLICATE in categories:
        groups: "dict[str, list[BootEntry]]" = {}
        for e in real:
            if e.loader_path:
                groups.setdefault(e.target_key(), []).append(e)
        for key, grp in groups.items():
            if len(grp) < 2:
                continue
            # Keep a protected entry if the group has one, else the BootOrder-
            # earliest, else the lowest num. Flag the others.
            keep = _pick_keeper(grp, nv, protected)
            for e in grp:
                if e.num == keep.num or e.num in protected:
                    continue
                out.append(Candidate(e.num, e.label, CAT_DUPLICATE,
                                     f"duplicate of Boot{keep.num} ({e.loader_path})",
                                     keep_num=keep.num))

    if CAT_ORPHAN_BOOTORDER in categories:
        nums = {e.num for e in nv.entries}
        for ref in nv.boot_order:
            if ref.upper() not in nums:
                # An orphan BootOrder ref is not an entry to delete (it has none);
                # it's a BootOrder repair. Surface it as a candidate keyed on the
                # dangling ref so clean can rewrite BootOrder.
                out.append(Candidate(ref.upper(), "(missing)", CAT_ORPHAN_BOOTORDER,
                                     f"BootOrder references Boot{ref.upper()} which has no entry"))

    if CAT_DANGLING in categories and present_partuuids is not None:
        for e in real:
            if e.num in protected or not e.part_guid:
                continue
            if e.part_guid.lower() not in present_partuuids:
                out.append(Candidate(e.num, e.label, CAT_DANGLING,
                                     f"target partition {e.part_guid} is not present"))

    return out


def _pick_keeper(grp: "list[BootEntry]", nv: Nvram, protected: "set[str]") -> BootEntry:
    for e in grp:
        if e.num in protected:
            return e
    order_index = {n.upper(): i for i, n in enumerate(nv.boot_order)}
    return min(grp, key=lambda e: (order_index.get(e.num, 10**6), e.num))


def restore_plan(backup: Nvram, current: Nvram) -> "list[BootEntry]":
    """Entries present in the backup but missing now (non-firmware, with a
    resolvable loader) — the set a `restore` must re-create.
    """
    cur = {e.num for e in current.entries}
    return [
        e for e in backup.entries
        if not e.is_firmware and e.num not in cur and e.loader_path and e.part_guid
    ]

