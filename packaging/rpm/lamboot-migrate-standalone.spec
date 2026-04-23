Name:           lamboot-migrate
Version:        1.0.0
Release:        1%{?dist}
Summary:        Automated Linux BIOS→UEFI migration and cross-bootloader migration tool
License:        MIT OR Apache-2.0
URL:            https://lamboot.dev/migrate/
Source0:        https://github.com/lamco-admin/%{name}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildArch:      noarch

BuildRequires:  make
BuildRequires:  bash
BuildRequires:  coreutils

Requires:       bash >= 4.0
Requires:       gdisk
Requires:       dosfstools
Requires:       efibootmgr
Requires:       util-linux
Requires:       rsync

# Optional deps for the more thorough preflight checks
Recommends:     file
Recommends:     lsblk
Suggests:       jq

# Conflict with the subpackage form — users should install one or the other
# The subpackage form (lamboot-migrate from lamboot-tools) has the same name,
# so RPM's own same-name-different-package handling prevents double install.

Provides:       linux-bios-uefi-migrate = %{version}-%{release}
Provides:       uefi-migrate = %{version}-%{release}

%description
lamboot-migrate is the first automated Linux BIOS→UEFI migration tool.

Features:
- Converts MBR → GPT on the running system
- Creates an EFI System Partition (ESP) at the end of the disk
- Installs a UEFI-capable bootloader (GRUB or LamBoot or systemd-boot)
- Rewrites fstab to UUID= form (partition-number-change-safe)
- Creates NVRAM UEFI boot entries via efibootmgr
- Populates the EFI/BOOT/BOOTX64.EFI fallback path
- Verifies the result via an 11-check post-conversion suite
- Supports rollback to the pre-migration MBR state

Safety guardrails refuse unsafe scenarios:
- Hybrid MBR (Rod Smith's "flaky and dangerous" layout)
- Windows dual-boot (NTFS with Boot Manager present)
- LVM-on-root or dm-crypt-on-root
- Insufficient free space for ESP
- Fstab using /dev/ paths (warns; Phase 6 auto-rewrites)
- Required tools missing (sgdisk, mkfs.vfat, efibootmgr, etc.)

Works on:
- Ubuntu / Debian (apt-based)
- Fedora / RHEL / Rocky / Alma (dnf-based)
- Arch / EndeavourOS / Manjaro / CachyOS (pacman-based)
- openSUSE (zypper-based)
- Alpine, Gentoo, others via generic grub-install fallback

Supports Proxmox VE VMs directly: three migration methods (pre-convert,
live-chroot, add-ESP-disk) with auto-selection.

Built by the authors of LamBoot (https://lamboot.dev). The complete
[lamboot-tools](https://github.com/lamco-admin/lamboot-tools) suite
provides additional diagnostic and repair utilities; this standalone
package exists for users who want just the migration tool.

%prep
%autosetup

%build
# Standalone build: the inlined binary is self-contained (shared library
# concatenated at top) so no external deps beyond what's in Requires:.
make

%install
install -d %{buildroot}%{_bindir}
install -m 755 bin/lamboot-migrate %{buildroot}%{_bindir}/lamboot-migrate

install -d %{buildroot}%{_mandir}/man1
if [ -f man/lamboot-migrate.1 ]; then
    install -m 644 man/lamboot-migrate.1 %{buildroot}%{_mandir}/man1/
fi

%check
# The inlined form should run --version without errors
%{buildroot}%{_bindir}/lamboot-migrate --version

%files
%license LICENSE-MIT LICENSE-APACHE
%doc README.md
%{_bindir}/lamboot-migrate
%{_mandir}/man1/lamboot-migrate.1*

%changelog
* Wed Apr 22 2026 Lamco Development <office@lamco.io> - 1.0.0-1
- Initial standalone release of lamboot-migrate
- Also available as subpackage of lamboot-tools
- 10-phase pipeline with 7 safety guardrails
- Distro-aware bootloader installation (apt/dnf/pacman/zypper/generic)
- Proxmox VE 3-method support
- Full rollback + 11-check verification
