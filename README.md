# LineageOS 21 (Android 14) for Samsung Galaxy S6 Edge+ (zenlte)

An **unofficial** build of LineageOS 21.0 for the Galaxy S6 Edge+ (`zenlte`,
Exynos 7420), plus a matching TWRP recovery and the fixes needed to reproduce
both.

Built 2026-08-03. Download from the [Releases](../../releases) page.

```
twrp-zenlte-v3-hardened-20260803.tar.md5     <- flash this in Odin first
32.4 MiB (33,945,671 bytes)
sha256: c751985f11232d0caf4ef49430df8b95e4b2988e16f56a52784a08fa2d50f457

lineage-21.0-20260803-UNOFFICIAL-zenlte.zip  <- then install this in TWRP
852.4 MiB (893,769,353 bytes)
sha256: 05cc196a7c8ec42881cd8e59cb3fb18e7d0e33916aa26aae69f634b01a817da0
```

## ⚠️ Read this first

This is a build of a community port on a phone from 2015. Flashing replaces your
OS and **wipes your data**. Back up first, and keep a known-good recovery path —
do not wipe your only way back until this has booted successfully for you.

**Verification status, stated honestly.** The f2fs kernel panic described below
was diagnosed at source level, and the fix was verified empirically rather than
assumed: the on-disk superblock produced by the patched formatter was parsed and
checked, and the compiled kernel was confirmed to contain the new bounds checks.
**But this specific build has not been flashed or booted on hardware by its
author.** The previous build in this series installed successfully via TWRP;
boot, radio, camera and sensors remain unconfirmed. No OTA path is provided.

No warranty. You are responsible for your own device.

## Flashing

The S6 Edge+ is a Samsung — it uses **download mode, not fastboot**. Odin cannot
flash raw `.img` files; it needs `.tar`/`.tar.md5` with the image at the archive
root. Both forms are attached to the release.

1. **Back up everything.**
2. Power off. Hold **Volume Down + Home + Power** to enter download mode, then
   **Volume Up** to confirm.
3. In Odin, load `twrp-zenlte-v3-hardened-20260803.tar.md5` into the **AP** slot.
   **Untick "Auto Reboot"** — this matters, see the next step.
4. Flash. When Odin says PASS, force a reboot with **Volume Down + Home + Power**,
   and the moment the screen goes dark switch to **Volume Up + Home + Power** to
   land straight in TWRP.
   *Do not let the phone boot to system in between — stock Android restores its
   own recovery on boot and you will lose TWRP.*
5. In TWRP: **Wipe → Format Data** (the full format, not just "wipe"), then
   **Wipe → Advanced** and tick Dalvik, Cache, System.
