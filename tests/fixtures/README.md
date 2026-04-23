# Fixture disk images

Disk images used by bats integration tests. Not committed to git directly (4 GB images exceed git-lfs budget); managed via the download script + SHA verification pattern.

## Catalog

| File | Size | Format | Scenario | Regen script |
|---|---|---|---|---|
| `clean-bios-mbr.raw` | 4 GB | raw | Debian 13 on MBR (baseline BIOS) | `regen/clean-bios-mbr.sh` |
| `clean-uefi-gpt.raw` | 4 GB | raw | Fedora 44 on GPT (baseline UEFI) | `regen/clean-uefi-gpt.sh` |
| `hybrid-mbr.raw` | 100 MB | raw | Synthetic hybrid MBR (refusal test) | `regen/hybrid-mbr.sh` |
| `encrypted-root.raw` | 4 GB | raw | Fedora + LUKS-encrypted root | `regen/encrypted-root.sh` |
| `windows-mbr.raw` | 4 GB | raw | Windows 11 on MBR | `regen/windows-mbr.sh` |
| `no-esp.raw` | 4 GB | raw | UEFI system without ESP partition | `regen/no-esp.sh` |
| `full-esp.raw` | 550 MB | raw | ESP at 99% capacity | `regen/full-esp.sh` |
| `corrupted-esp-fat.raw` | 550 MB | raw | ESP with deliberate FAT corruption | `regen/corrupted-esp-fat.sh` |
| `lamboot-installed.raw` | 4 GB | raw | Fedora 44 + LamBoot bootloader | `regen/lamboot-installed.sh` |
| `grub-installed.raw` | 4 GB | raw | Ubuntu 24.04 + GRUB | `regen/grub-installed.sh` |
| `sdboot-installed.raw` | 4 GB | raw | Arch + systemd-boot | `regen/sdboot-installed.sh` |

**Total:** 11 fixtures, ~40 GB uncompressed.

## Download

```bash
# From repo root
./tests/fixtures/download-fixtures.sh
```

Downloads fixtures from the hosting location (`https://fixtures.lamboot.dev/`) and verifies against `fixtures.sha256`. Re-run to fetch only missing fixtures.

## Regeneration

Each fixture has a per-fixture regen script under `regen/`. Regen is periodically re-run to track distro defaults (e.g., Fedora's kernel/bootloader packaging changes release-to-release).

```bash
# Regenerate one fixture (requires root + libvirt / qemu + install ISOs)
sudo ./tests/fixtures/regen/clean-uefi-gpt.sh

# Regenerate all (slow; ~2h per fixture with network-based installs)
sudo ./tests/fixtures/regen/regen-all.sh
```

Regen scripts use:

- **Kickstart** for Fedora/RHEL
- **preseed** for Debian/Ubuntu
- **cloud-init + autoinstall** for modern distros where available
- Manual install + snapshot for Windows (not reproducible without image copy)

Output of regen is a new `.raw` file + updated `fixtures.sha256` entry.

## Hosting

Fixtures are hosted at `https://fixtures.lamboot.dev/` (behind the lamco-admin infrastructure). Public read-only; HTTPS + sha256 verification provides integrity.

Hosting bandwidth is rate-limited; CI caches per-fixture on the self-hosted runner to avoid repeat downloads.

## Using fixtures in tests

Bats tests check for fixture presence before running:

```bats
@test "lamboot-migrate refuses on hybrid MBR" {
    local fixture="$BATS_TEST_DIRNAME/fixtures/hybrid-mbr.raw"
    [ -f "$fixture" ] || skip "fixture not present; run download-fixtures.sh"
    
    run sudo "$TOOL" to-uefi --offline "$fixture" --dry-run
    [ "$status" -eq 4 ]  # EXIT_UNSAFE
}
```

`skip` on missing fixture means developers without fixtures can still run the CLI-surface bats tests; CI with fixtures fetched runs the full integration matrix.

## Size policy

Fixtures committed to git: **never**. Too large.

- **Small (<1 MB)** synthetic artifacts (sample snapshots, tiny corrupted binaries) live under `tests/fixtures/small/` and are git-tracked.
- **Medium (1 MB – 100 MB)** synthetic disk layouts live in S3 + download script.
- **Large (>100 MB)** full-install fixtures live in S3 only; fetched on demand.

## CI cache strategy

GitHub Actions install-smoke tier doesn't need fixtures (install-only test). The self-hosted runner does and caches fixtures under `~/.cache/lamboot-fixtures/` keyed by the `fixtures.sha256` hash.

## Maintainer notes

When a regen produces a different output (distro updates, new kernel), the SHA changes:

1. Run the regen script
2. Commit the new `fixtures.sha256` line
3. Upload the new `.raw` to hosting
4. Update `docs/CROSS-REPO-STATUS.md` if the change affects testing baselines
