# SPEC-LAMBOOT-SIGNING-KEYS: Secure Boot Key Lifecycle Tool

**Version:** 1.0 (tool v0.2 target; maturity: **experimental** at v0.2)
**Date:** 2026-04-22
**Status:** Ready for implementation review
**Parent spec:** `SPEC-LAMBOOT-TOOLKIT-V1.md` §3.1 entry for `lamboot-signing-keys`
**Existing implementation:** NEW — introduced in Session J
**Related source-of-truth:** `~/lamboot-dev/docs/KEY-GENERATION.md`, `~/lamboot-dev/docs/SECURE-BOOT-AND-SIGNING-STRATEGY.md`, `~/lamboot-dev/docs/MOK-ENROLLMENT-GUIDE.md`, `~/lamboot-dev/docs/OVMF-VARS-PROXMOX.md`

---

## 1. Overview

`lamboot-signing-keys` is a **dual-mode** Secure Boot key lifecycle helper. Per founder direction (Session A Q1 = Scope 3), it covers both:

- **Scope 1 — Release engineering**: Manage a project's own PK/KEK/db keys for signing releases (the use case currently handled by `sign-lamboot.sh` + `KEY-GENERATION.md`). Target user: release engineers.
- **Scope 2 — User-facing**: Help Linux admins generate, enroll, rotate, and inspect their own Secure Boot keys. Target user: any Linux admin with SB-enabled hardware.

Both modes share the underlying OpenSSL/mokutil/sbsigntool machinery. Mode selection is implicit (based on subcommand) or explicit (`--mode release-eng|user`).

### 1.1 What this tool does

**All modes:**
- `generate` — generate a new keypair + cert per UEFI convention (RSA-2048 for db by default)
- `inspect KEYFILE` — display cert subject, issuer, validity, key size, algorithm, EKU
- `status` — show current Secure Boot state, enrolled MOK certs, setup mode

**User mode (Scope 2):**
- `mok-enroll CERT` — wrap `mokutil --import` + enrollment password flow
- `mok-list` — wrap `mokutil --list-enrolled`
- `mok-delete CERT` — wrap `mokutil --delete`
- `ovmf-vars OUTPUT.fd --cert CERT` — embed cert in OVMF_VARS.fd for VM pre-enrollment (wraps `virt-fw-vars`)

**Release-eng mode (Scope 1):**
- `generate-hierarchy` — generate full PK/KEK/db hierarchy per `KEY-GENERATION.md` §3
- `sign-binary BINARY --key --cert` — signs a binary with SBAT metadata (wraps sbsign)
- `rotate db|kek|pk` — rotate a keypair, cross-signing the new cert with the parent key (db←KEK, KEK←PK, PK←self)

### 1.2 What this tool does NOT do

