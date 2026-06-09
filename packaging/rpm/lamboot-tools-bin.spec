Name:           lamboot-tools
Version:        0.8.0
Release:        1%{?dist}
Summary:        Linux UEFI boot toolkit: diagnose, repair, migrate

License:        MIT OR Apache-2.0
URL:            https://lamco.ai/products/lamboot-tools/

# Prebuilt-repackage model (apt.lamco.ai / OBS prebuilt parity; see
# ../PACKAGING.md §7). Source0 is the PUBLISHED RELEASE TARBALL, which already
# carries the shell suite AND the vendored static-musl component binaries under
# vendor/bin/<arch>/. This spec does NOT compile anything and does NOT run the
# suite's Makefile build: it installs the already-built tools and the
# arch-matching binaries straight from the tarball. The build-from-source Copr
# spec is the sibling lamboot-tools.spec; this one is for repackaging the
# release artifact where building from source is not wanted.
#
# The checksum of Source0 is verified by the publish pipeline, not committed.
Source0:        https://github.com/lamco-admin/%{name}/releases/download/v%{version}/%{name}-%{version}.tar.gz

# The vendored binaries are already-stripped static-musl with no usable
# debuginfo; disable the debuginfo subpackage so rpmbuild does not try to
# extract build-ids from them and fail.
%global debug_package %{nil}

# Do NOT let rpmbuild's BRP scripts re-strip the vendored binaries. They are
# already stripped, and re-stripping rewrites the bytes (breaking the
# BuildID/sha256 recorded in vendor/BINARY-PROVENANCE.txt and any detached
# verification of the audited upstream binary). debug_package %%{nil} only drops
# the debuginfo SUBPACKAGE; the strip BRPs still run unless neutralised here.
%global __strip /bin/true
%global __brp_strip %{nil}
%global __brp_strip_static_archive %{nil}
%global __brp_strip_comment_note %{nil}

# Arch model: the lamboot-tools-firmware subpackage ships prebuilt x86_64 /
# aarch64 binaries, so it is arch-specific. RPM forbids an arch subpackage under
# a BuildArch: noarch main package, so the main package is arch-tagged even
# though its own payload is pure shell. The pure-shell lamboot-migrate and
# lamboot-toolkit-pve subpackages stay BuildArch: noarch.

# Runtime deps — base toolkit function
Requires:       bash >= 4.0
Requires:       util-linux
Requires:       coreutils
Requires:       findutils
Requires:       gawk
Requires:       sed
Requires:       efibootmgr
Requires:       dosfstools
# lamboot-inspect is Python.
Requires:       python3

# Optional runtime deps per-tool (documented; not forced)
Recommends:     gdisk
Recommends:     jq
Recommends:     rsync
Recommends:     file

# Bundled Rust component binaries. Weak dependency: dnf pulls it in by default
# on supported arches, but the suite functions without it (lamboot-doctor /
# lamboot-migrate degrade gracefully).
Recommends:     lamboot-tools-firmware = %{version}-%{release}

Suggests:       qemu-img
Suggests:       mokutil
Suggests:       sbsigntools
Suggests:       systemd-ukify

%description
lamboot-tools is a CLI suite for diagnosing, repairing, migrating, and
maintaining UEFI boot configurations on Linux. It treats GRUB, systemd-boot,
rEFInd, Limine, and LamBoot as first-class peers and works on any UEFI system
regardless of the installed bootloader.

Core tools: lamboot-diagnose (boot-chain scanner), lamboot-esp (ESP health),
lamboot-backup (boot-config snapshot/restore), lamboot-repair (online and
offline repair), lamboot-doctor (guided diagnose-repair-verify),
lamboot-uki-build (Unified Kernel Image builder), lamboot-signing-keys (Secure
Boot key lifecycle), lamboot-toolkit (dispatcher), and lamboot-inspect (LamBoot
deep introspection, Python). Every tool emits structured JSON on a stable
schema.

This package is built by repackaging the published release tarball; it does not
compile from source. Because the release bundles prebuilt component binaries it
is distributed from Lamco's own repositories (Copr / OBS), not Fedora official.

# ─────────────────────────────────────────────────────────────────────────
# Subpackage: lamboot-migrate — standalone BIOS→UEFI migration tool
# ─────────────────────────────────────────────────────────────────────────
%package -n lamboot-migrate
Summary:        Automated Linux BIOS to UEFI migration tool
License:        MIT OR Apache-2.0
BuildArch:      noarch
Requires:       bash >= 4.0
Requires:       gdisk
Requires:       dosfstools
Requires:       efibootmgr
Requires:       util-linux
Requires:       rsync

%description -n lamboot-migrate
lamboot-migrate is an automated Linux BIOS to UEFI migration tool. It converts
MBR to GPT, creates an ESP, installs a UEFI-capable bootloader, rewrites fstab,
creates NVRAM boot entries, and verifies the result. Preflight guardrails refuse
unsafe migrations (hybrid MBR, Windows dual-boot, LVM/dm-crypt root, etc.).

