"""Tests for the toolkit's shared Python infra (lamboot_toolkit).

The toolkit owns the JSON-envelope and help-registry contracts (CROSS-REPO-STATUS
§3); these assert the canonical implementation stays byte-compatible with the
bash suite (`lib/lamboot-toolkit-lib.sh`).
"""
from __future__ import annotations

import pathlib
import sys

HERE = pathlib.Path(__file__).resolve()
sys.path.insert(0, str(HERE.parent.parent))  # tools/

from lamboot_toolkit import envelope as env  # noqa: E402
from lamboot_toolkit import registry as reg  # noqa: E402
from lamboot_toolkit import exitcodes as ec  # noqa: E402


def test_exit_table_matches_spec():
    assert (ec.EXIT_OK, ec.EXIT_ERROR, ec.EXIT_PARTIAL, ec.EXIT_NOOP) == (0, 1, 2, 3)
    assert (ec.EXIT_UNSAFE, ec.EXIT_ABORT, ec.EXIT_NOT_APPLICABLE, ec.EXIT_PREREQUISITE) == (4, 5, 6, 7)


def test_status_for_exit_matches_bash_mapping():
    assert env.status_for_exit(0, 0) == "pass"
    assert env.status_for_exit(0, 2) == "warn"
    assert env.status_for_exit(2, 0) == "fail"
    assert env.status_for_exit(4, 0) == "unsafe"
    assert env.status_for_exit(1, 0) == "error"


def test_envelope_key_order():
    e = env.build(tool="t", version="0", command="t", exit_code=0, findings=[],
                  toolkit_version="0.8.2", host="h", run_id="r")
    assert list(e.keys()) == [
        "schema_version", "tool", "version", "toolkit_version", "timestamp",
        "host", "run_id", "command", "dry_run", "exit_code", "summary",
        "findings", "actions_taken", "backup_dir",
    ]


def test_generic_registry_dump():
    subs = [
        reg.Subcommand(name="inventory", category="Diagnostics", summary="s",
                       syntax="tool inventory"),
        reg.Subcommand(name="clean", category="Maintenance", summary="s2",
                       syntax="tool clean", maturity="draft"),
    ]
    dump = reg.dump("lamboot-nvram", "0.1.0", "0.8.2", subs)
    assert "TOOL_NAME=lamboot-nvram" in dump
    assert "---REGISTRY-BEGIN---" in dump and "---REGISTRY-END---" in dump
    body = dump.split("---REGISTRY-BEGIN---", 1)[1].split("---REGISTRY-END---", 1)[0]
    record = next(line for line in body.splitlines() if line.strip())
    assert record.count("\x1f") == 12  # 13 fields


def test_registry_find():
    subs = [reg.Subcommand(name="clean", category="c", summary="s", syntax="x",
                           aliases=("gc",))]
    assert reg.find(subs, "clean").name == "clean"
    assert reg.find(subs, "gc").name == "clean"
    assert reg.find(subs, "nope") is None
