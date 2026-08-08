# LineageOS 21 (Android 14) for Samsung Galaxy S6 Edge+ (zenlte)

An **unofficial** build of LineageOS 21.0 for the Galaxy S6 Edge+ (`zenlte`,
Exynos 7420), plus a matching TWRP recovery and the fixes needed to reproduce
both.

Current build **v5, 2026-08-05** — signed with a private release key, plus
curved-edge grip rejection. Download from the [Releases](../../releases) page.

```
twrp-zenlte-v3-hardened-20260803.tar.md5     <- flash this in Odin first
32.4 MiB (33,945,671 bytes)                     (unchanged since v3)
sha256: c751985f11232d0caf4ef49430df8b95e4b2988e16f56a52784a08fa2d50f457

lineage-21.0-20260805-UNOFFICIAL-zenlte.zip  <- then install this in TWRP
851.6 MiB (892,946,400 bytes)
sha256: e7fbd4242b0100673292a58a6dbbc31a41925ccf88b9af1e95782ab0b546d67c

NikGapps-basic-arm64-14                      <- then this, same TWRP session,
not hosted here - get it from nikgapps.com      before the first boot
```

**v4 (2026-08-04)** is also published: identical to v5 but without the edge
change. Same signing key, so you can dirty-flash between v4 and v5 with no
Format Data and no data loss — that is the escape hatch if the edge dead zone
does not suit you.

```
lineage-21.0-20260804-UNOFFICIAL-zenlte.zip
851.6 MiB (892,939,202 bytes)
sha256: 214d8e0f34b3ea16779fa88a0e907a1f363194aa238eb2aa14dc43105e064f82
```

> ### ⚠️ Coming from v3 or earlier? You must Format Data
>
> v4/v5 are signed with a different key than v3, so PackageManager sees a
> signature mismatch on every system app. A dirty flash will not boot.
>
> **This phone has no SD slot**, so Format Data erases the only storage you have
> — the ROM and GApps zips included. Nothing survives it. Either copy the zips
> back on afterwards over MTP/adb, or push them from TWRP at flash time
> (`adb push`, then `adb shell twrp install …`), which is the more reliable
> habit: files kept on internal storage die with every Format Data.
>
> Note that **Format Data is not the same as Wipe → Factory Reset.** Factory
> Reset preserves `/data/media` (internal storage); Format Data does not. Here
> you need Format Data.

