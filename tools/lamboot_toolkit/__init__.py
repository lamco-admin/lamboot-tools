"""lamboot_toolkit — shared Python infrastructure for the lamboot-tools suite.

This is the Python analogue of ``lib/lamboot-toolkit-lib.sh``: the contracts the
toolkit owns (the toolkit JSON output schema v1) expressed once, for every
Python tool in the suite to share.

Canonical home: ``lamboot-tools-dev/tools/lamboot_toolkit/``. Toolkit-native
Python tools (``lamboot-nvram`` and onward) import from here. ``lamboot-inspect``
— which straddles the bootloader/toolkit boundary because it *reads* lamboot-dev
owned formats — carries a vendored copy on its side, kept in sync.

Modules:
  * ``exitcodes`` — the shared 8-code exit table (SPEC-LAMBOOT-TOOLKIT-V1 §6)
  * ``envelope``  — the JSON envelope, byte-compatible with the bash ``emit_json``
  * ``registry``  — the subcommand help registry (the ``register_subcommand``
                    record format) + the ``--dump-registry`` serializer
"""
from __future__ import annotations

__all__ = ["envelope", "registry", "exitcodes", "__version__"]

# Tracks the toolkit version for the infra layer; the unified toolkit version is
# resolved at runtime via envelope._toolkit_version().
__version__ = "0.9.1"