This subpackage exists for users who want just the migration tool.

# ─────────────────────────────────────────────────────────────────────────
# Subpackage: lamboot-toolkit-pve — Proxmox VE host-side companion
# ─────────────────────────────────────────────────────────────────────────
%package -n lamboot-toolkit-pve
Summary:        Proxmox VE host-side companion to lamboot-tools
License:        MIT OR Apache-2.0
BuildArch:      noarch
Requires:       lamboot-tools = %{version}-%{release}
Requires:       bash >= 4.0
Requires:       coreutils
Requires:       util-linux
Requires:       python3 >= 3.9
Recommends:     jq
Suggests:       virt-firmware

%description -n lamboot-toolkit-pve
lamboot-toolkit-pve is the Proxmox VE host-side companion to lamboot-tools.
Tools for fleet-wide LamBoot integration on Proxmox hosts: lamboot-pve-setup
(per-VM setup), lamboot-pve-fleet (fleet inventory/status), lamboot-pve-monitor
(host-side NVRAM health reader), and lamboot-pve-ovmf-vars (OVMF variables
builder with cert pre-enrollment).

Intended for Proxmox VE host installation only.

# ─────────────────────────────────────────────────────────────────────────
# Subpackage: lamboot-tools-firmware — bundled Rust component binaries
# ─────────────────────────────────────────────────────────────────────────
%ifarch x86_64 aarch64
%package -n lamboot-tools-firmware
Summary:        Bundled firmware-audit and GRUB-reader binaries for lamboot-tools
License:        MIT OR Apache-2.0
Requires:       lamboot-tools = %{version}-%{release}

%description -n lamboot-tools-firmware
Prebuilt, statically linked (musl) binaries of the lamboot-tools Rust
components: lamboot-capcheck (firmware and platform capability auditor,
consumed by lamboot-doctor and lamboot-migrate) and lamboot-reader (GRUB
configuration reader and resolver, standalone CLI). Statically linked so a
single binary per arch runs across distributions with no runtime dependency.
THIRD_PARTY_NOTICES for the bundled crate dependencies are installed under the
package license directory.
%endif

%prep
%autosetup -n %{name}-%{version}

%build
# Prebuilt repackage: nothing to compile. The tools, man pages, and the
# vendored binaries are all final in the unpacked tarball.

%install
# Vendor arch directory name matches RPM's %{_arch} (x86_64 / aarch64).
%define _vendor_arch %{_arch}

# --- shared library + python helper -> /usr/lib/lamboot-tools ---
# Literal path: the tools source ${LAMBOOT_LIB_DIR:-/usr/lib/lamboot-tools}.
# Do NOT use %{_libdir} here — on x86_64 that is /usr/lib64 and the tools do not
# look there.
install -d %{buildroot}%{_prefix}/lib/lamboot-tools
install -m 0644 lib/lamboot-toolkit-lib.sh     %{buildroot}%{_prefix}/lib/lamboot-tools/lamboot-toolkit-lib.sh
install -m 0644 lib/lamboot-toolkit-help.sh    %{buildroot}%{_prefix}/lib/lamboot-tools/lamboot-toolkit-help.sh
install -m 0644 lib/esp-deploy.sh              %{buildroot}%{_prefix}/lib/lamboot-tools/esp-deploy.sh
install -m 0644 lib/lamboot-capcheck-bridge.sh %{buildroot}%{_prefix}/lib/lamboot-tools/lamboot-capcheck-bridge.sh
install -m 0755 lib/_nvram_set_first_boot.py   %{buildroot}%{_prefix}/lib/lamboot-tools/_nvram_set_first_boot.py

# --- shell tools -> /usr/bin ---
install -d %{buildroot}%{_bindir}
for t in lamboot-diagnose lamboot-esp lamboot-backup lamboot-repair \
         lamboot-migrate lamboot-doctor lamboot-toolkit lamboot-uki-build \
         lamboot-signing-keys; do
    install -m 0755 tools/$t %{buildroot}%{_bindir}/$t
done

# --- lamboot-inspect: real script + sibling package under /usr/lib/lamboot-tools,
#     PATH symlink so the python _bootstrap() realpath finds lamboot_inspect/ ---
install -m 0755 tools/lamboot-inspect %{buildroot}%{_prefix}/lib/lamboot-tools/lamboot-inspect
cp -a tools/lamboot_inspect %{buildroot}%{_prefix}/lib/lamboot-tools/
find %{buildroot}%{_prefix}/lib/lamboot-tools/lamboot_inspect -type d -exec chmod 0755 {} +
find %{buildroot}%{_prefix}/lib/lamboot-tools/lamboot_inspect -type f -exec chmod 0644 {} +
find %{buildroot}%{_prefix}/lib/lamboot-tools/lamboot_inspect -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
ln -s ../lib/lamboot-tools/lamboot-inspect %{buildroot}%{_bindir}/lamboot-inspect

