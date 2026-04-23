# Fixture regeneration scripts

One per fixture under `tests/fixtures/<name>.raw`. Each script is idempotent — re-runs produce the same output modulo distro updates.

## Prerequisites

- **libvirt / qemu-system-x86_64** for VM-based regen
- **Install ISOs** cached under `$FIXTURE_ISO_CACHE` (default: `/var/cache/lamboot-fixtures/isos/`)
- Root (for `losetup`, filesystem creation, disk imaging)

## Pattern

Every regen script:

1. Pulls the distro's install ISO if not cached (with checksum verification)
2. Spins up a throwaway VM with the ISO + a blank raw disk
3. Auto-installs via kickstart / preseed / autoinstall
4. Shuts down the VM
5. Writes the disk image to `tests/fixtures/<name>.raw`
6. Updates `tests/fixtures/fixtures.sha256` with the new SHA
7. Optionally: uploads to `fixtures.lamboot.dev` (gated on `PUBLISH_FIXTURES=1`)

## Scripts

| Script | Produces | Base distro |
|---|---|---|
| `clean-bios-mbr.sh` | `clean-bios-mbr.raw` | Debian 13 netinst |
| `clean-uefi-gpt.sh` | `clean-uefi-gpt.raw` | Fedora 44 everything |
| `hybrid-mbr.sh` | `hybrid-mbr.raw` | Synthetic — no base distro |
| `encrypted-root.sh` | `encrypted-root.raw` | Fedora 44 with LUKS kickstart |
| `windows-mbr.sh` | `windows-mbr.raw` | Manual; distribution restricted |
| `no-esp.sh` | `no-esp.raw` | Ubuntu minimal with ESP deletion post-install |
| `full-esp.sh` | `full-esp.raw` | Ubuntu minimal + dd dummy files on ESP |
| `corrupted-esp-fat.sh` | `corrupted-esp-fat.raw` | Ubuntu minimal + FAT sector overwrite |
| `lamboot-installed.sh` | `lamboot-installed.raw` | Fedora 44 + `lamboot-install` post-install |
| `grub-installed.sh` | `grub-installed.raw` | Ubuntu 24.04 LTS server |
| `sdboot-installed.sh` | `sdboot-installed.raw` | Arch Linux systemd-boot bootstrap |

## Running

Individual:

```bash
sudo tests/fixtures/regen/clean-uefi-gpt.sh
```

All (slow — 20–30 hours total):

```bash
sudo tests/fixtures/regen/regen-all.sh
```

## Publishing

After regen, upload to the hosting location:

```bash
PUBLISH_FIXTURES=1 sudo tests/fixtures/regen/clean-uefi-gpt.sh
# Requires: $FIXTURES_UPLOAD_URL + $FIXTURES_UPLOAD_TOKEN env vars
```

Publishing is normally done by a release engineer during a release cycle, not by individual contributors. See `publish/` for the release pipeline.

## Synthetic fixtures

Not every fixture comes from a full distro install. Synthetics like `hybrid-mbr.raw` are built from scratch using `dd` + `sgdisk` + manual byte editing:

```bash
# Sketch of hybrid-mbr.sh
dd if=/dev/zero of=hybrid-mbr.raw bs=1M count=100
sgdisk --clear hybrid-mbr.raw
sgdisk --new=1:0:+50M --typecode=1:8300 hybrid-mbr.raw
# ... then add MBR partition alongside GPT to create hybrid ...
```

These run faster (seconds) than full-install fixtures (hours).
