"""lamboot-nvram — UEFI NVRAM (Boot####) hygiene.

A toolkit-native Python tool (it operates on the UEFI-spec NVRAM surface, owned
by no one — like lamboot-esp/lamboot-doctor/lamboot-migrate, not mirrored from
lamboot-dev). Inventories and selectively cleans stale boot entries — dangling,
duplicate, dead-OS, orphan-BootOrder — live (efibootmgr) or offline against a
stopped VM's efidisk (--efidisk, via virt-fw-vars).
"""
from __future__ import annotations

__version__ = "0.1.0"