- Write firmware variables directly except via `mokutil`/`virt-fw-vars` (safety: never touch efivars raw)
- Generate Microsoft-signed shim binaries (that's `rhboot/shim-review`; release-eng track only)
- Host HSM integration (v0.5+ target)
- Auto-enroll certs without user consent (always prompts)

### 1.3 Constraints

- **RSA-2048 enforcement for db and MOK-enrolled keys** per Debian bug #1013320 (RSA 4096 freezes shim). Tool **refuses** to generate RSA 4096 for any key that might go through shim/MOK. User can override with `--force-4096` at their own risk.
- **PK and KEK allowed RSA 4096** (they operate in firmware variable space, not shim path).
- Generate subcommand requires `openssl` (ubiquitous; always available).
- MOK operations require `mokutil` (present on Debian/Ubuntu/Fedora; may be absent on Arch).
- Root required for MOK import and OVMF vars write.

---

## 2. CLI interface

```
lamboot-signing-keys [GLOBAL FLAGS] SUBCOMMAND [ARGS]

Shared subcommands:
    generate [--type db|kek|pk] [--size 2048|4096] [--cn NAME] [--days N] [--output PREFIX]
    inspect KEYFILE_OR_CERT
    status
    help [<sub>]

User-mode subcommands:
    mok-enroll CERT                     Stage MOK enrollment (wraps mokutil --import)
    mok-list                            List MOK-enrolled certs
    mok-delete CERT                     Stage MOK deletion
    ovmf-vars OUTPUT.fd --cert CERT     Build OVMF_VARS with cert pre-enrolled

Release-eng subcommands:
    generate-hierarchy [--output-dir DIR]   Generate PK + KEK + db per KEY-GENERATION.md
    sign-binary BINARY --key --cert         Sign with SBAT metadata (wraps sbsign)
    rotate TYPE --old-key K --old-cert C [--parent-key K --parent-cert C] [--new-cn NAME]
                                            Rotate db/kek/pk key with cross-sign

Tool-specific options:
    --mode MODE              user | release-eng (auto-detected by subcommand)
    --force-4096             Override RSA-2048 constraint (dangerous)
    --passphrase SOURCE      env:VAR, file:PATH, or prompt (default: prompt)
```

### 2.1 Exit codes

Standard toolkit codes from spec §4.4:
- **0** success
- **1** error
- **2** partial (e.g., generate succeeded but inspect follow-up failed)
- **3** noop
- **4** unsafe (e.g., refused RSA 4096 without `--force-4096`)
- **5** user aborted
- **7** prerequisite missing (openssl, mokutil, sbsign, virt-fw-vars)

---

## 3. Subcommand specifications

### 3.1 `generate`

```
lamboot-signing-keys generate --type db --cn "My Custom db Key 2026"
```

Produces:
- `db.key` (PEM-encoded, AES-256-CBC encrypted, prompting for passphrase)
- `db.crt` (X.509 PEM, self-signed)
- `db.der` (X.509 DER, for firmware enrollment)

Default: RSA-2048, SHA-256, 1095 days (3 years) for db; 3650 days (10 years) for PK/KEK.

Refuses RSA 4096 for `--type db` unless `--force-4096` is set:
```
error: RSA 4096 for db keys breaks shim MOK verification (Debian #1013320)
hint: use --size 2048 (default); RSA 4096 is safe for --type pk and --type kek
```

### 3.2 `inspect`

Works on `.key`, `.crt`, `.der`, or `.pem` files. Emits findings:

```
keys.inspect.subject: CN=LamBoot Release Signing Key 2026, O=Lamco Development
keys.inspect.issuer: (same as subject for self-signed)
keys.inspect.algorithm: sha256WithRSAEncryption
keys.inspect.key_size: 2048
keys.inspect.not_before: 2026-04-22
keys.inspect.not_after: 2029-04-21
keys.inspect.eku: codeSigning (for db leaf)
keys.inspect.ca: CA:FALSE (for db leaf) | CA:TRUE (for PK/KEK)
```

Warns if:
- Key is RSA 4096 AND is a leaf/codeSigning cert (MOK hazard)
- Cert is expired or expires within 90 days
- CA flag is inconsistent with the key role

### 3.3 `status`

Reports current Secure Boot posture:

```
  Secure Boot: enabled
  Setup Mode:  false
  Audit Mode:  false
  Vendor:      tianocore (read from firmware strings)

  PK:  1 cert enrolled
  KEK: 2 certs enrolled
  db:  3 certs (Microsoft + distro + custom)
  dbx: 1247 revocations

  MOK enrolled:
    - Subject: CN=..., SHA256: abc123...
    - ...
```

### 3.4 `mok-enroll CERT`

Interactive flow (user consent REQUIRED):

1. Validate cert is readable, RSA ≤ 2048 (refuses RSA 4096 without `--force-4096`)
2. Show cert details
3. Prompt for enrollment password (will be required in MokManager UI)
4. Run `mokutil --import CERT`
5. Emit `keys.mok.enrolled` finding with reboot instruction
6. Record action

### 3.5 `mok-list`

Wraps `mokutil --list-enrolled`. Emits one finding per enrolled cert with subject + SHA1 fingerprint.

### 3.6 `mok-delete CERT`

Reverse of mok-enroll. Stages `mokutil --delete`; requires reboot.

### 3.7 `ovmf-vars OUTPUT.fd --cert CERT`

Wraps `virt-fw-vars` to embed a cert in an OVMF variable store. Matches the `build-ovmf-vars.sh` in `lamboot-dev/tools/` and the process documented in `OVMF-VARS-PROXMOX.md`.

Used by release-eng for pre-enrolled VM templates, or by user for their own VMs.

### 3.8 `generate-hierarchy` (release-eng only)

Generates the full PK → KEK → db hierarchy per `KEY-GENERATION.md` §3:
- PK: RSA 4096, `CA:TRUE`, 10 years, CN=`<project> Platform Key`
- KEK: RSA 4096, `CA:TRUE`, 10 years, CN=`<project> Key Exchange Key`
- db: RSA 2048, `CA:FALSE`, `codeSigning` EKU, 3 years, CN=`<project> Release Signing Key <year>`

Writes to `--output-dir` (default: `./keys-gen/`). Prompts for three distinct passphrases.

### 3.9 `sign-binary` (release-eng only)

Wraps `sbsign` with SBAT-aware signing:

```
lamboot-signing-keys sign-binary dist/EFI/LamBoot/lambootx64.efi \
    --key keys/db.key --cert keys/db.crt
```

Adds `.sbat` PE section if not present, then runs `sbsign`.

### 3.10 `rotate TYPE`

Rotate a db/kek/pk keypair, emitting a timestamped rotation directory with
both old and new keypairs + a JSON manifest describing the transition. When
a `--parent-key` / `--parent-cert` pair is supplied, the new cert is
cross-signed by the parent (db by KEK, KEK by PK). Without parent credentials,
the new cert is self-signed and a `keys.rotate.manual_cross_sign_required`
warning is emitted pointing at the manual `openssl x509 -req` one-liner.

Flow:

1. Validate old-key ↔ old-cert public-key match (sha256 of RSA public bits).
2. Validate parent-key ↔ parent-cert match (when provided).
3. Generate new keypair with the type's default RSA size (db=2048, kek=4096, pk=4096).
4. Build OpenSSL config preserving keyUsage / basicConstraints / EKU per type.
5. Either (a) issue CSR → sign-with-parent, or (b) self-sign.
6. Write `<type>.old.{key,crt,der}`, `<type>.new.{key,crt,der}`, and
   `rotation.json` into the output directory (mode 0700; keys 0600).
7. Emit `keys.rotate.complete` finding with a `re_enroll` remediation
   command specific to the key type:
   - db: `mokutil --import <type>.new.der`
   - KEK: `lamboot-signing-keys ovmf-vars …` for VM template redistribution
   - PK: manual firmware-level update with physical-presence confirmation

Both old and new keys remain valid for signing during the transition window.
Stragglers can be re-signed with either; emergency rollback restores the old.

---

## 4. Safety defaults

- Passphrase never echoed; never written to shell history
- Private keys created mode 0600; parent dir mode 0700
- Refuse to overwrite existing `.key` files without `--force`
- Every write action goes through `record_action` for audit
- Refuse RSA 4096 for MOK-bound keys without explicit `--force-4096`

---

## 5. Test plan

### 5.1 Unit tests (bats)

- `tests/signing-keys-cli.bats` — CLI surface, help, JSON schema, prerequisite detection
- `tests/signing-keys-generate.bats` — generate succeeds with default RSA-2048; refuses RSA-4096 for db; inspect of generated cert shows expected fields

### 5.2 Integration tests (self-contained)

- Generate a db cert in a tmp dir → inspect → verify RSA-2048 + codeSigning EKU
- `--force-4096 --type db` → produces RSA 4096 (emits warning finding)
- Generate PK key without `--force-4096` at RSA 4096 → succeeds (no warning; PK is SB-safe at 4096)

### 5.3 Fleet matrix

Tier 1 distros: `status` subcommand run on each; verify clean enumeration of enrolled certs and SB state.

---

## 6. Acceptance criteria

- [ ] Sources shared lib + help registry
- [ ] Unified JSON schema v1 on all subcommands
- [ ] RSA-2048 default for db/leaf keys; refuses 4096 without `--force-4096`
- [ ] RSA-4096 allowed for PK/KEK (firmware-level keys)
- [ ] `inspect` parses `.key`, `.crt`, `.der`, `.pem` via openssl
- [ ] `generate` writes private key 0600, cert 0644
- [ ] MOK operations wrapped correctly (mokutil)
- [ ] OVMF vars via virt-fw-vars
- [ ] Every warning+ finding has remediation
- [ ] bats tests pass
- [ ] Shellcheck clean
- [ ] Maturity: **experimental** at v0.2; **beta** at v0.3; **stable** at v0.5

---

## 7. Deferred to v0.3+ / v0.5+

- **v0.3:** `rotate kek`, `rotate pk` subcommands
- **v0.3:** `sign-binary` SBAT section injection (currently wraps sbsign only)
- **v0.3:** Automated SBAT generation increment on security release
- **v0.5:** HSM-backed signing (YubiHSM 2, cloud KMS)
- **v0.5:** `mok-enrollment-wizard` interactive full-flow helper for new users
- **v0.5:** `export-for-firmware` subcommand producing firmware-setup-friendly auth files
- **v1.0:** Microsoft UEFI CA 2023 transition support
- **v1.0:** `shim-review-prep` subcommand aggregating the metadata required for rhboot/shim-review submission