6. Install `lineage-21.0-20260803-UNOFFICIAL-zenlte.zip`.
7. If you want Google apps, flash them **in the same session, before first boot** —
   retrofitting later means starting over. See
   [MindTheGapps_Legacy](https://github.com/samsungexynos7420/MindTheGapps_Legacy).
8. Reboot to system. **First boot can take several minutes.** Be patient.

Heimdall users can flash `twrp-zenlte-v3-hardened-20260803.img` straight to the
`RECOVERY` partition with no repacking.

### If you prefer LineageOS Recovery

`recovery.img` and `recovery.tar.md5` — the LineageOS recovery built from this
same tree, with the same hardened kernel — are also attached. LineageOS's own
documented install method is `adb sideload` from it, and it is the better choice
if you hit GApps trouble in TWRP (see below).

## What changed in this build: the f2fs kernel panic, fixed at the root

Earlier builds bootlooped with a kernel panic as soon as `/data` saw real I/O:

```
Unable to handle kernel paging request at virtual address ffffffc1022cfe80
Kernel panic - not syncing: Fatal exception
PC is at update_sit_entry+0x68/0x354
LR is at refresh_sit_entry+0x6c/0xe8
  ... allocate_data_block / f2fs_write_data_pages
  ... write_checkpoint / f2fs_sync_fs / f2fs_sync_file / SyS_fdatasync
```

The previous build worked around this by dropping f2fs and using ext4 only. This
build fixes the actual defect, and f2fs works again.

**Two things had to be true, and both were.**

**1. The formatter wrote a filesystem this kernel cannot parse.**
`external/f2fs-tools` is 1.16.0. Invoked as `make_f2fs -g android` — exactly how
`fs_mgr` and recovery invoke it — it enabled `EXTRA_ATTR` (0x0008) plus
`PRJQUOTA`, `QUOTA_INO` and `VERITY`. But the zenlte kernel is 3.10 and knows
only two feature bits:

```c
/* kernel/samsung/universal7420/include/linux/f2fs_fs.h:112-113 */
#define F2FS_FEATURE_ENCRYPT   0x0001
#define F2FS_FEATURE_BLKZONED  0x0002
```

and its `struct f2fs_inode` is the pre-4.14 fixed layout with **no
`i_extra_isize`**. f2fs has no incompatible-feature gate, so the old kernel
mounted the filesystem anyway. With `EXTRA_ATTR` set, mkfs writes block pointers
at `i_addr[get_extra_isize()]` while the kernel reads `i_addr[0]` — so the kernel
consumed *inode metadata as block addresses*.

*Corroboration:* TWRP ships f2fs-tools **1.14.0**, whose Android default set does
**not** enable `EXTRA_ATTR`. That is exactly why TWRP-formatted f2fs worked while
ROM-formatted f2fs did not.

**2. The kernel trusted those addresses without bounds-checking them.**
`GET_SEGNO()` → `get_seg_entry()` → `&sit_i->sentries[segno]`, with no check at
all — roughly 700× past the end of the array.

### Fixing only the defaults would not have been enough

The obvious fix — clearing the feature bits in f2fs-tools' `CONF_ANDROID`
defaults — leaves the bug **fully intact**, because both callers ask for the
killer feature explicitly on the command line:

- `system/core/fs_mgr/fs_mgr_format.cpp` sets `bool needs_projid = true;`
  unconditionally, so it always appends `-O project_quota,extra_attr`
- `bootable/recovery/recovery_utils/roots.cpp` hardcodes the same string

So the authoritative fix is a **mask applied after option parsing and after the
defaults**, which catches every caller whatever it asked for. Both callers were
fixed too, but the mask is what actually guarantees it.

### The kernel is hardened as well

So that a corrupt or incompatible filesystem produces a clean failure instead of
a panic:

- **`update_sit_entry()` bounds check** — the exact panic site. Returns early on
  `NULL_SEGNO`, and refuses with "needs fsck" when `segno >= MAIN_SEGS(sbi)`.
- **`sanity_check_ckpt()`** — adapted from upstream `15d3042a937c`
  (CVE-2017-10663, fixed upstream in 4.12.4), which this 3.10 tree never received.
- **`build_sit_entries()` SIT-journal bounds check.** Adapting upstream
  `b2ca374f33bd` exposed a **second, independent out-of-bounds bug**: the main SIT
  loop is bounded, but the journal loop below took its segment number straight
  from disk and indexed `sentries[]` unchecked.
- **`CONFIG_F2FS_CHECK_FS` turned off.** With it on, `f2fs_bug_on()` expands to a
  bare `BUG_ON()` — f2fs *deliberately panics* on any detected inconsistency,
  which would have kept panicking even with the bounds checks above. Off, it
  becomes `WARN_ON()` + "needs fsck", the upstream/AOSP production setting.

### Why the fstab lists ext4 first

`/data` and `/cache` list **ext4 first, f2fs second**. `fs_mgr` mounts the first
entry that works and formats using the first entry, so:

- a freshly formatted phone gets **ext4** — the conservative default;
- a partition that is already f2fs (for example, formatted by TWRP) still
  **mounts**, via the f2fs fallback.

That restores f2fs support without betting the boot on it. If anything about the
fix were still imperfect, you get ext4 and a working phone rather than a bootloop.

The TWRP image here is built on this same hardened kernel with `CONFIG_F2FS_FS=y`,
so TWRP can once again read and back up f2fs partitions — which the previous
f2fs-free workaround recovery could not.

### Known: MindTheGapps fails in TWRP with "error 1"

Reported on the earlier build: the **ROM itself installs fine in TWRP**, but
`MindTheGapps-14-arm64` aborts with a generic error 1.

Ruled out as causes — measured, not guessed:

- **Not disk space.** `system.img` is created at the full
  `BOARD_SYSTEMIMAGE_PARTITION_SIZE`, leaving roughly 820 MB free in `/system`.
- **Not an architecture mismatch.** The build is `TARGET_ARCH=arm64`, Android 14,
  SDK 34 — MindTheGapps 14 arm64 is correct.

The likely cause is the recovery. This device has **no separate `product` or
`system_ext` partition** — the fstab has only `SYSTEM`, and those are directories
inside it. MindTheGapps for Android 13+ expects to mount and write those paths,
and older TWRP builds frequently fail there. If you hit it, use `adb sideload`
from LineageOS Recovery and read `/tmp/recovery.log` — the line *above* the abort
is the useful one, and the log spans the whole session, so check timestamps
before blaming the most recent error you see.

## Building it yourself

Source trees come from the [samsungexynos7420](https://github.com/samsungexynos7420)
org, not LineageOS's official device list — `zenlte` is not an officially
supported device. `local_manifests/universal7420.xml` here is the manifest used.

```bash
repo init -u https://github.com/LineageOS/android.git -b lineage-21.0 --git-lfs
mkdir -p .repo/local_manifests
cp local_manifests/universal7420.xml .repo/local_manifests/
repo sync -c -j4
# apply patches/ (see below), then:
source build/envsetup.sh
breakfast zenlte      # -> lunch lineage_zenlte-ap2a-userdebug
mka -j16 bacon
```

`start_build.sh` runs the above detached and logged. Launch it with `setsid`,
**not** as a plain background job:

```bash
setsid nohup bash start_build.sh >/dev/null 2>&1 </dev/null & disown
```

`repack_twrp.sh` builds the TWRP image: it takes the TWRP ramdisk and repacks it
onto the LineageOS recovery kernel and device tree from this build, then produces
the Odin `.tar.md5`. It refuses to emit an image with `dt_size=0`, one that
exceeds the recovery partition, or one whose kernel lacks `CONFIG_F2FS_FS=y`.

## Patches

Each file in `patches/` carries a full explanation in its header. Apply each in
the tree named by its `Apply in:` line.

| Patch | Tree | What it does |
|---|---|---|
| 0001 | `device/samsung/zenlte` | FCM target level 3 → 5 (build fix) |
| 0002 | `external/f2fs-tools` | **The root-cause fix** — never stamp feature bits this kernel cannot parse |
| 0003 | `system/core` | fs_mgr stops requesting `extra_attr`/`project_quota` |
| 0004 | `bootable/recovery` | recovery stops requesting the same |
| 0005 | `device/samsung/universal7420-common` | f2fs restored for `/data` + `/cache`, listed after ext4 |
| 0006 | `kernel/samsung/universal7420` | SIT bounds checks, checkpoint sanity check, `CONFIG_F2FS_CHECK_FS` off |

Patches 0002–0006 are **device specific**. They are correct here because this
tree only ever builds `zenlte`; on a multi-device tree they would need gating on
the target kernel version.

**These live on repo-managed trees — `repo sync` will discard them.** Re-apply
after every sync.

## Other build fixes

Three further things broke a from-scratch build. All are documented with full
evidence in [PROGRESS.md](PROGRESS.md).

### Git LFS pointer stubs (fails at ~51%)

```
target Prebuilt: webview (.../webview_intermediates/package.apk)
zip2zip.go:82: zip: not a valid zip file
```

`external/chromium-webview/prebuilt/arm64/webview.apk` was a 134-byte LFS
pointer, not the 262 MB APK. **`git-lfs` was not installed**, so `repo sync` wrote
stubs and reported success — `repo init --git-lfs` does nothing without the binary
present.

```bash
git lfs version || echo "install git-lfs FIRST"
cd external/chromium-webview/prebuilt/arm64 && git lfs pull
cd ../arm && git lfs pull
```

Nothing validates prebuilt integrity at sync time, so this stays invisible until
something opens the file as a zip, 51% into a build.

### repo config cache vs the build sandbox

```
OSError: [Errno 30] Read-only file system: '/home/<user>/.repo_.gitconfig.json'
```

Not a disk fault. The AOSP build sandbox mounts `/` read-only. `repo manifest`
caches `~/.gitconfig` keyed on mtime; installing git-lfs rewrote `~/.gitconfig`,
invalidating that cache, and the next refresh happened *inside* the sandbox.

```bash
cd src && python3 .repo/repo/repo manifest -o - -r >/dev/null
# run again; ~/.repo_.gitconfig.json mtime must not change
```

**General rule: after any change to `~/.gitconfig`, re-warm before building.**

### SIGHUP kills a backgrounded build

A build started as a plain `&` background job dies to SIGHUP when its parent shell
exits — silently, ~80 seconds in, with no `FAILED:` line in the log. Use `setsid`
(and `trap '' HUP`, as `start_build.sh` does).

## Notes

- Do **not** add `set -u` to the build script — `build/envsetup.sh` references an
  unbound `TOP` and aborts under `nounset`, silently producing an `rc=127` no-op
  build that looks like it ran.
- `lineage_zenlte-ota.zip` in the output dir is a hardlink to the same file as the
  dated zip, not a second artifact.
- LineageOS 21 does not generate a `.md5sum` for the ROM zip; verify with sha256.
- For Odin, the md5 line must name the **`.tar`**:
  `tar -H ustar -cf X.tar recovery.img && md5sum -t X.tar >> X.tar && mv X.tar X.tar.md5`.
  Naming `recovery.img` there produces an Odin "binary is invalid" failure.
- A recovery image with `dt_size=0` will not boot on this device.
- **Android 14 is the ceiling for this device.** Every repo in the
  samsungexynos7420 org tops out at `lineage-21.0-unify` — there is no
  `lineage-22` branch anywhere, including forks. The org is actively maintained,
  so this is a deliberate stopping point, not abandonment.

## Credits

All device, kernel, and vendor work is by the
[samsungexynos7420](https://github.com/samsungexynos7420) maintainers, and TWRP by
[TeamWin](https://twrp.me/). This repo contains build fixes, the f2fs diagnosis
and fix, and compiled artifacts.
