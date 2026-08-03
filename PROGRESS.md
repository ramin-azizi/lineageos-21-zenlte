# S6 Edge+ (zenlte) LineageOS 21 Build — Progress

**Status (2026-08-02): v1 built OK but bootlooped on hardware — f2fs kernel panic on /data and /cache. Fixed by dropping the f2fs fstab entries; v2 full rebuild in progress. See the 2026-08-02 section at the end of this file — and note that zenlte uses the `.noble` fstab, not `.zero`.**

**Earlier status: VINTF FCM-level build failure at 77% diagnosed and FIXED (2026-08-01). Read the FCM block below before touching `device/samsung/zenlte/manifest.xml`.**

## HANDOVER — VINTF FCM level mismatch at 77% — FIXED (2026-08-01)

### The failure

Build died at `[77% 58061/75096]` on the only failing target, with 0 other errors:

```
FAILED: out/target/product/zenlte/gen/ETC/vendor_manifest.xml_intermediates/manifest.xml
  assemble_vintf -i device/samsung/universal7420-common/manifest.xml:device/samsung/zenlte/manifest.xml
Inconsistent FCM Version in HAL manifests:
    File 'device/samsung/universal7420-common/manifest.xml' has level 5
    File 'device/samsung/zenlte/manifest.xml' has level 3
```

### Root cause — a missed upstream cherry-pick, NOT a real HAL incompatibility

`.repo/local_manifests/universal7420.xml` pins `device/samsung/universal7420-common` to
`lineage-21.0-unify` but `device/samsung/zenlte` to `lineage-20.0-unify`. That pin is
**correct and unavoidable** — the zenlte repo has no lineage-21 branch at all
(`lineage-18.1-unify`, `lineage-19.1`, `lineage-19.1-unify`, `lineage-20.0-unify` only).

Two facts make this benign:

1. **`device/samsung/zenlte/manifest.xml` is an empty shell.** Since
   `5b10f3e "zero: move manifest to common"` (Aug 2023) all 284 lines of HAL entries were
   moved into the common tree. The device file's entire content was:
   ```xml
   <manifest version="1.0" type="device" target-level="3">
   </manifest>
   ```
   It declares **zero HALs**. Its only effect on the build is to assert an FCM level.
