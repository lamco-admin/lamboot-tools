Name:           lamboot-tools
Version:        0.3.0
Release:        1%{?dist}
Summary:        The Linux UEFI boot toolkit — diagnose, repair, migrate
License:        MIT OR Apache-2.0
URL:            https://lamboot.dev/tools/
Source0:        https://github.com/lamco-admin/%{name}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildArch:      noarch

# Build-time only (for man page generation + tests, not installed)
BuildRequires:  make
BuildRequires:  bash
BuildRequires:  sed
BuildRequires:  coreutils
BuildRequires:  findutils
BuildRequires:  pandoc
BuildRequires:  bats
BuildRequires:  jq

# Runtime deps — base toolkit function
Requires:       bash >= 4.0
Requires:       util-linux
Requires:       coreutils
Requires:       findutils
Requires:       gawk
Requires:       sed
Requires:       efibootmgr
Requires:       dosfstools

# Optional runtime deps per-tool (documented; not forced)
Recommends:     gdisk
Recommends:     jq
Recommends:     rsync
Recommends:     file

# Optional deps for specific tools
Suggests:       qemu-img
Suggests:       mokutil
Suggests:       sbsigntools
Suggests:       virt-firmware
Suggests:       systemd-ukify

%description
lamboot-tools is a comprehensive CLI suite for diagnosing, repairing,
migrating, and maintaining UEFI boot configurations on Linux systems.

Core tools:

  lamboot-diagnose      Generic UEFI boot-chain scanner (flagship)
  lamboot-esp           ESP health, inventory, stale-file cleanup
  lamboot-backup        UEFI boot config snapshot/restore/show/list
  lamboot-repair        Online + offline boot repair
  lamboot-migrate       Automated BIOS→UEFI + cross-bootloader migration
  lamboot-doctor        Guided diagnose→repair→verify wrapper
  lamboot-uki-build     Unified Kernel Image builder
  lamboot-signing-keys  Secure Boot key lifecycle management
  lamboot-toolkit       Suite dispatcher
  lamboot-inspect       LamBoot-specific deep introspection (Python)

Every tool emits structured JSON conforming to a stable schema v1. Every
finding at warning severity or above includes a machine-readable
remediation command and documentation URL.

Works on any Linux UEFI system regardless of installed bootloader.
Treats GRUB, systemd-boot, rEFInd, Limine, and LamBoot as first-class
peers.

Built by the authors of LamBoot.

# ─────────────────────────────────────────────────────────────────────────
# Subpackage: lamboot-migrate — standalone BIOS→UEFI migration tool
# (Dual-published per R22; also available as independent RPM via
#  packaging/rpm/lamboot-migrate-standalone.spec for users who want
#  just the migration tool with no toolkit dependency.)
# ─────────────────────────────────────────────────────────────────────────
%package -n lamboot-migrate
Summary:        Automated Linux BIOS→UEFI migration tool
License:        MIT OR Apache-2.0
Requires:       bash >= 4.0
Requires:       gdisk
Requires:       dosfstools
Requires:       efibootmgr
Requires:       util-linux
Requires:       rsync

%description -n lamboot-migrate
lamboot-migrate is the first automated Linux BIOS→UEFI migration tool.
Converts MBR → GPT, creates an ESP, installs a UEFI-capable bootloader,
rewrites fstab, creates NVRAM boot entries, and verifies the result.
Seven preflight safety guardrails refuse unsafe migrations (hybrid MBR,
Windows dual-boot, LVM/dm-crypt root, etc.).

This subpackage exists for users who want just the migration tool.
The complete lamboot-tools package provides additional diagnostic and
repair utilities.

# ─────────────────────────────────────────────────────────────────────────
# Subpackage: lamboot-toolkit-pve — Proxmox VE host-side companion
# Installed only on Proxmox hosts. Source lives in the same dev repo
# (pve/ subtree); built from the same source tarball as core.
# Versions in lockstep with core (per §8.3).
# ─────────────────────────────────────────────────────────────────────────
%package -n lamboot-toolkit-pve
Summary:        Proxmox VE host-side companion to lamboot-tools
License:        MIT OR Apache-2.0
Requires:       lamboot-tools = %{version}-%{release}
Requires:       bash >= 4.0
Requires:       coreutils
Requires:       util-linux
Requires:       python3 >= 3.9
Recommends:     jq
Suggests:       virt-firmware

