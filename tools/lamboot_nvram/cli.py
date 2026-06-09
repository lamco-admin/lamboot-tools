"""lamboot-nvram CLI — inventory + clean over the UEFI NVRAM boot-entry surface."""
from __future__ import annotations

import argparse
import datetime as _dt
import os
import pathlib
import subprocess
import sys
from typing import Optional

from lamboot_toolkit import envelope as env_mod
from lamboot_toolkit import registry as reg_mod
from lamboot_toolkit.exitcodes import (
    EXIT_OK, EXIT_ERROR, EXIT_PARTIAL, EXIT_NOOP, EXIT_ABORT,
    EXIT_NOT_APPLICABLE, EXIT_PREREQUISITE,
)

from . import __version__, model

TOOL_NAME = "lamboot-nvram"

_SEV_FOR_CATEGORY = {
    model.CAT_DANGLING: env_mod.SEV_WARNING,
    model.CAT_DUPLICATE: env_mod.SEV_INFO,
    model.CAT_DEAD_OS: env_mod.SEV_WARNING,
    model.CAT_ORPHAN_BOOTORDER: env_mod.SEV_WARNING,
}


# ── data sources ─────────────────────────────────────────────────────────────

def _read_live() -> "Optional[str]":
    try:
        r = subprocess.run(["efibootmgr", "-v"], capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return None
    return r.stdout if r.returncode == 0 else None


def _read_offline(efidisk: str) -> "Optional[str]":
    try:
        r = subprocess.run(["virt-fw-vars", "--input", efidisk, "--print"],
                           capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return None
    return r.stdout if r.returncode == 0 else None


def _present_partuuids() -> "set[str]":
    try:
        r = subprocess.run(["lsblk", "-rno", "PARTUUID"], capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return set()
    return {ln.strip().lower() for ln in r.stdout.splitlines() if ln.strip()}


def _load(args: argparse.Namespace) -> "tuple[Optional[model.Nvram], Optional[set[str]], Optional[str]]":
    """Return (nvram, present_partuuids|None, error_message|None)."""
    if getattr(args, "efidisk", None):
        text = _read_offline(args.efidisk)
        if text is None:
            return None, None, f"could not read efidisk {args.efidisk} (need virt-fw-vars)"
        return model.parse_virtfw(text), None, None  # offline: no live partition table
    text = _read_live()
    if text is None:
        return None, None, "could not read NVRAM (need efibootmgr and an EFI-booted system)"
    return model.parse_efibootmgr(text), _present_partuuids(), None


# ── envelope helper ──────────────────────────────────────────────────────────

def _emit(args, exit_code, findings, data):
    env = env_mod.build(tool=TOOL_NAME, version=__version__, command=TOOL_NAME,
                        exit_code=exit_code, findings=findings, data=data,
                        dry_run=getattr(args, "apply", True) is False and hasattr(args, "apply"))
    env_mod.emit(env, sys.stdout)
    return exit_code


def _err(args, message: str, code: int = EXIT_PREREQUISITE) -> int:
    if getattr(args, "json", False):
        f = env_mod.Finding(id="nvram.unavailable", category="nvram",
                            severity=env_mod.SEV_ERROR, status="fail",
                            title="NVRAM source unavailable", message=message)
        return _emit(args, code, [f], None)
    print(f"lamboot-nvram: {message}", file=sys.stderr)
    return code


def _candidate_finding(c: "model.Candidate") -> env_mod.Finding:
    return env_mod.Finding(
        id=f"nvram.{c.category}",
        category="nvram",
        severity=_SEV_FOR_CATEGORY.get(c.category, env_mod.SEV_WARNING),
        status="warn",
        title=f"Boot{c.num} {c.label}".strip(),
        message=c.reason,
        context={"num": c.num, "category": c.category, "keep": c.keep_num},
    )


# ── subcommands ──────────────────────────────────────────────────────────────

def cmd_inventory(args: argparse.Namespace) -> int:
    nv, partuuids, err = _load(args)
    if err:
        return _err(args, err)
    cands = model.classify(nv, model.ALL_CATEGORIES, partuuids)
    findings = [_candidate_finding(c) for c in cands]

    if args.json:
        data = {
            "boot_current": nv.boot_current,
            "boot_order": nv.boot_order,
            "entries": [
                {"num": e.num, "label": e.label, "active": e.active,
                 "loader": e.loader_path, "part_guid": e.part_guid,
                 "firmware": e.is_firmware}
                for e in nv.entries
            ],
        }
        return _emit(args, EXIT_OK, findings, data)

    print(f"BootCurrent: {nv.boot_current or '-'}    BootOrder: {','.join(nv.boot_order) or '-'}")
    flagged = {c.num: c for c in cands}
    for e in nv.entries:
        mark = "  "
        if e.is_firmware:
            mark = "fw"
        elif e.num in flagged:
            mark = " !"
        print(f"{mark} Boot{e.num}{'*' if e.active else ' '} {e.label}"
              + (f"  ->  {e.loader_path}" if e.loader_path else ""))
    if cands:
        print(f"\n{len(cands)} hygiene candidate(s):")
        for c in cands:
            print(f"  ! Boot{c.num} [{c.category}] {c.reason}")
    else:
        print("\nNo hygiene candidates — NVRAM is clean.")
    return EXIT_OK


def _backup_dir(args) -> pathlib.Path:
    if getattr(args, "backup_dir", None):
        return pathlib.Path(args.backup_dir)
    ts = _dt.datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
    return pathlib.Path(f"/var/backups/lamboot-nvram-{ts}")


def cmd_clean(args: argparse.Namespace) -> int:
    nv, partuuids, err = _load(args)
    if err:
        return _err(args, err)

    cats = tuple(args.category) if args.category else model.ALL_CATEGORIES
    if args.exclude:
        cats = tuple(c for c in cats if c not in args.exclude)
    cands = model.classify(nv, cats, partuuids)
    # orphan-bootorder is a BootOrder repair, handled by rewrite; entry deletions
    # are the rest.
    to_delete = [c for c in cands if c.category != model.CAT_ORPHAN_BOOTORDER]
    orphans = [c for c in cands if c.category == model.CAT_ORPHAN_BOOTORDER]

    if not cands:
        if args.json:
            return _emit(args, EXIT_NOOP, [], {"removed": [], "boot_order_repaired": False})
        print("lamboot-nvram: nothing to clean — NVRAM is already tidy.")
        return EXIT_NOOP

    findings = [_candidate_finding(c) for c in cands]

    # Preview (dry-run is the default; --apply performs the change).
    if not args.apply:
        if args.json:
            data = {"would_remove": [c.num for c in to_delete],
                    "would_repair_bootorder": bool(orphans)}
            return _emit(args, EXIT_OK, findings, data)
        print(f"DRY-RUN: would remove {len(to_delete)} entr(y/ies); "
              f"BootOrder repair: {'yes' if orphans else 'no'}  (pass --apply to perform)")
        for c in to_delete:
            print(f"  would delete Boot{c.num} [{c.category}] {c.reason}")
        for c in orphans:
            print(f"  would drop Boot{c.num} from BootOrder ({c.reason})")
        return EXIT_OK

    # --apply path: requires root + a live (efibootmgr) target. Offline write is
    # not yet supported; surface honestly rather than pretend.
    if getattr(args, "efidisk", None):
        return _err(args, "offline --efidisk clean --apply is not yet supported; "
                          "inventory offline, then apply on the live system",
                    code=EXIT_NOT_APPLICABLE)
    if os.geteuid() != 0:
        return _err(args, "clean --apply requires root; rerun with sudo")

    backup = _backup_dir(args)
    backup.mkdir(parents=True, exist_ok=True)
    live = _read_live()
    (backup / "efibootmgr.pre.txt").write_text(live or "")
    _log(f"clean --apply categories={','.join(cats)} backup={backup}", backup)

    removed, failed = [], []
    for c in to_delete:
        r = subprocess.run(["efibootmgr", "-b", c.num, "-B"], capture_output=True, text=True, check=False)
        if r.returncode == 0:
            removed.append(c.num); _log(f"removed Boot{c.num} [{c.category}] {c.reason}", backup)
        else:
            failed.append(c.num); _log(f"FAILED to remove Boot{c.num}: {r.stderr.strip()}", backup)
    # BootOrder is rewritten by efibootmgr -B automatically; for pure orphan refs
    # (no entry) rewrite explicitly to drop them.
    if orphans:
        nums = {e.num for e in model.parse_efibootmgr(_read_live() or "").entries}
        new_order = [n for n in nv.boot_order if n.upper() in nums]
        if new_order:
            subprocess.run(["efibootmgr", "-o", ",".join(new_order)],
                           capture_output=True, text=True, check=False)

    code = EXIT_OK if not failed else EXIT_PARTIAL
    if args.json:
        data = {"removed": removed, "failed": failed, "backup_dir": str(backup)}
        return _emit(args, code, findings, data)
    print(f"removed {len(removed)} entr(y/ies)" + (f", {len(failed)} failed" if failed else "")
          + f"; backup at {backup}")
    return code


# ── logging + restore ─────────────────────────────────────────────────────────

_LOG = pathlib.Path("/var/log/lamboot/lamboot-nvram.log")


def _log(msg: str, backup: "Optional[pathlib.Path]" = None) -> None:
    """Append an audit line to the system log and (when applying) the backup dir.

    Every mutating action is logged so a clean/restore is itself auditable —
    best-effort: a non-writable log location never blocks the operation.
    """
    ts = _dt.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    line = f"{ts} lamboot-nvram: {msg}\n"
    for target in (_LOG, (backup / "actions.log") if backup else None):
        if target is None:
            continue
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open("a") as fh:
                fh.write(line)
        except OSError:
            pass


def _disk_for_partuuid(partuuid: str) -> "tuple[Optional[str], Optional[str]]":
    """Resolve a GPT PARTUUID to (disk_device, partition_number) for efibootmgr."""
    try:
        r = subprocess.run(["lsblk", "-rno", "NAME,PARTUUID,PKNAME"],
                           capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return None, None
    for ln in r.stdout.splitlines():
        cols = ln.split()
        if len(cols) >= 2 and cols[1].lower() == partuuid.lower():
            name = cols[0]
            disk = cols[2] if len(cols) >= 3 and cols[2] else name.rstrip("0123456789p")
            partnum = "".join(c for c in name[len(disk):] if c.isdigit())
            return f"/dev/{disk}", (partnum or None)
    return None, None


def _latest_backup() -> "Optional[pathlib.Path]":
    base = pathlib.Path("/var/backups")
    cands = sorted(base.glob("lamboot-nvram-*")) + sorted(base.glob("lamboot-doctor-*"))
    return cands[-1] if cands else None


def cmd_restore(args: argparse.Namespace) -> int:
    bdir = pathlib.Path(args.backup_dir) if args.backup_dir else _latest_backup()
    if bdir is None or not (bdir / "efibootmgr.pre.txt").exists():
        return _err(args, f"no NVRAM backup found (looked in {bdir or '/var/backups/lamboot-nvram-*'})")
    backup_nv = model.parse_efibootmgr((bdir / "efibootmgr.pre.txt").read_text())
    live = _read_live()
    if live is None:
        return _err(args, "could not read current NVRAM (need efibootmgr on an EFI system)")
    current = model.parse_efibootmgr(live)
    plan = model.restore_plan(backup_nv, current)

    findings = [
        env_mod.Finding(id="nvram.restore", category="nvram", severity=env_mod.SEV_INFO,
                        status="warn", title=f"Re-create Boot{e.num} {e.label}".strip(),
                        message=f"{e.loader_path} on partition {e.part_guid}",
                        context={"num": e.num})
        for e in plan
    ]
    if not plan:
        if args.json:
            return _emit(args, EXIT_NOOP, [], {"restored": [], "backup_dir": str(bdir)})
        print(f"lamboot-nvram: nothing to restore (all backed-up entries still present) from {bdir}")
        return EXIT_NOOP

    if not args.apply:
        if args.json:
            return _emit(args, EXIT_OK, findings, {"would_restore": [e.num for e in plan], "backup_dir": str(bdir)})
        print(f"DRY-RUN: would re-create {len(plan)} boot entr(y/ies) from {bdir} (pass --apply):")
        for e in plan:
            print(f"  Boot{e.num} {e.label} -> {e.loader_path}")
        return EXIT_OK

    if os.geteuid() != 0:
        return _err(args, "restore --apply requires root; rerun with sudo")

    restored, failed = [], []
    for e in plan:
        disk, partnum = _disk_for_partuuid(e.part_guid)
        if not disk or not partnum:
            failed.append(e.num); _log(f"restore Boot{e.num} FAILED: cannot resolve disk for {e.part_guid}", bdir)
            continue
        r = subprocess.run(["efibootmgr", "-c", "-b", e.num, "-d", disk, "-p", partnum,
                            "-l", e.loader_path, "-L", e.label or f"Restored-{e.num}"],
                           capture_output=True, text=True, check=False)
        if r.returncode == 0:
            restored.append(e.num); _log(f"restored Boot{e.num} ({e.loader_path} on {disk}p{partnum})", bdir)
        else:
            failed.append(e.num); _log(f"restore Boot{e.num} FAILED: {r.stderr.strip()}", bdir)

    code = EXIT_OK if not failed else EXIT_PARTIAL
    if args.json:
        return _emit(args, code, findings, {"restored": restored, "failed": failed, "backup_dir": str(bdir)})
    print(f"restored {len(restored)} entr(y/ies)" + (f", {len(failed)} failed" if failed else ""))
    return code


# ── registry + parser ────────────────────────────────────────────────────────

SUBCOMMANDS = [
    reg_mod.Subcommand(
        name="inventory", category="Diagnostics",
        summary="List UEFI boot entries and classify each (live, dangling, duplicate, dead-OS)",
        syntax="lamboot-nvram inventory [--efidisk FILE] [--json]",
        args=("--efidisk FILE:Inspect an offline efidisk/OVMF_VARS image instead of live efivarfs",),
        examples=("lamboot-nvram inventory", "lamboot-nvram inventory --efidisk /dev/zvol/AB/vm-129-disk-1 --json"),
        notes="Resolves each Boot#### against present partitions. Reads live efivarfs (unprivileged) or, with --efidisk, an offline vars image via virt-fw-vars.",
        offline_capable=True, requires_root=False, see_also=("clean",),
        doc_url="https://github.com/lamco-admin/lamboot-tools", maturity="draft",
    ),
    reg_mod.Subcommand(
        name="clean", category="Maintenance",
        summary="Remove stale UEFI boot entries (dry-run by default)",
        syntax="lamboot-nvram clean [--apply] [--category CAT ...] [--exclude CAT ...] [--efidisk FILE] [--backup-dir DIR] [--json]",
        args=(
            "--apply:Actually delete entries (default: preview only)",
            "--category CAT:dangling | duplicate | dead-os | orphan-bootorder (repeatable; default: all)",
            "--exclude CAT:Skip a category (repeatable)",
            "--efidisk FILE:Operate on an offline efidisk image (inventory/preview; apply is live-only)",
            "--backup-dir DIR:Where to export the pre-change NVRAM",
        ),
        examples=("lamboot-nvram clean", "sudo lamboot-nvram clean --category duplicate --apply"),
        notes="NEVER removes BootCurrent or the default (BootOrder head). Backs up via efibootmgr -v before --apply; reverse with 'lamboot-nvram restore'. Logs every action to /var/log/lamboot/.",
        offline_capable=True, requires_root=True, see_also=("inventory", "restore"),
        doc_url="https://github.com/lamco-admin/lamboot-tools", maturity="draft",
    ),
    reg_mod.Subcommand(
        name="restore", category="Maintenance",
        summary="Re-create boot entries removed by a previous clean (from its backup)",
        syntax="lamboot-nvram restore [--apply] [--backup-dir DIR] [--json]",
        args=(
            "--apply:Actually re-create entries (default: preview only)",
            "--backup-dir DIR:Backup to restore from (default: most recent /var/backups/lamboot-{nvram,doctor}-*)",
        ),
        examples=("lamboot-nvram restore", "sudo lamboot-nvram restore --apply"),
        notes="Reads the backup's efibootmgr.pre.txt, re-creates any entry present then but missing now (efibootmgr -c, resolving the disk from the partition UUID). Idempotent.",
        offline_capable=False, requires_root=True, see_also=("clean",),
        doc_url="https://github.com/lamco-admin/lamboot-tools", maturity="draft",
    ),
]


def _common(p: argparse.ArgumentParser) -> None:
    p.add_argument("--json", action="store_true", help="Emit the shared toolkit JSON envelope")
    p.add_argument("--no-color", action="store_true")
    p.add_argument("-q", "--quiet", action="store_true")
    p.add_argument("-v", "--verbose", action="store_true")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog=TOOL_NAME, description="UEFI NVRAM boot-entry hygiene.")
    parser.add_argument("--version", action="version", version=f"{TOOL_NAME} {__version__}")
    parser.add_argument("--json-schema", action="store_true")
    parser.add_argument("--dump-registry", action="store_true", help=argparse.SUPPRESS)
    sub = parser.add_subparsers(dest="command", required=False, metavar="<subcommand>")

    p_inv = sub.add_parser("inventory", help=SUBCOMMANDS[0].summary)
    _common(p_inv)
    p_inv.add_argument("--efidisk")
    p_inv.set_defaults(func=cmd_inventory)

    p_cl = sub.add_parser("clean", help=SUBCOMMANDS[1].summary)
    _common(p_cl)
    p_cl.add_argument("--apply", action="store_true")
    p_cl.add_argument("--category", action="append", choices=model.ALL_CATEGORIES)
    p_cl.add_argument("--exclude", action="append", choices=model.ALL_CATEGORIES)
    p_cl.add_argument("--efidisk")
    p_cl.add_argument("--backup-dir")
    p_cl.set_defaults(func=cmd_clean)

    p_rs = sub.add_parser("restore", help=SUBCOMMANDS[2].summary)
    _common(p_rs)
    p_rs.add_argument("--apply", action="store_true")
    p_rs.add_argument("--backup-dir")
    p_rs.set_defaults(func=cmd_restore)
    return parser


def main(argv: "Optional[list]" = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if getattr(args, "json_schema", False):
        env_mod.emit(env_mod.schema(), sys.stdout)
        return EXIT_OK
    if getattr(args, "dump_registry", False):
        sys.stdout.write(reg_mod.dump(TOOL_NAME, __version__, env_mod._toolkit_version(), SUBCOMMANDS))
        return EXIT_OK
    if not getattr(args, "command", None):
        parser.print_help(sys.stderr)
        return EXIT_ERROR
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