2. **The common tree's jump to level 5 was a late, LOS21-only change.** Both trees went
   `legacy -> 3` together in Sept 2022. The common tree then went `3 -> 5` in
   `45e54e3 "Import A51 S RIL stack"` (Aug 2025, `lineage-21.0-unify` only — the common
   repo's own `lineage-20.0-unify` branch still says 3). No matching commit reached zenlte,
   because zenlte has no LOS21 branch to receive it.

### Decisive evidence — the sibling device shows the exact intended fix

`noblelte` (Galaxy Note5, same universal7420, identical empty-shell manifest) **does** have a
`lineage-21.0-unify` branch. On it, commit
`eb21caff "universal7420: Uprev manifests/FCM level — Legacy targets are not allowed anymore"`
(committed 2025-12-04) is literally:

```diff
-<manifest version="1.0" type="device" target-level="3">
+<manifest version="1.0" type="device" target-level="5">
 </manifest>
```

So the org's own answer to this exact situation, on the branch we would be tracking if it
existed, is a bare `3 -> 5` bump on the empty shell. (`zeroflte`/`zerolte` also sit at level 3
but only have `lineage-20.0-unify` branches, so they show the pre-fix state, not a
contradiction. They additionally carry an IR-blaster HAL entry that zen/noble do not.)

### The change applied

`src/device/samsung/zenlte/manifest.xml`:

```diff
-<manifest version="1.0" type="device" target-level="3">
+<manifest version="1.0" type="device" target-level="5">
 </manifest>
```

That is the **only** change. `BoardConfig.mk` was not touched — its
`DEVICE_MANIFEST_FILE += $(DEVICE_PATH)/manifest.xml` is fine and matches noblelte.

### Why this cannot mask a real HAL incompatibility (verified, not assumed)

The concern with an FCM `target-level` bump is that it is a compatibility *assertion* — a
higher level can demand newer mandatory HAL versions and cascade into missing-HAL errors.
That risk is **structurally absent here**, and it was proven empirically:

1. Re-ran the exact failing `assemble_vintf` command by hand after the edit: **rc=0**.
2. Diffed the merged output against `assemble_vintf` run on the common manifest *alone*:
   **byte-identical** (`<manifest version="8.0" type="device" target-level="5">`, same HAL set).

Because the device manifest is content-free, bumping it to 5 is exactly equivalent to
deleting it from `DEVICE_MANIFEST_FILE` entirely. It adds **no** new HAL requirement — the
level-5 assertion was already being made by the common tree; the stale device file was only
blocking the *merge*. Any level-5 compatibility obligation that exists, existed before this
change.

### Alternatives considered and rejected

- **Repoint zenlte to `lineage-21.0-unify`** — impossible, the branch does not exist.
- **Downgrade the common tree to level 3** — wrong direction; would revert the deliberate
  LOS21 RIL uprev (`45e54e3`) that the rest of the LOS21 tree depends on.
- **Delete the zenlte manifest / drop it from `DEVICE_MANIFEST_FILE`** — functionally
  identical (proven above) but diverges from what upstream noblelte does. Bumping keeps us
  byte-compatible with the org's own LOS21 device tree.

### Restart confirmed past the failure

Relaunched via `setsid nohup bash start_build.sh ... & disown` at 2026-08-01T15:57:28Z.
Log: `logs/build_20260801T155728Z.log` (`build_latest.log` repoints to it).

Ninja recomputed **17,036 remaining** targets (matching the 75,096 - 58,061 left over from the
failed run — `out/` was correctly reused, nothing rebuilt from scratch). The previously-failing
target built successfully as step **25/17036**:

```
[  0% 25/17036] build out/target/product/zenlte/gen/ETC/vendor_manifest.xml_intermediates/manifest.xml
```

Artifact written, 5183 bytes, header `<manifest version="8.0" type="device" target-level="5">`.
Build then continued cleanly past it — 0 `FAILED:` blocks, 0 `error:` lines, progressing normally
(21% 3668/17036 ≈ 61,729/75,096 in original terms). Disk: 595G free. Do not restart it.

### Caveat for future sessions

`device/samsung/zenlte` is a repo-managed **detached HEAD**. A future `repo sync` will
discard this edit and the build will fail at 77% again in the same way. If you sync, re-apply
the one-line bump. Do **not** "fix" it by editing the common tree or the local manifest.

---

## HANDOVER — disk expansion mid-build (2026-08-01, later session)

### What happened

The baseline build (`breakfast zenlte`, resolving to `lunch lineage_zenlte-ap2a-userdebug` — `ap2a` is the only release LineageOS declares, matching `BUILD_ID=AP2A.240905.003`) reached **8% (15,348/180,457 targets)** with zero errors. But disk headroom on `/mnt/rom-data` was projected to run out: `out/` had already consumed 16GB at just 8%, leaving 86GB free, while a full LineageOS `out/` typically reaches 100-150GB plus extra headroom for the final `bacon` image/zip packaging step.

### Action taken

The build was cleanly stopped (SIGTERM, `out/` preserved — AOSP builds are incremental, so no work was lost). The dedicated ext4 VHD was expanded:

- `E:\WSL-data\rom-project.vhdx` grown 300GB -> 500GB via `Resize-VHD` in an elevated Windows PowerShell (the Hyper-V PowerShell module is available on this machine — cleaner than the diskpart `expand vdisk` fallback).
- Remounted with `wsl --mount --vhd "E:\WSL-data\rom-project.vhdx" --bare`.
- Filesystem grown with `sudo resize2fs /dev/sdd` run by the user inside a real Ubuntu terminal. The ext4 lives directly on the raw disk with **no partition table**, so this was a single resize2fs with no partition juggling.
- Result: `/mnt/rom-data` went from 295G total / 86G free to **492G total / 275G free**.

### Gotcha on restart — do not "fix" this

After the WSL restart, the first `breakfast zenlte` `check_product` call failed on a cold soong cache, which made `breakfast` fall through to `roomservice.py`. That printed alarming-but-harmless errors:

```
Default revision lineage-21.0 not found in android_device_samsung_zenlte. Bailing.
Repository for zenlte not found in the LineageOS Github repository list.
```

This is **expected, not a failure** — the zenlte device tree comes from the `samsungexynos7420` org, not LineageOS's official repo list. `breakfast` retries `check_product` after roomservice fails and succeeds on the retry. Verified afterward that `.repo/local_manifests/universal7420.xml` was **not** modified and no `roomservice.xml` was written, so the manifest is intact. Future sessions should not "fix" this warning.

Also note the known-harmless `build/make/core/config.mk:803: warning: This device does not have Treble enabled` message so nobody chases it.

### Current state

Build restarted and confirmed compiling again (soong glob regeneration -> Kati parsing -> ninja), 0 errors, ~275GB free. Log: `~/android/s6edgeplus-los-build/logs/build_latest.log` (symlink to the newest timestamped `build_*.log`); PID recorded in `logs/build.pid`. An automated monitor checks build progress + disk every 13 minutes.

### Post-build follow-ups

**Reclaiming VHD space after the build (deferred, do NOT do while building):**

The VHD `E:\WSL-data\rom-project.vhdx` is **dynamic** — it grows as data is written but never shrinks on its own. Verified 2026-08-01: 197GB of data inside the filesystem = 211GB `.vhdx` file on disk (the delta is ext4 metadata/overhead). When `out/` (100-150GB) is eventually deleted, the filesystem will show the space free but the `.vhdx` file will stay at its high-water mark on E:.

Current state of the reclaim machinery (checked 2026-08-01):
- `/dev/sdd` DOES advertise TRIM support (`lsblk -D` shows DISC-GRAN 32M, DISC-MAX 4G) — so hole-punching is possible.
- `/mnt/rom-data` is mounted WITHOUT the `discard` option, so deletions currently send no TRIM hints.
- `fstrim` is installed at `/usr/sbin/fstrim` but NO `fstrim.timer` is scheduled (`systemctl list-timers fstrim.timer` returns 0 timers).

Recommended follow-up once the build is done and it's decided what to keep:
1. Run a one-off reclaim: `sudo fstrim -v /mnt/rom-data`
2. Enable ongoing weekly reclaim: `sudo systemctl enable --now fstrim.timer`
3. Optionally, for a full compaction of the file on the Windows side (needs elevated PowerShell, WSL shut down):
   ```powershell
   wsl --shutdown
   Optimize-VHD -Path "E:\WSL-data\rom-project.vhdx" -Mode Full
   ```

Explicitly **do not** add the `discard` mount option to `/mnt/rom-data` — continuous TRIM adds I/O overhead on every file deletion, which is a bad trade on an AOSP build tree that creates and destroys millions of files. Periodic `fstrim` is the better approach.

No urgency: E: had 526GB free as of 2026-08-01.

---

## BASELINE BUILD LAUNCHED AND CONFIRMED COMPILING (2026-08-01, build session)

**Status: build is running detached and healthy. Do not restart it.**

### The lunch-combo problem — solved

Android 14 / LineageOS 21 requires the 3-part combo `<product>-<release>-<variant>`, so the old
`lunch lineage_zenlte-userdebug` is rejected. The correct release token for a LineageOS device
build is **`ap2a`** (matching `BUILD_ID=AP2A.240905.003`). Evidence:

- `vendor/lineage/release/release_config_map.mk` declares exactly one release config:
  `$(call declare-release-config, ap2a, .../build_config/ap2a.scl)` — and `build_config/` contains
  only `ap2a.scl`. There is no LineageOS-specific release name; `trunk_staging` is AOSP-side only.
- `vendor/lineage/vars/aosp_target_release` contains `aosp_target_release=ap2a`.
- `vendor/lineage/build/envsetup.sh` `breakfast()` sources that var and runs
  `lunch lineage_$target-$aosp_target_release-$variant`, defaulting variant to `userdebug`.

**So `breakfast zenlte` builds the combo automatically — no hand-constructed string needed.**
Equivalent explicit form: `lunch lineage_zenlte-ap2a-userdebug`.

Verified config resolution (exit 0):
`TARGET_PRODUCT=lineage_zenlte  TARGET_RELEASE=ap2a  TARGET_BUILD_VARIANT=userdebug`
`LINEAGE_VERSION=21.0-20260801-UNOFFICIAL-zenlte`, `TARGET_ARCH=arm64`.

### Exact invocation used

```bash
cd ~/android/s6edgeplus-los-build/src
nohup bash -c 'source build/envsetup.sh && breakfast zenlte && mka bacon' \
  > ~/android/s6edgeplus-los-build/logs/build_20260801-111107.log 2>&1 &
```

- **Log:** `~/android/s6edgeplus-los-build/logs/build_20260801-111107.log`
  (symlink `~/android/s6edgeplus-los-build/logs/build_latest.log` points at it)
- **PID (wrapper):** `10756` — also written to `~/android/s6edgeplus-los-build/logs/build.pid`
- **PID (soong_ui):** `11349`
- To kill: `kill $(cat ~/android/s6edgeplus-los-build/logs/build.pid)` then
  `pkill -f soong_ui; pkill -f "mka bacon"`

### Health verification (~18 min in)

Progressed cleanly through all three stages — this is a real build, not a config stall:
1. Soong bootstrap: `1167/1167`, `cp out/host/linux-x86/bin/soong_build`.
2. Soong analysis: `analyzing Android.bp files and generating ninja file` completed; Kati
   legacy Make parsing completed and emitted `out/build-lineage_zenlte.ninja`.
3. Ninja: **`[7% 13950/180457]`** — real module compilation (clang++ on `external/protobuf`,
   `external/libcxx`; turbine on `frameworks/base`, androidx prebuilts).

**Zero build errors so far** (`grep -c "error:"` = 0; the only "error" hits in the log are
filenames like `error_prone`/`system_error.cpp`). Only warning is the known, expected
`config.mk:803: This device does not have Treble enabled` — normal for this legacy device.

### Watch items for whoever checks next

1. **Disk space is the main risk.** `/mnt/rom-data` was 109G free at launch, 95G free at 7%.
   A full LineageOS 21 `out/` is typically 90-150GB. **It may run out before finishing.**
   Check with `df -h /mnt/rom-data`; if it fills, the fix is to free space on the ext4 VHD
   (or `export OUT_DIR` elsewhere), not to change build config.
2. Expected wall time on 24 cores / 31GB RAM: roughly 3-6 hours for a first cold build.
3. If it does fail, check for duplicate-symbol / duplicate-rule errors in `system/*` or
   `build/make` first — see risk note 2 in the patching handover below.
4. Success artifact will be `out/target/product/zenlte/lineage-21.0-*-UNOFFICIAL-zenlte.zip`.

---


**Status: BASELINE BUILD RUNNING (launched 2026-08-01). Patching complete. Read the BASELINE BUILD block first.**

## HANDOVER — patch conflicts RESOLVED (2026-08-01, later session)

### Headline: the "5 conflicting repos" were mostly a false alarm

The prior session's "live branch drift" theory was **wrong**. The real cause: **the LineageOS `lineage-21.0-unify` branches for 4 of those 5 repos already carry the entire 7420 patch series upstream.** The patches "conflicted" because they were *already applied* — `git am` was trying to add lines that were already there and remove lines already gone.

This was proven conclusively with `git patch-id --stable`, comparing each `.patch` file against the patch-ids of the repo's recent commits. **Every single patch in those 4 repos matched an existing commit byte-for-byte** (identical diff content, not just a similar subject line):

| Repo | Patches | Result |
|---|---|---|
| frameworks/base | 6/6 | all 6 patch-ids matched existing commits — already applied upstream |
| frameworks/native | 14/14 | all 14 matched — already applied upstream |
| packages/modules/Connectivity | 14/14 | all 14 matched — already applied upstream |
| packages/modules/NetworkStack | 9/9 | all 9 matched — already applied upstream |

**No action was taken on these 4 repos and none is needed.** They are at their pristine synced HEADs, clean, and already contain every 7420 change. Attempting to force-apply the patches would have *duplicated* the changes and broken the build.

(Note: the earlier per-patch `git apply --reverse --check` probe showed some mid-series patches as "NEITHER" — that is expected and not evidence of a problem, because a later patch in the same series edits the same lines, so an isolated reverse-check of an earlier patch can't succeed. patch-id matching is the correct test and it was unambiguous.)

### bionic — the one repo that genuinely needed patching (now DONE)

bionic was the real case: **0 of 9** patches were present in the tree. Resolved as follows.

- **0001–0007: applied cleanly** via `git am`.
- **0008 `Revert "Implement per-process target SDK version override."`: SKIPPED (`git am --skip`) — verified no-op.** Reasoning, three independent confirmations:
  1. `linker/Android.bp` `linker_defaults` already lists only `shim_libs_defaults`; the string `process_sdk_version_overrides_defaults` **does not exist anywhere in the bionic tree**.
  2. `linker/linker.cpp:3719` is already the post-revert form — `set_application_target_sdk_version(config->target_sdk_version());` — and `SDK_VERSION_OVERRIDES` appears **0 times** in the file.
  3. The commit the patch claims to revert (`36a170e9632e20bc4b2f63c2972bd59a393bc16e`) **is not in this repo's history at all** (`git cat-file` fails, no matching log entry).
  The feature being reverted was never in LineageOS 21's bionic, so the revert has nothing to do. Skipping is correct and carries no behavioral risk.
- **0009 `Reapply "Rewrite renameat()."`: applied cleanly** after the skip.

**Net result: 8 of 9 bionic patches applied, 1 verified-no-op skipped, tree clean.**

Sanity check on bionic's net diff vs the pre-patch baseline (`c9fb1e864`) confirms the series' self-cancelling pairs cancelled correctly — 0004 `Switch to jemalloc` / 0007 `Revert Switch to jemalloc` and 0006 `Revert Rewrite renameat` / 0009 `Reapply Rewrite renameat` both net out to zero (`git diff` on `renameat.cpp`/`SYSCALLS.TXT` is empty, no jemalloc churn). The only surviving changes are the 5 effective ones:

```
 libc/bionic/pthread_mutex.cpp |  22 +-      (pre-P mutex behavior)
 libc/dns/net/getaddrinfo.c    |  10 +
 libc/dns/net/hosts_cache.c    | 547 ++++++  (hosts file cache)
 libc/dns/net/hosts_cache.h    |  23 ++
 libc/dns/net/sethostent.c     |   7 +
 libc/include/arpa/inet.h      |   1 +
 libc/include/bits/in_addr.h   |   3 +-
 libc/include/inaddr.h         |  36 ++      (inaddr.h header)
 8 files changed, 639 insertions(+), 10 deletions(-)
```

### Final state — all 12 repos

All 12 verified `dirty=0`, no `git am` in progress, no half-applied state:

| Repo | State |
|---|---|
| bionic | **PATCHED this session** — 8/9 applied, 0008 skipped (verified no-op) |
| build/make | patched (prior session) |
| frameworks/base | already patched upstream — no action needed |
| frameworks/native | already patched upstream — no action needed |
| packages/modules/Connectivity | already patched upstream — no action needed |
| packages/modules/DnsResolver | patched (prior session) |
| packages/modules/NetworkStack | already patched upstream — no action needed |
| system/bpf | patched (prior session) |
| system/core | patched (prior session) |
| system/libhwbinder | patched (prior session) |
| system/netd | patched (prior session) |
| system/security | patched (prior session) |

**Nothing is blocked. No repo is in a silent partial state.**

### Risks / things to watch before and during the build

1. **bionic is on a detached HEAD** (`## HEAD (no branch)`, tip `d2e1e6ba0`). This is normal for `repo`-managed projects, but it means **any future `repo sync` will discard the 8 hand-applied bionic commits.** If a sync becomes necessary, re-run the bionic patch procedure documented above afterwards. Consider `git branch 7420-patched` in `src/bionic` to make the work recoverable.
2. **The 7 "prior session" repos were not re-verified for double-application this session** beyond confirming they are clean with the expected patch commits on top. Given that 4 other repos turned out to already carry their patches upstream, it is *possible* one of the 7 had a patch applied on top of an equivalent upstream change. This did not produce conflicts (git would generally have complained), and no action is proposed, but if the build shows odd duplicate-symbol or duplicate-rule errors in `system/*` or `build/make`, check there first.
3. The skipped bionic 0008 is the only judgement call made. It is low-risk (the code it targets does not exist), but it is the single thing to revisit if the linker misbehaves on-device.

### Next steps

1. Confirm the exact build target from `device/samsung/zenlte/lineage.mk` / `vendorsetup.sh` — **do not assume `brunch zenlte` is right.**
2. `cd ~/android/s6edgeplus-los-build/src && source build/envsetup.sh && brunch <confirmed-target>`.

---

## Earlier handover (2026-08-01, superseded by the block above)

### Storage note (supersedes older handover entries below)
The distro/disk-relocation saga below (C: -> D: -> ...) is **obsolete**. Final, current layout: main Ubuntu WSL distro is back on **`C:\WSL\Ubuntu`** (fast NVMe, small footprint), and a dedicated **300GB ext4 VHD at `E:\WSL-data\rom-project.vhdx`** (label `romdata`) is mounted at `/mnt/rom-data`, holding this project via a symlink (`~/android/s6edgeplus-los-build -> /mnt/rom-data/s6edgeplus-los-build`). See `~/android/s6edgeplus-los-build/CLAUDE.md` for full mount/recovery mechanics. Do not act on the older "move to D:" instructions further down this file.

### Where things stand
- `repo sync` is confirmed complete and healthy (log ends "repo sync has finished successfully."; `.repo/` ~80GB, `/` has 883GB free).
- Cloned `samsungexynos7420/7420_patches` @ `lineage-21` lives at `~/android/s6edgeplus-los-build/7420_patches/` (persists — inside the project dir, not scratch).
- Patch application attempted against the current synced tree. **7 of 12 repos applied cleanly, 5 have real conflicts:**

| Patch dir | Target path | Result |
|---|---|---|
| bionic | `src/bionic` | **CONFLICT** — patch 0008 fails at `linker/Android.bp:76` / `linker/linker.cpp:3716` |
| build_make | `src/build/make` | OK (1 patch) |
| frameworks_base | `src/frameworks/base` | **CONFLICT** — patch 0001 fails at `core/jni/com_android_internal_os_Zygote.cpp:1968` |
| frameworks_native | `src/frameworks/native` | **CONFLICT** — patch 0001 fails at `services/gpuservice/gpuservice.rc:2` |
| packages_modules_Connectivity | `src/packages/modules/Connectivity` | **CONFLICT** — patch 0001 fails at `Tethering/apex/Android.bp:19` (also `Tethering/apex/out-of-process: already exists in index`) |
| packages_modules_DnsResolver | `src/packages/modules/DnsResolver` | OK (1 patch) |
| packages_modules_NetworkStack | `src/packages/modules/NetworkStack` | **CONFLICT** — patch 0001 fails at `TcpSocketTracker.java:148` and the paired test file |
| system_bpf | `src/system/bpf` | OK (1 patch) |
| system_core | `src/system/core` | OK (3 patches) |
| system_libhwbinder | `src/system/libhwbinder` | OK (1 patch) |
| system_netd | `src/system/netd` | OK (3 patches) |
| system_security | `src/system/security` | OK (1 patch) |

All 5 failed repos were confirmed reverted cleanly via `git am --abort` (0 dirty entries, HEAD back at the pristine synced commit) — nothing is left half-patched.

**Important: tried both plain `git am` and `git am --3way` on the 4 non-bionic conflicts — both fail identically with real content conflicts (not a `--3way` artifact).** This means the source tree these patches were written against has genuinely drifted from what's currently synced — likely because `7420_patches` pins no exact base commit and the manifest tracks live branches (`lineage-21.0-unify`/`lineage-21`), so upstream commits landed on those branches between when the org wrote these patches and when we synced. This is the same category of problem already diagnosed for bionic in the prior session (see below) — now confirmed to affect 4 more repos too.

### What resuming requires
This is source-conflict diagnosis across 5 repos, not routine setup — **per PROMPT.md's model guidance, do this at Opus/high, not Sonnet.** For each of bionic, frameworks_base, frameworks_native, packages_modules_Connectivity, packages_modules_NetworkStack:
1. Inspect the failing patch (`git am --show-current-patch=diff` after re-attempting, or read the `.patch` file directly) against the current file content at the stated line.
2. Determine whether the revert/change is already effectively present upstream (safe to skip) or needs manual hand-application.
3. Apply by hand (`git apply --reject` + manual fixup, or hand-edit + `git am --continue`) or explicitly skip with reasoning recorded here.
4. Re-run remaining patches in that repo's series after resolving the blocker (git am stops mid-series on first conflict — 0002+ in each repo haven't been attempted yet).

Logs for every attempt are in `~/android/s6edgeplus-los-build/logs/patch_apply_*.log` and `patch_apply_*_retry.log`.

### Next steps once all 12 are patched
1. **Switch to Opus/high** (already required for the conflict resolution above — carry it through) before attempting the baseline build.
2. `cd ~/android/s6edgeplus-los-build/src && source build/envsetup.sh && brunch zenlte` — but confirm the exact lunch/brunch target name from `device/samsung/zenlte/lineage.mk`/`vendorsetup.sh` first, don't assume `zenlte` is exactly right.

---

## Earlier history (superseded, kept for reference)

Prior session (2026-07-31 ~22:31 UTC) got 11/12 patched cleanly with only bionic blocked, on what was then a D:-resident disk. Between then and now the distro moved again (D: -> C: for the main distro, dedicated E: VHD for project data — see storage note at top) and 4 additional repos that previously applied cleanly now conflict too, consistent with the "live branch drift" theory above rather than anything disk-move-related.

Phase 1 recon, environment setup, and the original C:->D: disk relocation handover are unchanged from before and omitted here for brevity — git history of this file (if ever committed) or ask for the full prior text if needed.

## 2026-08-01 (evening) — three build failures, all fixed

1. **77% `assemble_vintf`** — "Inconsistent FCM Version": common tree level 5 vs
   zenlte device tree level 3. The zenlte manifest is an empty shell (all HALs
   moved to the common tree in 2023); the common tree went 3->5 in Aug 2025 on
   `lineage-21.0-unify`, and zenlte never got the matching commit because it has
   no LOS21 branch. Fixed by `target-level` 3->5 in
   `src/device/samsung/zenlte/manifest.xml`, matching upstream's own `noblelte`
   commit `eb21caff`. Verified no HAL cascade: merged output is byte-identical to
   running assemble_vintf on the common manifest alone.
   **NOTE: repo-managed detached HEAD — a future `repo sync` will discard this.**

2. **51% `zip2zip: not a valid zip file`** — `external/chromium-webview/prebuilt/
   arm64/webview.apk` was a 134-byte Git LFS pointer, not the 262MB APK.
   `git-lfs` was never installed, so `repo sync` silently wrote pointer stubs.
   Fixed by installing the git-lfs 3.7.1 binary to `~/bin` (NOT via apt --
   sudo hangs on a password prompt non-interactively) and running `git lfs pull`
   in the arm64 and arm prebuilt repos.

3. **18% `build-manifest.xml`** — `repo manifest` failed with
   "OSError: [Errno 30] Read-only file system: '/home/ramin/.repo_.gitconfig.json'".
   NOT a disk fault: /home is rw, no ext4 errors. This is the AOSP build sandbox,
   which mounts / read-only and binds only /tmp and the source/out dirs rw.
   Root cause: step 2's `git lfs install` added `filter.lfs.*` entries to
   `~/.gitconfig`, invalidating repo's mtime-keyed cache of it; the next
   `repo manifest` ran inside the sandbox and could not rewrite the cache.
   Fixed by running `python3 .repo/repo/repo manifest -o - -r` once from `src/`
   OUTSIDE the sandbox to re-warm `~/.repo_.gitconfig.json`.
   **General rule: after ANY change to `~/.gitconfig`, re-warm the repo cache
   outside the sandbox before building, or this recurs.**

## 2026-08-01 17:54 — BUILD COMPLETE

`out/target/product/zenlte/lineage-21.0-20260801-UNOFFICIAL-zenlte.zip`
853 MB (893,733,417 bytes), rc=0, zero errors. `lineage_zenlte-ota.zip` is a
hardlink to the same file (note the link count of 2), not a second artifact.

Also produced, for flashing via Odin/Heimdall download mode (this is a Samsung —
there is no fastboot):
  - `recovery.img`  (31.7 MB)  -- LineageOS recovery, built from this same tree
  - `boot.img`      (24.8 MB)
  - `dt.img`        (190 KB)   -- the separated device tree that needed dtbTool
  - `system.img`    (2.23 GB)

Final run: 16:30:19Z -> 16:54:01Z (23m 42s) for the last 6,799 targets.
Total across all runs this session: 162,274 targets.

No md5sum file was generated (`.zip.md5sum` absent) -- LineageOS 21 does not
produce one by default. Verify by size/sha256 if copying to another machine.

---

## 2026-08-02 — f2fs kernel panic on /data and /cache — FIXED (v2 build)

### The failure (observed on real hardware, not speculation)

The v1 ROM from 2026-08-01 bootlooped on every boot. Kernel log:

```
Kernel panic - not syncing: Fatal exception
PC is at update_sit_entry+0x68/0x354
Call trace: update_sit_entry / refresh_sit_entry / allocate_data_block /
  f2fs_write_data_pages / write_checkpoint / f2fs_sync_fs / f2fs_sync_file /
  SyS_fdatasync
```

This is the 3.10 Exynos7420 kernel's f2fs implementation dying inside the
segment-info-table update during a checkpoint write. Any `fdatasync()` on an
f2fs mount can trigger it, so the device panics as soon as early boot does real
I/O on `/data`.

### Why a factory reset could not fix it

`fs_mgr` walks the fstab in order and formats/mounts the **first** entry matching
a mount point. Both `/cache` and `/data` listed **f2fs first**, ext4 second, so
every wipe reformatted both partitions straight back to f2fs. Hand-converting
both to ext4 on the device made it boot reliably — confirming the diagnosis and
the fix.

### The fix

Deleted the two f2fs lines (`/cache` and `/data`) from the universal7420 fstabs,
leaving the pre-existing ext4 entries as the only match. **ext4 flags were not
otherwise touched.**

### IMPORTANT — zenlte uses the `.noble` fstab, NOT `.zero`

This is easy to get wrong and was initially mis-stated in the task brief.
`BoardConfigCommon.mk:155` and `ramdisk/Android.mk:6` both switch on the same
device filter:

```
ifneq ($(filter noblelte ... zenlte zenltecan ... zenltezt,$(TARGET_DEVICE)),)
  -> fstab.samsungexynos7420.noble
else
  -> fstab.samsungexynos7420.zero
endif
```

`zenlte` (PRODUCT_DEVICE in `lineage_zenlte.mk:32`, SM-G928F) is **inside** that
list, so it takes the `.noble` branch. Line 158's `.zero` assignment is the
`else` branch and is dead code for this device. The same conditional governs
both `TARGET_RECOVERY_FSTAB` (recovery.fstab) and the `fstab.samsungexynos7420`
prebuilt installed to `/vendor/etc`, so one file drives both the ROM's runtime
fstab and recovery's — patching `.noble` fixes the ROM/recovery disagreement
that the hand-patched v1 phone had.

Both variants were patched anyway: `.noble` because it is what zenlte actually
builds (required), `.zero` because it carries the identical bug for the
zero-family (zeroflte/zerolte) devices and was explicitly requested. Patching
`.zero` is a no-op for this build.

Patch saved at `7420_patches_local/0001-fstab-drop-f2fs-for-data-and-cache.patch`
(apply with `git apply` from `src/device/samsung/universal7420-common`).
**NOTE: repo-managed tree — a future `repo sync` will discard this**, same
caveat as the manifest.xml FCM fix above.

### Acceptance criterion

Built `out/target/product/zenlte/recovery/root/system/etc/recovery.fstab` must
contain **zero** f2fs lines for `/data` and `/cache`.

### Pre-build verification (both still in place, tree was not re-synced)

- `device/samsung/zenlte/manifest.xml` — `target-level="5"` confirmed.
- `external/chromium-webview/prebuilt/arm64/webview.apk` — 262,187,199 bytes
  (real APK, not a 134-byte LFS pointer). arm variant 95,283,023 bytes.

### v2 BUILD COMPLETE — 2026-08-03T01:32:02Z, rc=0

Full build from an empty `out/`: 22:43:44Z -> 01:32:02Z (2h 48m), 180,457 ninja
targets, **0 FAILED targets**.

**Acceptance criterion PASSED — the fix is in the artifact.** Both generated
fstabs contain zero f2fs lines; `/cache` and `/data` are ext4-only:

- `out/target/product/zenlte/recovery/root/system/etc/recovery.fstab` — no f2fs
- `out/target/product/zenlte/system/vendor/etc/fstab.samsungexynos7420` — no f2fs
  (note: this device is non-Treble, so the vendor fstab lands under
  `system/vendor/etc`, NOT `vendor/etc` — the latter does not exist)

Recovery and ROM now agree on ext4, which the hand-patched v1 phone did not.

Artifacts copied to `/mnt/rom-data/artifacts/zenlte-v2/` with `SHA256SUMS.txt`:

```
aefd9dd2faec1323d3ddcf3c7177bfacf3947f41f0e20adcf246ff0c8af92ec1  lineage-21.0-20260802-UNOFFICIAL-zenlte.zip   893,798,998 B
62e1a9580e1e8ecf4a8472272f877ed57650d41fdf69dd6ed4238213784aa285  recovery.img                                   31,674,384 B
4a219db890307e172a1aa9c332757ada8190902d761aac18cd8fe5a1306688a8  boot.img                                       24,809,488 B
```

Log: `logs/build_20260802T224344Z.log`. Disk after build: 339 GB free.

**Flashing note (not done here — user flashes):** because `/data` and `/cache`
are currently f2fs-formatted on the phone from the hand-patch era, or may be, the
new recovery will now format them ext4. Nothing was flashed and nothing was
pushed to GitHub by this session.

---

# v3 — fix the f2fs bug at its root (2026-08-03)

v2 shipped ext4 and *avoided* f2fs. v3 fixes the actual defect and restores
f2fs as a working option, with ext4 kept as the default for safety.

## Root cause, restated

Two independent things had to be true for the panic, and both were:

1. **The formatter wrote a filesystem the kernel cannot parse.**
   `external/f2fs-tools` is 1.16.0. Invoked as `make_f2fs -g android` it enabled
   `EXTRA_ATTR` (0x0008) plus `PRJQUOTA`/`QUOTA_INO`/`VERITY`. The zenlte kernel
   is 3.10 and knows only `ENCRYPT` (0x0001) and `BLKZONED` (0x0002)
   — `kernel/.../include/linux/f2fs_fs.h:112-113` — and its `struct f2fs_inode`
   is the pre-4.14 fixed layout with **no `i_extra_isize`**.
   f2fs has no incompatible-feature gate, so the old kernel mounted it anyway.
   With `EXTRA_ATTR`, mkfs places block pointers at `i_addr[get_extra_isize()]`
   while the kernel reads `i_addr[0]` — so the kernel consumed *inode metadata
   as block addresses*.

2. **The kernel trusted those addresses without bounds-checking them.**
   `GET_SEGNO()` → `get_seg_entry()` → `&sit_i->sentries[segno]` with no check
   at all, ~700x out of bounds → the observed
   `update_sit_entry+0x68/0x354` paging-request panic on the first `fdatasync()`.

Corroboration: TWRP ships f2fs-tools **1.14.0**, whose `CONF_ANDROID` does not
set `EXTRA_ATTR` — which is exactly why TWRP-formatted f2fs worked.

## IMPORTANT — the brief's fix #1 alone would NOT have worked

Fixing only the `CONF_ANDROID` defaults leaves the bug fully intact, because
**both callers request the killer feature explicitly on the command line**:

- `system/core/fs_mgr/fs_mgr_format.cpp` — `fs_mgr_do_format()` sets
  `bool needs_projid = true;` unconditionally, so `format_f2fs()` always appends
  `-O project_quota,extra_attr`.
- `bootable/recovery/recovery_utils/roots.cpp` — `format_volume()` hardcodes the
  same `-O project_quota,extra_attr`.

So the authoritative fix is a **mask applied after getopt and after the
defaults** in `f2fs_parse_options()`, which catches every caller regardless of
what it asked for. The two callers were fixed as well (defence in depth), but
the mask is what actually guarantees it.

Also checked and cleared: `Android.bp` defines `-DCONF_CASEFOLD -DCONF_PROJID`
(which re-add `EXTRA_ATTR` outside the switch) **only** for the host-only
`make_f2fs_casefold` binary, not the on-device `make_f2fs`. No f2fs images are
built by this device (`BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4`).

## Changes (patches 0002–0006 in `7420_patches_local/`)

| # | Tree | Change |
|---|------|--------|
| 0002 | `external/f2fs-tools` | CONF_ANDROID keeps only ENCRYPT; **authoritative post-getopt feature mask** |
| 0003 | `system/core` | fs_mgr stops requesting `extra_attr`/`project_quota` for f2fs |
| 0004 | `bootable/recovery` | recovery stops requesting the same |
| 0005 | `device/samsung/universal7420-common` | f2fs restored for `/data` + `/cache`, **listed after ext4** |
| 0006 | `kernel/samsung/universal7420` | SIT bounds checks, checkpoint sanity check, `CONFIG_F2FS_CHECK_FS` off |

`0005` **supersedes `0001`** (which deleted the f2fs lines outright) — do not
apply both.

### Kernel hardening detail (0006)

- **`update_sit_entry()` bounds check — landed.** The most valuable change and
  the exact panic site. Returns early on `NULL_SEGNO`; refuses with
  `SBI_NEED_FSCK` when `segno >= MAIN_SEGS(sbi)`.
- **`sanity_check_ckpt()` — landed**, adapted from upstream `15d3042a937c`
  (CVE-2017-10663). Adapted, not applied blind: `MAIN_SEGS()`/`SM_I()` are not
  usable there (segment manager isn't built until *after* `get_valid_checkpoint()`),
  so the raw superblock `segment_count_main` is used, as upstream does.
  `sbi->blocks_per_seg` *is* valid there because `init_sb_info()` (super.c:1956)
  runs before `get_valid_checkpoint()` (super.c:1977).
- **`build_sit_entries()` SIT-journal bounds check — landed**, in the spirit of
  `b2ca374f33bd`. **This exposed a second, real, independent OOB bug**: the main
  SIT loop is bounded by `start < MAIN_SEGS(sbi)`, but the journal loop below took
  the segno straight from disk and indexed `sentries[]` unchecked.
  `check_block_count()` is too late — the bad pointer is already formed.
  Function changed `void` → `int` so the mount fails cleanly.
- **`CONFIG_F2FS_CHECK_FS=y` → not set — judgement call, landed.** With it on,
  `f2fs_bug_on()` is a bare `BUG_ON()`, i.e. f2fs *deliberately panics* on any
  detected inconsistency — which flatly contradicts the "never panic" goal and
  would have kept panicking even with the bounds checks (e.g. the `new_vblocks`
  assertion a few lines below the fix). Off = `WARN_ON()` +
  `SBI_NEED_FSCK`, the upstream/AOSP production setting. Easiest change to
  revert: one line in `exynos7420-zenlte_defconfig`.

Nothing was skipped for being unadaptable.

## Empirical proof of the root-cause fix (not just a source grep)

Host `make_f2fs` was built and run with the **exact fs_mgr command line** against
a 4 GB image:

```
$ make_f2fs -g android -O project_quota,extra_attr -w 4096 -b 4096 img.bin 1048576
Info: zenlte: dropping f2fs feature bits 0x0098 unsupported by this device's 3.10 kernel
...
Info: format successful
```

`0x0098` = `QUOTA_INO|PRJQUOTA|EXTRA_ATTR` — i.e. without the mask the on-disk
`feature` would have been `0x0099` and the kernel would have panicked.
Parsing the resulting superblock (offset validated by checking
`magic=0xf2f52010` and `root/node/meta_ino = 3/1/2`):

```
feature offset = 2180
feature = 0x0001   -> ENCRYPT only
EXTRA_ATTR set?          False
only kernel-known bits?  True
```

(The first attempt at this parse used a wrong offset — 2188 — and reported
`feature = 0x0000`. The offset chain was then validated independently against
`magic = 0xf2f52010` and `root/node/meta_ino = 3/1/2`, which located `feature`
at 2180. The `version` string sits immediately before it, confirming the spot.)

## v3 BUILD COMPLETE — 2026-08-03T03:19:12Z, rc=0

Incremental from the v2 `out/`: 02:22:32Z → 03:19:12Z (**57 min**, vs 2h48m cold),
**0 FAILED targets**. A second unrelated build (`sanders-los22-build`) was running
concurrently and competing for CPU.

### Acceptance criteria — each verified, none assumed

**1. `grep -c EXTRA_ATTR` in the CONF_ANDROID block == 0 — met in substance,
   with a caveat stated plainly.** The literal grep returns **2**, and both hits
   are in the *explanatory comment* I added. No code in that block sets the bit:

```
=== every line mentioning EXTRA_ATTR in the CONF_ANDROID block ===
  21:  * Stamping EXTRA_ATTR makes mkfs write block pointers at
  32:  * PRJQUOTA implies EXTRA_ATTR.

=== the only |= of EXTRA_ATTR left in the whole file ===
188:  c.feature |= F2FS_FEATURE_EXTRA_ATTR;      <- inside #ifdef CONF_PROJID
```

Line 188 is inside `#ifdef CONF_PROJID`, which `Android.bp` defines **only** for
the host-only `make_f2fs_casefold` binary (lines 194/197), never for the
on-device `make_f2fs`. And even there, the post-getopt mask would strip it.
I chose not to reword the comments purely to make a grep return zero — the
explanation is worth more than the literal count, and a rebuild for a comment
change would have invalidated the shipped hashes.

**2. Both built fstabs list ext4 before f2fs — PASSED.** Identical in both, so
recovery and ROM agree:

```
out/.../recovery/root/system/etc/recovery.fstab
out/.../system/vendor/etc/fstab.samsungexynos7420
  /cache ext4 ...
  /cache f2fs ...
  /data  ext4 ...
  /data  f2fs ...
```

Also confirmed the entries are **consecutive per mount point**, which `fs_mgr`
explicitly requires ("We required that fstab entries for the same mountpoint be
consecutive", `mount_with_alternatives`, fs_mgr.cpp:945).

**3. Kernel — all three backports landed, none skipped.** Proven from the *built*
binary, not the source tree:

```
KERNEL_OBJ/.config:  CONFIG_F2FS_FS=y
                     # CONFIG_F2FS_CHECK_FS is not set
strings KERNEL_OBJ/arch/arm64/boot/Image:
  "update_sit_entry: bad segno"    x1
  "Wrong journal entry on segno"   x1
  "Wrong checkpoint: node segno"   x1
```

(v2 baseline for comparison: `CONFIG_F2FS_CHECK_FS=y`, zero occurrences of all
three strings.) The same strings are present in the built `recovery.img`.

**4. ROM zip produced.**

```
lineage-21.0-20260803-UNOFFICIAL-zenlte.zip   893,769,353 B  (852.4 MiB)
sha256: 05cc196a7c8ec42881cd8e59cb3fb18e7d0e33916aa26aae69f634b01a817da0
```

Note the `20260802`-named zip in `out/` is a **hardlink to the same inode** as the
20260803 one (link count 3, with `lineage_zenlte-ota.zip`) — it is not a leftover
v2 artifact. The real v2 zip is preserved in `artifacts/zenlte-v2/`.

**5. TWRP image — PASSED on every sub-criterion.**

```
dt_size            = 190,464          (non-zero, taken from the v3 recovery.img)
size               = 33,939,472 B     (< 35,651,584 limit)
TWRP version       = 3.7.1_12-0       (parsed out of the packed ramdisk)
kernel config      = CONFIG_F2FS_FS=y (extracted from the packed kernel itself)
                     # CONFIG_F2FS_CHECK_FS is not set
```

The kernel and dt are taken from the **same** v3 `recovery.img`, so they cannot
be mismatched. `repack_v3_hardened.sh` hard-fails on `dt_size=0`, on oversize,
and on a kernel without `CONFIG_F2FS_FS=y`.

**6. Odin tar — PASSED, structure verified rather than assumed.**

```
tar member       : recovery.img          (at archive root)
trailing line    : 6df2249aa52eb79a656743ead33361f1  twrp-zenlte-v3-hardened-20260803.tar
names the .tar   : True
md5 recomputed over the tar payload matches: True
```

### Artifacts

Saved locally to `/mnt/rom-data/artifacts/zenlte-v3/` with `SHA256SUMS.txt`:

```
05cc196a...  lineage-21.0-20260803-UNOFFICIAL-zenlte.zip   893,769,353 B
6de641b1...  boot.img                                       24,809,488 B
b6aa1591...  recovery.img                                   31,674,384 B
4d8766c4...  recovery.tar.md5                               31,682,607 B
8d0f9450...  twrp-zenlte-v3-hardened-20260803.img           33,939,472 B
c751985f...  twrp-zenlte-v3-hardened-20260803.tar.md5       33,945,671 B
```

Log: `logs/build_20260803T022232Z.log`. Disk after build: 332 GB free.

### Not done

Nothing was flashed to any phone. **This build has not been boot-tested on
hardware** — the fix is verified at source level and empirically at the formatter
and kernel-binary level, but no one has run it on a device yet.