Three files, in that order: **TWRP in Odin → ROM in TWRP → GApps in TWRP.**
GApps are not redistributed here; download `NikGapps-basic` (arm64, Android 14)
from [nikgapps.com](https://nikgapps.com/). **Do not substitute MindTheGapps** —
it does not fit on this device. The [sizing table](#gapps-how-much-actually-fits--and-why-mindthegapps-fails-with-error-1)
explains why.

## ⚠️ Read this first

This is a build of a community port on a phone from 2015. Flashing replaces your
OS and **wipes your data**. Back up first, and keep a known-good recovery path —
do not wipe your only way back until this has booted successfully for you.

**Verification status, stated honestly.** The f2fs kernel panic described below
was diagnosed at source level, and the fix was verified empirically rather than
assumed: the on-disk superblock produced by the patched formatter was parsed and
checked, and the compiled kernel was confirmed to contain the new bounds checks.

**This build has since been flashed, booted and set up on hardware** — an
SM-G928F, on 2026-08-03. It installs from TWRP, boots to a working Android 14,
and has been taken through initial setup with **`NikGapps-basic` installed, the
Play Store signed in, and apps downloaded and installed** — which also confirms
the GApps sizing below empirically, not just from the superblock arithmetic.

Still not claimed: **camera, sensors and battery life have not been
systematically tested**, and the build was booted on **ext4** — the f2fs path is
fixed and verified at the formatter and kernel-binary level, but has not been
exercised end-to-end on a device. No OTA path is provided.

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
6. **Now** copy the ROM zip and your GApps zip onto the phone — MTP over USB, a
   USB-OTG stick, or `adb push <file> /sdcard/` from TWRP. Do it in this order:
   the S6 Edge+ has **no microSD slot**, so "internal storage" is a folder on
   `/data`, and Format Data in step 5 erases anything you staged there first.
7. Install `lineage-21.0-20260803-UNOFFICIAL-zenlte.zip`.
8. If you want Google apps, flash them **in the same session, before first boot** —
   retrofitting later means starting over. Use **`NikGapps-basic`** (arm64, 14)
   or `NikGapps-core`; **MindTheGapps 14 does not fit on this device** and fails
   with a generic "error 1". See [the sizing table](#gapps-how-much-actually-fits--and-why-mindthegapps-fails-with-error-1)
   before you pick a package — this is the single most common way an install of
   this ROM goes wrong.
9. Reboot to system. **First boot can take several minutes.** Be patient.

The TWRP you flashed in step 3 is enough for all of this. The v3 hardened image
is only *needed* if you intend to use f2fs; an earlier TWRP build for this device
installs this ROM fine.

Heimdall users can flash `twrp-zenlte-v3-hardened-20260803.img` straight to the
`RECOVERY` partition with no repacking.

**TWRP survives the ROM install.** Checked rather than assumed: the zip's
`updater-script` writes only `boot.img` to `BOOT` and never touches `RECOVERY`,
and the build contains no `install-recovery.sh` / `recovery-from-boot.p`, so
nothing restores a different recovery on first boot. The `recovery.img` inside
the zip is carried for reference and is not flashed.

### If you flash TWRP from inside TWRP, pick `Recovery` — never `Boot`

Odin puts the image where it belongs, so this only applies to **Install → Install
Image** inside TWRP, where you choose the target partition yourself and `Boot`
sits next to `Recovery` in the list. The sizes, read off an SM-G928F:

| | bytes | |
|---|---:|---|
| `BOOT` → `sda5` | 29,360,128 | **image does not fit — 4.6 MB too big** |
| `RECOVERY` → `sda6` | 35,651,584 | fits, 1.7 MB to spare |
| `twrp-zenlte-v3-hardened-20260803.img` | 33,939,472 | |

A truncated image on `boot` leaves nothing bootable, and the phone falls back to
recovery on every start — which reads as a "recovery bootloop" even though system
is untouched. Recover by flashing a good `boot.img` (it is inside the ROM zip),
not by wiping anything. The sister project for the Moto G5S Plus hit exactly this.

To confirm what is actually on the recovery partition, hash it with the image's
**exact byte length** — `dd` with a 512-byte block size silently reads short here,
because 33,939,472 is not a multiple of 512:

```bash
adb shell 'head -c 33939472 /dev/block/sda6 | sha256sum'
# 8d0f945021c1d6cf60d1ba49c0e39c1663126745f9ff1b3b341cdd78b4a5fc3d
```

The TWRP version string cannot tell the two builds apart — both report
`3.7.1_12-0`. Use the kernel date instead: `adb shell cat /proc/version` says
**1 Aug 17:38** for the earlier build and **3 Aug 04:01** for the hardened one.

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

### GApps: how much actually fits — and why MindTheGapps fails with "error 1"

**Correction.** An earlier version of this page ruled out disk space as the cause
of the MindTheGapps "error 1" failure. **That was wrong**, and the mistake was
comparing free space against the *compressed download size* instead of the
installed payload. Measured properly:

| Package | Installed payload | Fits in 812 MiB? |
|---|---|---|
| `MindTheGapps-14.0.0-arm64` | **1025 MiB** | **no — short by 215 MiB** |
| `NikGapps-full` / `NikGapps-stock` | ~2100 / ~1750 MiB | no, by a wide margin |
| `NikGapps-omni` | **1048 MiB** | **no — short by 237 MiB** |
| `NikGapps-basic` | **497 MiB** | **yes**, 314 MiB to spare |
| `NikGapps-core` | ~266 MiB | yes |

`/system` on this device is a fixed 3,124,019,200-byte partition. The ROM fills
2.12 GiB of it, leaving **812 MiB** — measured from the ext4 superblock inside
the built `system.img` (207,774 free 4 KiB blocks), not estimated.

MindTheGapps 14 needs 1025 MiB of that. **It cannot fit, and "error 1" is the
expected result.** The device also has **no separate `product` or `system_ext`
partition** — the fstab has only `SYSTEM`, and those are directories inside it —
which is a genuine second obstacle for MindTheGapps on Android 13+, but the space
shortfall alone is sufficient to explain the failure.

**Use `NikGapps-basic` (or `core`).** They are the variants that fit. Google apps
must be installed in the same recovery session as the ROM, before first boot.

To check any package yourself before flashing it, compare its *uncompressed*
payload — not the download size — against 812 MiB:

```bash
# NikGapps: payloads are nested zips under AppSet/
unzip -q NikGapps-*.zip 'AppSet/*' -d /tmp/ng
for z in $(find /tmp/ng -name '*.zip'); do unzip -l "$z" | tail -1; done | awk '{s+=$1} END{printf "%.0f MiB\n", s/2^20}'

# MindTheGapps: a plain system/ tree
unzip -l MindTheGapps-*.zip | awk '$4 ~ /^system\// {s+=$1} END {printf "%.0f MiB\n", s/2^20}'
```

If a GApps install does fail, read `/tmp/recovery.log` — the line *above* the
abort is the useful one, and the log spans the whole session, so check timestamps
before blaming the most recent error you see.

## What changed in v4 and v5

### v4 — signed with a private release key

v3 and earlier were `test-keys` builds, so LineageOS Trust showed the
"public key" warning. v4 and v5 are signed with a generated release key:

```make
# vendor/lineage-priv/keys/keys.mk
PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/lineage-priv/keys/releasekey
```

Setting that flips `ro.build.tags` from `test-keys` to `dev-keys` automatically
(`build/make/core/sysprop.mk`), which is what clears the warning. No
`sign_target_files_apks` post-processing step is needed for this tree, and this
board has `BOARD_AVB_ENABLE := false`, so there is no vbmeta/verity key.

Two things that are easy to get wrong:

**The keys must live inside the tree.** Soong resolves `certificate: "platform"`
against `DefaultAppCertificateDir()`, which is `dirname(PRODUCT_DEFAULT_DEV_CERTIFICATE)`
resolved with `PathForSource()`. An absolute path outside the source tree does
not work.

**You need nine keys, including one called `testkey`.**
`system/sepolicy/build/soong/mac_permissions.go` has

```go
AllPlatformKeys = []string{"platform","sdk_sandbox","media",
                           "networkstack","shared","testkey","bluetooth"}
```

and joins each to the default cert dir. Miss `testkey` and the build dies at
**ninja time** on `plat_mac_permissions.xml`, not at Soong analysis time — so
`m nothing` will not catch it, and you find out an hour in. Generating a key
file named `testkey` does **not** make this a test-keys build; `ro.build.tags`
follows `releasekey`.

Also note `make_key` installs `trap '…; exit 1' EXIT` and never clears it, so it
returns 1 even on success. Do not run a key-generation loop under `set -e`.

**What signing does not fix:** the SELinux warning below, and Play Integrity.

### v5 — curved-edge grip rejection

The curved edges on this phone are easy to catch with a palm or thumb. The STM
`fts5ad56` touch controller has a firmware dead-zone feature for exactly this,
and the ROM never enabled it — the sysfs entry is even permissioned for it in
`init.samsung.rc`, but nothing ever writes to it.

v5 enables it in the driver
(`drivers/input/touchscreen/stm/fts5ad56/fts_ts.c`):

```c
regAdd[0] = 0xC4;  regAdd[1] = 0x03;  /* set_dead_zone, side edge all on */
regAdd[0] = 0xC2;  regAdd[1] = 0x0C;  /* dead zone enable */
```

Register polarity was read out of `dead_zone_enable()` in `fts_sec.c` — `0xC2`
is inverted relative to `fts_enable_feature()`, which is a trap if you assume
consistency.

It is applied in **both** `fts_init()` and `fts_reinit()`. The second one is
load-bearing: `fts_reinit()` issues a system reset on every resume and restores
only the cover and glove settings, so without a hook there the dead zone would
silently vanish the first time the screen turned off.

The band is Samsung's own ~160 px per side. If it rejects touches you actually
wanted, turn it off at runtime with root:

```sh
echo dead_zone_enable,0 > /sys/class/sec/tsp/cmd
```

or dirty-flash v4, which has no edge change and the same signing key.

### SELinux ships Permissive, and it is not a one-line fix

`exynos7420-zenlte_defconfig` sets `CONFIG_SECURITY_SELINUX_PERMISSIVE=y`, which
hardcodes `new_value = 0` in `sel_write_enforce()`. The kernel command line says
`androidboot.selinux=enforcing` and `getenforce` still reports `Permissive` —
the cmdline cannot win against that config.

This was audited on hardware before deciding, not guessed:

```
443  unique denial tuples          (a manageable port is < ~50)
 98  denials in core domains       (init, zygote, apexd, netd, logd,
                                    system_server, surfaceflinger, bpfloader,
                                    vold_prepare_subdirs, kernel, vendor_init)
 76  distinct source domains
458  denials from odrefresh alone
```

Upstream set this deliberately — commit `3a373b4fd6b6`, *"defconfigs: set to
permissive / sepolicy is not ready"*. Flipping the defconfig without writing the
policy to match would produce a device that does not boot. It was left as-is.

Consequence: Trust still shows the SELinux warning, and Play Integrity will
fail. The warning can be silenced from the notification's Manage button.

### Xposed: LSPosed does not work on this build — use Vector

LSPosed 1.9.2 (the final release of the abandoned original project) fails to
initialise here. Its manager will not open from its notification, and no module
is ever hooked. `/data/adb/lspd/log/verbose_*.log` shows:

```
E/LSPlant   Failed to find GetMethodShorty
E/LSPlant   Failed to init art method
E/LSPosed   Failed to init lsplant
```

`libart.so` from this ROM, read with `readelf --syms --dyn-syms`:

```
2,622  dynamic symbols             -> not stripped
   93  ArtMethod symbols           -> richly symbolled
    0  symbols containing "Shorty" -> searched .symtab AND .dynsym
```

`ArtMethod::GetShorty()` is defined inline in `art_method-inl.h`; fully inlined
here, so no out-of-line copy and no symbol. LSPlant resolves it by mangled name
and cannot start without it.

LSPosed's "supports Android 8.1 ~ 14" claim does not help, because LSPlant binds
to **ART internals by mangled C++ symbol**, not to the API level — and ART ships
as an updatable APEX (`com.android.art`), so two devices can both be Android 14
with different ART binaries. This ROM reports `com.android.art@350090000`.

Use [JingMatrix/Vector](https://github.com/JingMatrix/Vector) instead — the
maintained successor, built on a current LSPlant, supporting Android 8.1
through 17. Requires Magisk with Zygisk enabled (tested with Magisk 30.7).

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
