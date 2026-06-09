"""Tests for lamboot-nvram — NVRAM boot-entry parsing, classification, and CLI.

The classifier is pure and unit-tested against real captured output (the VM-129
duplicate Boot0005/0006 case); the CLI is exercised with its NVRAM source
monkeypatched so the tests need no live efivarfs.
"""
from __future__ import annotations

import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve()
sys.path.insert(0, str(HERE.parent.parent))  # tools/

from lamboot_nvram import cli, model  # noqa: E402

LIVE = (
    "BootCurrent: 0006\n"
    "BootOrder: 0006,0005,0004,0003,0000\n"
    "Boot0000* BootManagerMenuApp\tFvVol(7cb8bdc9)/FvFile(eec25bdc)\n"
    "Boot0003* UEFI QEMU QEMU HARDDISK \tPciRoot(0x0)/Pci(0x1e,0x0)/SCSI(0,0)\n"
    "Boot0004* Ubuntu\tHD(3,GPT,4912964d-2e2d-41fc-8fbc-0cce292dc5dd,0x9,0x1)/File(\\EFI\\ubuntu\\shimx64.efi)\n"
    "Boot0005* LamBoot\tHD(3,GPT,4912964d-2e2d-41fc-8fbc-0cce292dc5dd,0x9,0x1)/File(\\EFI\\LamBoot\\lambootx64.efi)\n"
    "Boot0006* LamBoot-migrated\tHD(3,GPT,4912964d-2e2d-41fc-8fbc-0cce292dc5dd,0x9,0x1)/File(\\EFI\\LamBoot\\lambootx64.efi)\n"
)

OFFLINE = (
    'Boot0005            : boot entry: title="LamBoot" devpath=Partition(nr=3)/FilePath(\\EFI\\LamBoot\\lambootx64.efi)\n'
    'Boot0006            : boot entry: title="LamBoot-migrated" devpath=Partition(nr=3)/FilePath(\\EFI\\LamBoot\\lambootx64.efi)\n'
    "BootOrder           : boot order: 0006, 0005, 0004\n"
)


def test_parse_efibootmgr_basics():
    nv = model.parse_efibootmgr(LIVE)
    assert nv.boot_current == "0006"
    assert nv.boot_order[0] == "0006"
    assert len(nv.entries) == 5
    fw = [e for e in nv.entries if e.is_firmware]
    assert {e.num for e in fw} == {"0000"}


def test_duplicate_keeps_the_default_flags_the_rest():
    nv = model.parse_efibootmgr(LIVE)
    cands = model.classify(nv, (model.CAT_DUPLICATE,))
    dups = [c for c in cands if c.category == model.CAT_DUPLICATE]
    assert len(dups) == 1
    assert dups[0].num == "0005" and dups[0].keep_num == "0006"


def test_protected_entries_never_flagged():
    nv = model.parse_efibootmgr(LIVE)
    cands = model.classify(nv)
    flagged = {c.num for c in cands if c.category != model.CAT_ORPHAN_BOOTORDER}
    assert "0006" not in flagged  # BootCurrent + BootOrder head
    assert "0004" not in flagged  # distinct loader


def test_orphan_bootorder_detected():
    nv = model.parse_efibootmgr(LIVE + "")  # BootOrder lists 0000 which has an entry
    nv.boot_order.append("00AB")  # a ref with no entry
    cands = model.classify(nv, (model.CAT_ORPHAN_BOOTORDER,))
    assert any(c.num == "00AB" for c in cands)


def test_dangling_requires_present_partuuids():
    nv = model.parse_efibootmgr(LIVE)
    # Partition not in the present set -> dangling (excluding the protected 0006).
    cands = model.classify(nv, (model.CAT_DANGLING,), present_partuuids=set())
    nums = {c.num for c in cands}
    assert "0005" in nums and "0004" in nums
    assert "0006" not in nums  # protected


def test_parse_virtfw_offline():
    nv = model.parse_virtfw(OFFLINE)
    assert nv.boot_order[0] == "0006"
    cands = model.classify(nv, (model.CAT_DUPLICATE,), present_partuuids=None)
    assert any(c.num == "0005" and c.category == model.CAT_DUPLICATE for c in cands)


# ── CLI (source monkeypatched) ────────────────────────────────────────────────

def test_cli_inventory_json(monkeypatch, capsys):
    monkeypatch.setattr(cli, "_read_live", lambda: LIVE)
    monkeypatch.setattr(cli, "_present_partuuids", lambda: {"4912964d-2e2d-41fc-8fbc-0cce292dc5dd"})
    rc = cli.main(["inventory", "--json"])
    out = json.loads(capsys.readouterr().out)
    assert rc == 0
    assert out["tool"] == "lamboot-nvram"
    assert out["schema_version"] == "v1"
    assert any(f["id"] == "nvram.duplicate" for f in out["findings"])


