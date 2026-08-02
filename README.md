# LineageOS 21 (Android 14) for Samsung Galaxy S6 Edge+ (zenlte)

An **unofficial** build of LineageOS 21.0 for the Galaxy S6 Edge+ (`zenlte`,
Exynos 7420), plus the fixes needed to reproduce it.

Built 2026-08-01. Download the ROM from the
[Releases](../../releases) page.

```
lineage-21.0-20260801-UNOFFICIAL-zenlte.zip
853 MB
sha256: 4590053278eecf979c1f0549d7dd94ae3bcb3e83da3b58b9922ba7387b730157
```

## ⚠️ Read this first

This is a build of a community port on a phone from 2015. **It has been confirmed
to flash and install**, but treat everything beyond that as unverified. It has
not been verified to boot. Flashing replaces your OS and **wipes your data**.
Back up first, and keep a known-good recovery path — do not wipe your only way
back until this has booted successfully for you.

No warranty. You are responsible for your own device.

## Flashing

The S6 Edge+ is a Samsung — it uses **download mode, not fastboot**.

**Odin cannot flash raw `.img` files** — it needs `.tar`/`.tar.md5`, with the
image at the archive root so Odin can identify the target partition. A ready-made
`recovery.tar.md5` is attached to the release; flash it in the **AP** slot, and
**untick "Auto Reboot"** so you can boot straight into the new recovery instead of
letting the phone boot to system first. Heimdall flashes `recovery.img` directly
with no repacking.

### Known: MindTheGapps fails in TWRP with "error 1"

Reported on this build: the **ROM itself installs fine in TWRP**, but
`MindTheGapps-14-arm64` aborts with a generic error 1.

Ruled out as causes — measured, not guessed:
- **Not disk space.** `system.img` is a sparse image of 762,700 × 4096 =
  3,123,916,800 bytes, i.e. the ext4 filesystem is created at the full
  `BOARD_SYSTEMIMAGE_PARTITION_SIZE` (3,124,019,200), not shrunk to content.
  With ~2.1 GiB of content that leaves roughly **820 MB free** in `/system`.
- **Not an architecture mismatch.** The build is `TARGET_ARCH=arm64`, Android 14,
  SDK 34 — so MindTheGapps 14 arm64 is the correct package.

The likely cause is the recovery. This device has **no separate `product` or
`system_ext` partition** — the fstab has only `SYSTEM`, and `product`/`system_ext`
are directories inside it. MindTheGapps for Android 13+ expects to mount and write
those paths, and older TWRP builds frequently fail there.

LineageOS's own documented method is `adb sideload` from **LineageOS Recovery**
(`recovery.img`, attached to the release, version-matched to this ROM). If you
still hit it there, `/tmp/recovery.log` names the real cause — the line above the
abort is the useful one, and note the log spans the whole recovery session, so
check timestamps before blaming the most recent error you see.

GApps must go on **before the first boot** of the ROM. If you have already booted,
reflash the ROM and GApps in one session from a clean format.

1. **Back up everything.**
2. Flash `recovery.tar.md5` in Odin's **AP** slot (Auto Reboot off), or
   `recovery.img` via Heimdall.
3. Boot **straight into recovery** — do not let the phone boot to system in
   between, or stock Android may restore its own recovery.
4. Factory reset / format data.
5. Sideload or install `lineage-21.0-20260801-UNOFFICIAL-zenlte.zip`.
6. If you want Google apps, flash them **in the same session, before first
   boot** — retrofitting later means starting over. See
   [MindTheGapps_Legacy](https://github.com/samsungexynos7420/MindTheGapps_Legacy).

First boot on this hardware can take several minutes. Be patient.

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

## Fixes required to build

Four things broke a from-scratch build. All are documented with full evidence in
[PROGRESS.md](PROGRESS.md).

### 1. FCM version mismatch (fails at ~77%)

```
Inconsistent FCM Version in HAL manifests:
    device/samsung/universal7420-common/manifest.xml has level 5
    device/samsung/zenlte/manifest.xml               has level 3
```

The zenlte device manifest is an empty shell — all HAL entries moved to the
common tree in 2023, so the file's only effect is asserting an FCM level. The
common tree went 3→5 in Aug 2025 on `lineage-21.0-unify`; zenlte never got the
matching commit because it has **no `lineage-21` branch** (its newest is
`lineage-20.0-unify`).

Fix: `patches/0001-zenlte-manifest-fcm-target-level-3-to-5.patch`. This mirrors
upstream's own commit `eb21caff` on the `noblelte` `lineage-21.0-unify` branch,
which makes the identical one-line change. Verified to introduce no new HAL
requirement: the merged `assemble_vintf` output is byte-identical to running it
on the common manifest alone.

**This lives on a repo-managed detached HEAD — `repo sync` will discard it.**

### 2. Git LFS pointer stubs (fails at ~51%)

```
target Prebuilt: webview (.../webview_intermediates/package.apk)
zip2zip.go:82: zip: not a valid zip file
```

`external/chromium-webview/prebuilt/arm64/webview.apk` was a 134-byte LFS
pointer, not the 262MB APK. **`git-lfs` was not installed**, so `repo sync`
wrote stubs and reported success. `repo init --git-lfs` does nothing without the
binary present.

```bash
git lfs version || echo "install git-lfs FIRST"
cd external/chromium-webview/prebuilt/arm64 && git lfs pull
cd ../arm && git lfs pull
```

Nothing validates prebuilt integrity at sync time, so this stays invisible until
something opens the file as a zip — 51% into a build.

### 3. repo config cache vs the build sandbox

```
OSError: [Errno 30] Read-only file system: '/home/<user>/.repo_.gitconfig.json'
```

Not a disk fault. The AOSP build sandbox mounts `/` read-only and binds only
`/tmp` and the source/out dirs read-write. `repo manifest` caches `~/.gitconfig`
keyed on mtime; installing git-lfs (fix #2) rewrote `~/.gitconfig`, invalidating
that cache, and the next refresh happened *inside* the sandbox.

Fix — re-warm the cache outside the sandbox, then confirm it's stable:

```bash
cd src && python3 .repo/repo/repo manifest -o - -r >/dev/null
# run again; ~/.repo_.gitconfig.json mtime must not change
```

**General rule: after any change to `~/.gitconfig`, re-warm before building.**

### 4. SIGHUP kills a backgrounded build

A build started as a plain `&` background job dies to SIGHUP when its parent
shell exits — silently, ~80 seconds in, with no `FAILED:` line in the log. Use
`setsid` (and `trap '' HUP`, as `start_build.sh` does).

## Notes

- Do **not** add `set -u` to the build script — `build/envsetup.sh` references an
  unbound `TOP` and aborts under `nounset`, silently producing an `rc=127` no-op
  build that looks like it ran.
- `lineage_zenlte-ota.zip` in the output dir is a hardlink to the same file as
  the dated zip, not a second artifact.
- LineageOS 21 does not generate a `.md5sum` for the ROM zip; verify with sha256.
- **Android 14 is the ceiling for this device.** Every repo in the
  samsungexynos7420 org tops out at `lineage-21.0-unify` — there is no
  `lineage-22` branch anywhere, including forks. The org is actively maintained
  (pushes within the last week), so this is a deliberate stopping point, not
  abandonment.

## Credits

All device, kernel, and vendor work is by the
[samsungexynos7420](https://github.com/samsungexynos7420) maintainers. This repo
only contains build fixes and a compiled artifact.