%description -n lamboot-toolkit-pve
lamboot-toolkit-pve is the Proxmox VE host-side companion to
lamboot-tools. Four tools for fleet-wide LamBoot integration on
Proxmox hosts:

  lamboot-pve-setup        Per-VM LamBoot integration setup
                           (fw_cfg args + hookscript + per-VM JSON)
  lamboot-pve-fleet        Fleet-wide inventory / setup / status / report
  lamboot-pve-monitor      Host-side NVRAM health reader for LamBoot VMs
  lamboot-pve-ovmf-vars    OVMF variables builder with cert pre-enrollment

Reads /etc/lamboot/fleet.toml (shared config with lamboot-dev's
hookscript).

Requires lamboot-tools (this package version) on the same host for the
shared library. Requires lamboot-dev >= 0.8.4 for the fw_cfg
file-reference-pattern hookscript; lamboot-pve-setup will emit a
remediation hint if an older hookscript is detected.

Intended for Proxmox VE host installation only. Not useful outside a
Proxmox environment.

%prep
%autosetup

%build
# Build the inlined forms (self-contained single-file binaries suitable
# for rescue-media and for users who prefer one-file portability).
make build-inlined

# Regenerate man pages from help registries (single-source-of-truth)
make man

%install
# Install the sourced form (depends on shared library from this package)
%make_install PREFIX=%{_prefix} \
              BINDIR=%{_bindir} \
              LIBDIR=%{_prefix}/lib/lamboot-tools \
              MANDIR=%{_mandir} \
              DOCDIR=%{_docdir}/%{name}

# Install PVE subtree (same make target covers both)
%make_install install-pve \
              PREFIX=%{_prefix} \
              BINDIR=%{_bindir} \
              MANDIR=%{_mandir} \
              DOCDIR=%{_docdir}/lamboot-toolkit-pve

