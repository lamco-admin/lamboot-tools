# SPEC-LAMBOOT-UKI-BUILD: Host-Side Unified Kernel Image Builder

**Version:** 1.0 (tool v0.2 target; maturity: **beta** at v0.2)
**Date:** 2026-04-22
**Status:** Ready for implementation review
**Parent spec:** `SPEC-LAMBOOT-TOOLKIT-V1.md` §3.1 entry for `lamboot-uki-build`
**Existing implementation:** NEW — introduced in Session I

---

## 1. Overview

`lamboot-uki-build` wraps the UKI build ecosystem (`ukify`, `dracut`, `objcopy`) in a single command with consistent flags and unified JSON output. UKIs are the industry-direction for trusted boot; this tool makes building them uniform across distros.

**The tool is bootloader-agnostic.** Built UKIs conform to the [UAPI.5 UKI Specification](https://uapi-group.org/specifications/specs/unified_kernel_image/) and work with systemd-boot, LamBoot, any firmware-direct boot, and any other UKI-aware bootloader.

### 1.1 What this tool does

- **`build`** — compose a UKI from a kernel + initrd + cmdline + optional splash/dtb/.profile/osrel sections
- **`inspect`** — parse an existing UKI's PE sections and emit their contents (reuses logic from `SPEC-UKI-PE-PARSER` at a high level, from a host-side perspective)
- **`sign`** — sign a UKI with `sbsign` for Secure Boot enrollment
- **`verify`** — verify a UKI's signature against a known cert

### 1.2 What this tool does NOT do

- Generate its own initrd (delegates to `dracut` or a pre-built initrd argument)
- Manage signing keys (that's `lamboot-signing-keys`)
- Install UKIs to the ESP (copy manually; or use `dracut --uefi --install`)
- Modify kernel command-line permanently (cmdline is embedded at build time)

### 1.3 Constraints

- Wraps existing tools — does NOT reimplement `ukify`/`objcopy`/`sbsign`
- Unprivileged for `inspect` and `verify`; `build` + `sign` may require root depending on source paths
- Supports `ukify` (preferred, modern) and raw `objcopy` (fallback, for older systems)

---

## 2. CLI interface

```
lamboot-uki-build [GLOBAL FLAGS] SUBCOMMAND [ARGS]

Subcommands:
    build OUTPUT.efi    Compose a UKI
    inspect UKI.efi     Parse and display an existing UKI's sections
    sign UKI.efi        Sign a UKI with sbsign
    verify UKI.efi      Verify a UKI's signature
    help [<sub>]

build options:
    --kernel PATH          Source kernel vmlinuz (required)
    --initrd PATH          Source initrd (repeatable for multi-initrd concat)
    --cmdline STR          Kernel command line to embed (default: empty)
    --osrel PATH           os-release file path (default: /etc/os-release)
    --uname STR            Kernel version string for .uname (default: extract from --kernel)
    --splash PATH          BMP splash image (optional)
    --dtb PATH             Device tree blob (optional, for ARM)
    --stub PATH            EFI stub binary (default: auto-detect systemd-stub)
    --profile ID=TITLE     Multi-profile UKI (repeatable)
    --backend ukify|objcopy  Choose build backend (default: ukify if available, else objcopy)

sign options:
    --key PATH             Signing private key (required)
    --cert PATH            Signing certificate (required)
    --output PATH          Output signed file (default: overwrite input)

verify options:
    --cert PATH            Certificate to verify against (required)
```

### 2.1 Exit codes

- **0** success
- **1** build/inspect/sign/verify error
- **3** nothing to do (e.g., `inspect` of empty file)
- **5** user declined confirmation
- **7** prerequisite missing (ukify, sbsign, objcopy)

---

## 3. Build flow

1. Validate inputs: kernel exists + is PE32+ or raw kernel image; initrd exists; cmdline is a valid ASCII string; output path is writable
2. Choose backend:
    - If `ukify` is available: `ukify build --linux=<kernel> --initrd=<initrd> --cmdline=<cmdline> --os-release=@<osrel> [--splash=<splash>] [--dtb=<dtb>] --output=<output>`
    - Else if `objcopy` is available: manual section composition via `objcopy --add-section .osrel=<osrel> .cmdline=<cmdline-file> .linux=<kernel> .initrd=<initrd-concat> [--splash=<splash>] --set-section-flags .xxx=data,readonly <stub> <output>`
3. Emit `ukibuild.output.created` finding with path + size + section count
4. Record action `uki.build.compose`

### 3.1 Section selection

UKI sections composed per UAPI.5:
- `.osrel` — contents of `--osrel` file
- `.cmdline` — `--cmdline` value
- `.linux` — contents of `--kernel`
- `.initrd` — concatenation of all `--initrd` arguments
- `.uname` — `--uname` or extracted via `file` from kernel
- `.splash` — optional
- `.dtb` — optional
- `.profile` — one per `--profile ID=TITLE`

Section measurement order (for TPM PCR 11 pre-calculation, reference only; not computed at build time in v0.2):
`.linux, .osrel, .cmdline, .initrd, .ucode, .splash, .dtb, .dtbauto, .hwids, .uname, .sbat`

---

## 4. Inspect flow

1. Read first ~4 KB to parse DOS + PE + COFF headers
2. Enumerate section table; match against known UKI section names
3. For each found section: print name + size + offset; extract text content for `.osrel`/`.cmdline`/`.uname`
4. Emit one finding per discovered section: `ukibuild.inspect.section.<name>` with size/offset/content preview

### 4.1 PE parsing

Follows `~/lamboot-dev/docs/specs/SPEC-UKI-PE-PARSER.md` algorithm:
- DOS header `MZ` at offset 0
- `e_lfanew` at offset 0x3C → PE offset
- PE signature `PE\0\0` at PE offset
- COFF header 20 bytes after PE signature
- `SizeOfOptionalHeader` at COFF+16 → skip to section table
- Each `IMAGE_SECTION_HEADER` is 40 bytes: Name[8], VirtualSize, VirtualAddress, SizeOfRawData, PointerToRawData, reloc/line fields

Implementation uses `od` + shell arithmetic — NO external PE parser dependency.

---

## 5. Sign flow

1. Verify `sbsign` is available (prerequisite check)
2. Verify `--key` + `--cert` exist and are readable
3. Run `sbsign --key=<key> --cert=<cert> --output=<output> <input>`
4. Emit finding `ukibuild.sign.complete` with cert subject + output path
5. Record `uki.sign.signed` action

### 5.1 Sign output

Default: overwrite input file (`--output` defaults to input path). Signed UKI is PE32+ with embedded authenticode signature.

Signed UKIs verify against the cert via either `sbverify` or any UEFI Secure Boot chain that trusts the cert (db/MOK).

---

## 6. Verify flow

1. Verify `sbverify` is available (prerequisite)
2. Run `sbverify --cert=<cert> <input>`
3. Parse output; emit `ukibuild.verify.result` finding with pass/fail status

---

## 7. Test plan

### 7.1 Unit tests (bats)

- `tests/uki-build-cli.bats` — CLI parsing, help, JSON schema, prerequisite detection
- `tests/uki-build-inspect.bats` — PE header parse on a known-good UKI (if `/boot/efi/EFI/Linux/*.efi` exists)

### 7.2 Integration tests

- Build a UKI from `/boot/vmlinuz-*` + `/boot/initrd.img-*` → inspect → verify all expected sections present
- Sign with a test cert → verify with same cert → exit 0
- Verify with wrong cert → exit 1

### 7.3 Fleet matrix

Tier 1 VMs with systemd-stub available: build + inspect round-trip. Skipped on VMs without ukify or systemd-stub.

---

## 8. Acceptance criteria

- [ ] Sources shared lib + help registry
- [ ] Unified JSON schema v1 on all subcommands
- [ ] `build` supports both ukify + objcopy backends with automatic selection
- [ ] `inspect` parses PE headers without external dependency (pure bash + od)
- [ ] `sign` and `verify` wrap sbsign/sbverify correctly
- [ ] Every warning+ finding has remediation URL
- [ ] bats tests pass
- [ ] Shellcheck clean
- [ ] Maturity: **beta** at v0.2; promote to **stable** at v0.3 after field validation

---

## 9. Deferred to v0.3+

- TPM PCR 11 pre-calculation (for measured-boot attestation setup)
- Multi-profile UKI build (`--profile` accepted but not fully composed in v0.2)
- Incremental rebuild (skip if inputs unchanged since last build)
- `install` subcommand copying to `EFI/Linux/` with bootloader-correct naming
- Cross-architecture builds (aarch64 UKI from x86_64 host)
- SBAT metadata injection
- Systemd-ukify profile-file format import (for batch builds via `ukify build --config=`)
