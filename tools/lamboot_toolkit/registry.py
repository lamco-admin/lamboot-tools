"""Subcommand help registry — the Python side of the suite help contract.

The bash tools declare subcommands via ``register_subcommand`` (13 fields,
0x1F-separated, in ``lib/lamboot-toolkit-help.sh``); ``scripts/registry-to-man``
renders man/website from that registry. Python tools can't be sourced, so they
declare the *same* 13 fields with :class:`Subcommand` and emit them in the
identical dump format via :func:`dump` (exposed by each tool as
``--dump-registry``), which ``registry-to-man`` consumes for Python tools.

Field order matches the bash record: name, aliases, category, summary, syntax,
args (|-joined ``flag:desc``), examples (||-joined), notes, offline_capable,
requires_root, see_also (comma-joined), doc_url, maturity.
"""
from __future__ import annotations

import dataclasses

FS = "\x1f"  # LAMBOOT_HELP_FS — the bash registry field separator.


@dataclasses.dataclass(frozen=True)
class Subcommand:
    name: str
    category: str
    summary: str
    syntax: str
    args: "tuple[str, ...]" = ()
    examples: "tuple[str, ...]" = ()
    notes: str = ""
    offline_capable: bool = True
    requires_root: bool = False
    see_also: "tuple[str, ...]" = ()
    doc_url: str = ""
    maturity: str = "stable"
    aliases: "tuple[str, ...]" = ()

    def record(self) -> str:
        """Serialize to the 13-field 0x1F record the bash registry produces."""
        return FS.join(
            (
                self.name,
                ",".join(self.aliases),
                self.category,
                self.summary,
                self.syntax,
                "|".join(self.args),
                "||".join(self.examples),
                self.notes,
                "true" if self.offline_capable else "false",
                "true" if self.requires_root else "false",
                ",".join(self.see_also),
                self.doc_url,
                self.maturity,
            )
        )


def find(subcommands: "list[Subcommand]", name: str) -> "Subcommand | None":
    for s in subcommands:
        if s.name == name or name in s.aliases:
            return s
    return None


def dump(
    tool_name: str,
    tool_version: str,
    toolkit_version: str,
    subcommands: "list[Subcommand]",
) -> str:
    """Emit the bash-compatible registry dump consumed by registry-to-man."""
    lines = [
        f"TOOL_NAME={tool_name}",
        f"TOOL_VERSION={tool_version}",
        f"TOOLKIT_VERSION={toolkit_version}",
        "---REGISTRY-BEGIN---",
        "\n".join(s.record() for s in subcommands),
        "---REGISTRY-END---",
    ]
    return "\n".join(lines) + "\n"