# Strip +x from shared library files installed to LIBDIR
chmod 0644 %{buildroot}%{_prefix}/lib/lamboot-tools/*.sh

# The Makefile install target places LICENSE-*, README.md, CHANGELOG.md into
# DOCDIR so that non-RPM consumers (make install PREFIX=/usr/local) get them.
# Under rpmbuild we use %%license and %%doc directives below to place them at
# /usr/share/licenses/<pkg> and /usr/share/doc/<pkg> correctly — so remove
# the Makefile-placed copies to avoid "installed but unpackaged" errors.
rm -f %{buildroot}%{_docdir}/%{name}/LICENSE-MIT
rm -f %{buildroot}%{_docdir}/%{name}/LICENSE-APACHE
rm -f %{buildroot}%{_docdir}/%{name}/README.md
rm -f %{buildroot}%{_docdir}/%{name}/CHANGELOG.md
rm -f %{buildroot}%{_docdir}/lamboot-toolkit-pve/LICENSE-MIT
rm -f %{buildroot}%{_docdir}/lamboot-toolkit-pve/LICENSE-APACHE
rm -f %{buildroot}%{_docdir}/lamboot-toolkit-pve/README.md
rm -f %{buildroot}%{_docdir}/lamboot-toolkit-pve/CHANGELOG.md

%check
# Run shellcheck against every bash source
if command -v shellcheck >/dev/null 2>&1; then
    make lint
fi

# Run the fast bats-core suite (skip integration tests — they need fixtures)
if command -v bats >/dev/null 2>&1; then
    make test
    bats pve/tests/*.bats || true
fi

# Verify claims appendix
./scripts/verify-claims.sh

%files
%license LICENSE-MIT LICENSE-APACHE
%doc README.md CHANGELOG.md docs/SPEC-LAMBOOT-TOOLKIT-V1.md

# Core tools (excluding lamboot-migrate — split into its own subpackage)
%{_bindir}/lamboot-diagnose
%{_bindir}/lamboot-esp
%{_bindir}/lamboot-backup
%{_bindir}/lamboot-repair
%{_bindir}/lamboot-doctor
%{_bindir}/lamboot-toolkit
%{_bindir}/lamboot-uki-build
%{_bindir}/lamboot-signing-keys

# Python mirrored tool (installed if present from release-build mirror).
# The script lives in LIBDIR so its sibling lamboot_inspect/ package is
# found by the Python _bootstrap() via dirname(realpath(__file__)).
# /usr/bin/lamboot-inspect is a symlink to the real script.
%{_bindir}/lamboot-inspect
%{_prefix}/lib/lamboot-tools/lamboot-inspect
%{_prefix}/lib/lamboot-tools/lamboot_inspect/

# Shared library
%dir %{_prefix}/lib/lamboot-tools
%{_prefix}/lib/lamboot-tools/lamboot-toolkit-lib.sh
%{_prefix}/lib/lamboot-tools/lamboot-toolkit-help.sh
# esp-deploy.sh is mirrored from lamboot-dev/lib/ at release-build time
# (see publish/mirror-from-lamboot-dev.sh). It encodes the canonical ESP
# file-layout knowledge consumed by lamboot-esp's offline-deploy action.
%{_prefix}/lib/lamboot-tools/esp-deploy.sh
# _nvram_set_first_boot.py bridges to virt.firmware's Python API to
# reorder BootOrder (the virt-fw-vars CLI does not expose this).
# Used by lamboot-repair's repair.nvram.set_first action.
%{_prefix}/lib/lamboot-tools/_nvram_set_first_boot.py

# Man pages
%{_mandir}/man1/lamboot-diagnose.1*
%{_mandir}/man1/lamboot-esp.1*
%{_mandir}/man1/lamboot-backup.1*
%{_mandir}/man1/lamboot-repair.1*
%{_mandir}/man1/lamboot-doctor.1*
%{_mandir}/man1/lamboot-toolkit.1*
%{_mandir}/man1/lamboot-uki-build.1*
%{_mandir}/man1/lamboot-signing-keys.1*
%{_mandir}/man1/lamboot-inspect.1*
%{_mandir}/man5/lamboot-tools-schema.5*
%{_mandir}/man7/lamboot-tools.7*

%files -n lamboot-migrate
%license LICENSE-MIT LICENSE-APACHE
%doc README.md
%{_bindir}/lamboot-migrate
%{_mandir}/man1/lamboot-migrate.1*

%files -n lamboot-toolkit-pve
%license LICENSE-MIT LICENSE-APACHE
%doc pve/README.md pve/docs/SPEC-LAMBOOT-PVE-SETUP.md pve/docs/SPEC-LAMBOOT-PVE-FLEET.md

%{_bindir}/lamboot-pve-setup
%{_bindir}/lamboot-pve-fleet
%{_bindir}/lamboot-pve-monitor
%{_bindir}/lamboot-pve-ovmf-vars

%{_mandir}/man1/lamboot-pve-setup.1*
%{_mandir}/man1/lamboot-pve-fleet.1*

%post -n lamboot-toolkit-pve
cat <<EOF

lamboot-toolkit-pve installed.

Next steps:
  1. Verify lamboot-dev >= 0.8.4 is installed (hookscript required):
       lamboot-pve-setup doctor-hookscript
  2. Create /etc/lamboot/fleet.toml — see:
       man lamboot-pve-setup
       https://lamboot.dev/tools/guides/proxmox-fleet-setup
  3. Run initial inventory:
       lamboot-pve-fleet inventory

EOF
exit 0

%changelog
* Wed Apr 22 2026 Lamco Development <office@lamco.io> - 0.2.0-1
- Initial Fedora Copr release
- Core toolkit with 9 shared-library tools
- lamboot-migrate as separate subpackage for users who want just migration
- lamboot-toolkit-pve subpackage for Proxmox VE hosts (4 tools)
- Three-surface documentation (inline help, man pages, website)
