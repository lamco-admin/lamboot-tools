"""Shared exit-code table — SPEC-LAMBOOT-TOOLKIT-V1 §6.

Identical to ``lib/lamboot-toolkit-lib.sh``'s ``EXIT_*`` constants, so a consumer
scripting the suite gets the same semantics from every tool, bash or Python.
Codes >= 8 are reserved for tool-specific use (documented in the tool's man).
"""
from __future__ import annotations

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_PARTIAL = 2
EXIT_NOOP = 3
EXIT_UNSAFE = 4
EXIT_ABORT = 5
EXIT_NOT_APPLICABLE = 6
EXIT_PREREQUISITE = 7