def test_cli_clean_dry_run_previews(monkeypatch, capsys):
    monkeypatch.setattr(cli, "_read_live", lambda: LIVE)
    monkeypatch.setattr(cli, "_present_partuuids", lambda: {"4912964d-2e2d-41fc-8fbc-0cce292dc5dd"})
    rc = cli.main(["clean", "--category", "duplicate", "--json"])
    out = json.loads(capsys.readouterr().out)
    assert rc == 0  # dry-run is non-destructive
    assert "0005" in out["data"]["would_remove"]
    assert "0006" not in out["data"]["would_remove"]


def test_cli_clean_nothing_to_do_is_noop(monkeypatch, capsys):
    clean = "BootCurrent: 0001\nBootOrder: 0001\nBoot0001* Only\tHD(1,GPT,aa,0x1,0x1)/File(\\EFI\\x\\x.efi)\n"
    monkeypatch.setattr(cli, "_read_live", lambda: clean)
    monkeypatch.setattr(cli, "_present_partuuids", lambda: {"aa"})
    rc = cli.main(["clean", "--json"])
    out = json.loads(capsys.readouterr().out)
    assert rc == 3  # EXIT_NOOP
    assert out["summary"]["status"] == "noop"


def test_cli_json_schema_and_dump_registry(capsys):
    assert cli.main(["--json-schema"]) == 0
    schema = json.loads(capsys.readouterr().out)
    assert schema["title"] == "lamboot-tools JSON envelope"
    assert cli.main(["--dump-registry"]) == 0
    dump = capsys.readouterr().out
    assert "TOOL_NAME=lamboot-nvram" in dump
    assert "inventory" in dump and "clean" in dump and "restore" in dump


PRE_WITH_0005 = (
    "BootCurrent: 0006\nBootOrder: 0006,0005\n"
    "Boot0005* LamBoot\tHD(3,GPT,4912964d-2e2d-41fc-8fbc-0cce292dc5dd,0x9,0x1)/File(\\EFI\\LamBoot\\lambootx64.efi)\n"
    "Boot0006* LamBoot-migrated\tHD(3,GPT,4912964d-2e2d-41fc-8fbc-0cce292dc5dd,0x9,0x1)/File(\\EFI\\LamBoot\\lambootx64.efi)\n"
)
CUR_NO_0005 = (
    "BootCurrent: 0006\nBootOrder: 0006\n"
    "Boot0006* LamBoot-migrated\tHD(3,GPT,4912964d-2e2d-41fc-8fbc-0cce292dc5dd,0x9,0x1)/File(\\EFI\\LamBoot\\lambootx64.efi)\n"
)


def test_cli_restore_dry_run_plans_recreation(monkeypatch, capsys, tmp_path):
    (tmp_path / "efibootmgr.pre.txt").write_text(PRE_WITH_0005)
    monkeypatch.setattr(cli, "_read_live", lambda: CUR_NO_0005)
    rc = cli.main(["restore", "--backup-dir", str(tmp_path), "--json"])
    out = json.loads(capsys.readouterr().out)
    assert rc == 0  # dry-run, non-destructive
    assert "0005" in out["data"]["would_restore"]


def test_cli_restore_nothing_when_all_present(monkeypatch, capsys, tmp_path):
    (tmp_path / "efibootmgr.pre.txt").write_text(PRE_WITH_0005)
    monkeypatch.setattr(cli, "_read_live", lambda: PRE_WITH_0005)  # current == backup
    rc = cli.main(["restore", "--backup-dir", str(tmp_path), "--json"])
    out = json.loads(capsys.readouterr().out)
    assert rc == 3  # EXIT_NOOP
    assert out["summary"]["status"] == "noop"


def test_clean_apply_logs_and_backs_up(monkeypatch, tmp_path):
    # --apply path with a mocked efibootmgr: backs up pre-state + writes a log.
    monkeypatch.setattr(cli, "_read_live", lambda: PRE_WITH_0005)
    monkeypatch.setattr(cli, "_present_partuuids", lambda: {"4912964d-2e2d-41fc-8fbc-0cce292dc5dd"})
    monkeypatch.setattr(cli.os, "geteuid", lambda: 0)
    monkeypatch.setattr(cli.subprocess, "run",
                        lambda *a, **k: type("R", (), {"returncode": 0, "stderr": ""})())
    monkeypatch.setattr(cli, "_LOG", tmp_path / "nvram.log")
    rc = cli.main(["clean", "--category", "duplicate", "--apply",
                   "--backup-dir", str(tmp_path / "bk")])
    assert rc == 0
    assert (tmp_path / "bk" / "efibootmgr.pre.txt").exists()
    assert (tmp_path / "bk" / "actions.log").exists()
    assert (tmp_path / "nvram.log").exists()