# --- PVE tools -> /usr/bin (lamboot-toolkit-pve subpackage) ---
for t in lamboot-pve-setup lamboot-pve-fleet lamboot-pve-monitor lamboot-pve-ovmf-vars; do
    [ -f pve/tools/$t ] && install -m 0755 pve/tools/$t %{buildroot}%{_bindir}/$t
done

# --- man pages ---
install -d %{buildroot}%{_mandir}/man1 %{buildroot}%{_mandir}/man5 %{buildroot}%{_mandir}/man7
for m in man/*.1; do
    [ -f "$m" ] || continue
    install -m 0644 "$m" %{buildroot}%{_mandir}/man1/$(basename "$m")
done
[ -f man/lamboot-tools-schema.5 ] && install -m 0644 man/lamboot-tools-schema.5 %{buildroot}%{_mandir}/man5/lamboot-tools-schema.5
[ -f man/lamboot-tools.7 ]        && install -m 0644 man/lamboot-tools.7        %{buildroot}%{_mandir}/man7/lamboot-tools.7

# --- vendored component binaries -> /usr/bin (arch-matching) ---
%ifarch x86_64 aarch64
install -m 0755 vendor/bin/%{_vendor_arch}/lamboot-capcheck %{buildroot}%{_bindir}/lamboot-capcheck
install -m 0755 vendor/bin/%{_vendor_arch}/lamboot-reader   %{buildroot}%{_bindir}/lamboot-reader
%endif
%ifnarch x86_64 aarch64
# No firmware subpackage on this arch: drop the capcheck/reader man pages so
# they are not orphaned.
rm -f %{buildroot}%{_mandir}/man1/lamboot-capcheck.1* \
      %{buildroot}%{_mandir}/man1/lamboot-reader.1*
%endif

%files
%license LICENSE-MIT LICENSE-APACHE
%doc README.md CHANGELOG.md

%{_bindir}/lamboot-diagnose
%{_bindir}/lamboot-esp
%{_bindir}/lamboot-backup
%{_bindir}/lamboot-repair
%{_bindir}/lamboot-doctor
%{_bindir}/lamboot-toolkit
%{_bindir}/lamboot-uki-build
%{_bindir}/lamboot-signing-keys

%{_bindir}/lamboot-inspect
%{_prefix}/lib/lamboot-tools/lamboot-inspect
%{_prefix}/lib/lamboot-tools/lamboot_inspect/

%dir %{_prefix}/lib/lamboot-tools
%{_prefix}/lib/lamboot-tools/lamboot-toolkit-lib.sh
%{_prefix}/lib/lamboot-tools/lamboot-toolkit-help.sh
%{_prefix}/lib/lamboot-tools/lamboot-capcheck-bridge.sh
%{_prefix}/lib/lamboot-tools/esp-deploy.sh
%{_prefix}/lib/lamboot-tools/_nvram_set_first_boot.py

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
%doc pve/README.md
%{_bindir}/lamboot-pve-setup
%{_bindir}/lamboot-pve-fleet
%{_bindir}/lamboot-pve-monitor
%{_bindir}/lamboot-pve-ovmf-vars
%{_mandir}/man1/lamboot-pve-setup.1*
%{_mandir}/man1/lamboot-pve-fleet.1*

%ifarch x86_64 aarch64
%files -n lamboot-tools-firmware
%license LICENSE-MIT LICENSE-APACHE
%license vendor/notices/lamboot-capcheck.THIRD_PARTY_NOTICES.md
%license vendor/notices/lamboot-reader.THIRD_PARTY_NOTICES.md
%doc vendor/BINARY-PROVENANCE.txt
%{_bindir}/lamboot-capcheck
%{_bindir}/lamboot-reader
%{_mandir}/man1/lamboot-capcheck.1*
%{_mandir}/man1/lamboot-reader.1*
%endif

%post -n lamboot-toolkit-pve
cat <<EOF

lamboot-toolkit-pve installed.

Next steps:
  1. Verify the LamBoot hookscript is present:
       lamboot-pve-setup doctor-hookscript
  2. Create /etc/lamboot/fleet.toml — see: man lamboot-pve-setup
  3. Run initial inventory:
       lamboot-pve-fleet inventory

EOF
exit 0

%changelog
* Thu Jun 04 2026 Lamco Development LLC <office@lamco.io> - 0.8.0-1
- Prebuilt-repackage spec: repackages the published release tarball instead of
  building from source (sibling of the build-from-source lamboot-tools.spec)
- Installs the shell suite + the arch-matching vendored static-musl binaries
  (lamboot-capcheck, lamboot-reader) from vendor/bin/<arch>/
- Shared library and the lamboot_inspect package under /usr/lib/lamboot-tools
  (literal path, not %{_libdir})
