#!/bin/bash
# Pack TWRP for zenlte on top of the v3 HARDENED LineageOS recovery kernel,
# with f2fs still ENABLED.
#
# Why this exists
# ---------------
# TWRP's own kernel is a different fork of the 3.10 tree with a substantially
# different defconfig, and did not boot reliably on this handset.  Reusing the
# LineageOS recovery kernel and device tree byte-for-byte means the ONLY
# difference from a known-booting image is the ramdisk.
#
# An earlier attempt worked around the f2fs panic by building a kernel with
# CONFIG_F2FS_FS=n, which cost TWRP the ability to read or back up f2fs
# partitions at all.  v3 fixes the bug at its root instead:
#
#   * external/f2fs-tools no longer stamps feature bits (EXTRA_ATTR et al)
#     that the 3.10 kernel cannot parse -- that mismatch was what fed garbage
#     block addresses into update_sit_entry() and panicked the kernel.
#   * the kernel now bounds-checks sentries[] in update_sit_entry() and in the
#     SIT-journal loop, and sanity-checks the checkpoint (CVE-2017-10663).
#
# So f2fs can be turned back on: TWRP regains f2fs support, and a bad
# filesystem now yields a clean failure instead of a panic.
#
# kernel  : from the freshly built v3 LineageOS recovery.img (hardened, f2fs=y)
# dt      : from the SAME v3 recovery.img -- keeping kernel and dt from one
#           build avoids the dt_size=0 mistake that wasted a flash, and avoids
#           pairing a dt with a kernel it was not built alongside
# ramdisk : the TWRP 3.7.1 recovery ramdisk from the TWRP tree

set -e

ROOT=/mnt/rom-data/sanders-twrp-build
SRC=$ROOT/src
TWRP_IMG=$SRC/out/target/product/zenlte/recovery.img        # ramdisk source
LOS_IMG=/mnt/rom-data/s6edgeplus-los-build/src/out/target/product/zenlte/recovery.img
KSRC=/mnt/rom-data/s6edgeplus-los-build/src/kernel/samsung/universal7420
ART=/mnt/rom-data/artifacts/zenlte-v3
DATE=$(date -u +%Y%m%d)
NAME=twrp-zenlte-v3-hardened-$DATE
WORK=$(mktemp -d)
MKBOOTIMG=$SRC/out/host/linux-x86/bin/mkbootimg
PART_SIZE=35651584   # BOARD_RECOVERYIMAGE_PARTITION_SIZE

mkdir -p "$ART"

[ -s "$LOS_IMG" ]  || { echo "FATAL: no v3 LOS recovery.img at $LOS_IMG"; exit 1; }
[ -s "$TWRP_IMG" ] || { echo "FATAL: no TWRP recovery.img at $TWRP_IMG"; exit 1; }
[ -x "$MKBOOTIMG" ] || { echo "FATAL: no mkbootimg at $MKBOOTIMG"; exit 1; }

# --- split the v3 LOS image: kernel + dt + header fields --------------------
python3 - "$LOS_IMG" "$WORK/ref" <<'PY'
import sys, struct, os
p, out = sys.argv[1], sys.argv[2]
d = open(p, 'rb').read()
(magic, ksz, kaddr, rsz, raddr, ssz, saddr, tags, page, dtsz, osver) = \
    struct.unpack('<8sIIIIIIIIII', d[:48])
assert magic == b'ANDROID!', magic
assert dtsz > 0, "reference image has dt_size=0 -- refusing (would not boot)"
pad = lambda x: (x + page - 1) // page * page
os.makedirs(out, exist_ok=True)
o = page
open(out + '/kernel', 'wb').write(d[o:o + ksz]); o += pad(ksz)
o += pad(rsz)
o += pad(ssz)
open(out + '/dt', 'wb').write(d[o:o + dtsz])
open(out + '/meta', 'w').write("%d %d\n" % (page, osver))
PY

# --- take the TWRP ramdisk out of the TWRP-built recovery.img --------------
python3 - "$TWRP_IMG" "$WORK/new" <<'PY'
import sys, struct, os
p, out = sys.argv[1], sys.argv[2]
d = open(p, 'rb').read()
(magic, ksz, kaddr, rsz, raddr, ssz, saddr, tags, page, dtsz, osver) = \
    struct.unpack('<8sIIIIIIIIII', d[:48])
assert magic == b'ANDROID!', magic
pad = lambda x: (x + page - 1) // page * page
os.makedirs(out, exist_ok=True)
o = page + pad(ksz)
open(out + '/ramdisk', 'wb').write(d[o:o + rsz])
PY

read PAGE OSVER < "$WORK/ref/meta"
OS_VERSION=$(python3 -c "v=$OSVER>>11;print('%d.%d.%d'%((v>>14)&0x7f,(v>>7)&0x7f,v&0x7f))")
OS_PATCH=$(python3 -c "p=$OSVER&0x7ff;print('%d-%02d'%(2000+((p>>4)&0x7f),p&0xf))")

echo "v3 hardened kernel : $(stat -c%s "$WORK/ref/kernel") bytes"
echo "v3 dt              : $(stat -c%s "$WORK/ref/dt") bytes"
echo "twrp ramdisk       : $(stat -c%s "$WORK/new/ramdisk") bytes"
echo "os_version         : $OS_VERSION / $OS_PATCH"

# --- the whole point of v3: f2fs must still be compiled in ------------------
"$KSRC/scripts/extract-ikconfig" "$WORK/ref/kernel" > "$WORK/kernel-config" 2>/dev/null || true
if ! grep -q "^CONFIG_F2FS_FS=y" "$WORK/kernel-config"; then
    echo "FATAL: CONFIG_F2FS_FS=y not found in the packed kernel -- v3 is"
    echo "       supposed to RESTORE f2fs support, not drop it."
    exit 1
fi
echo "kernel config      : CONFIG_F2FS_FS=y confirmed"
grep -E "^(CONFIG_F2FS_FS|CONFIG_F2FS_CHECK_FS|# CONFIG_F2FS_CHECK_FS)" \
    "$WORK/kernel-config" || true
cp "$WORK/kernel-config" "$ART/$NAME.kernel-config"

# --- repack ----------------------------------------------------------------
"$MKBOOTIMG" \
    --kernel "$WORK/ref/kernel" \
    --ramdisk "$WORK/new/ramdisk" \
    --dt "$WORK/ref/dt" \
    --base 0x10000000 \
    --kernel_offset 0x00008000 \
    --ramdisk_offset 0x01000000 \
    --tags_offset 0x00000100 \
    --pagesize 2048 \
    --os_version "$OS_VERSION" \
    --os_patch_level "$OS_PATCH" \
    --header_version 0 \
    --output "$WORK/$NAME.img"

printf 'SEANDROIDENFORCE' >> "$WORK/$NAME.img"

SZ=$(stat -c%s "$WORK/$NAME.img")
echo "packed image       : $SZ bytes (limit $PART_SIZE)"
if [ "$SZ" -gt "$PART_SIZE" ]; then
    echo "FATAL: image exceeds RECOVERY partition by $((SZ - PART_SIZE)) bytes"
    exit 1
fi

# --- refuse to ship a dt_size=0 image (this already cost one wasted flash) --
python3 - "$WORK/$NAME.img" <<'PY'
import sys, struct
d = open(sys.argv[1], 'rb').read()
(magic, ksz, ka, rsz, ra, ssz, sa, tags, page, dtsz, osver) = \
    struct.unpack('<8sIIIIIIIIII', d[:48])
assert magic == b'ANDROID!', magic
print("packed dt_size     : %d" % dtsz)
if dtsz == 0:
    sys.exit("FATAL: dt_size=0 -- this image would not boot")
PY

cp "$WORK/$NAME.img" "$ART/$NAME.img"

# --- Odin package ----------------------------------------------------------
# The md5 line must name the .tar, NOT recovery.img -- getting this wrong
# produced an Odin "binary is invalid" failure.
cd "$WORK"
cp "$NAME.img" recovery.img
tar -H ustar -cf "$NAME.tar" recovery.img
md5sum -t "$NAME.tar" >> "$NAME.tar"
mv "$NAME.tar" "$NAME.tar.md5"
cp "$NAME.tar.md5" "$ART/"

cd "$ART"
sha256sum "$NAME.img" "$NAME.tar.md5" > "$NAME.SHA256SUMS.txt"
ls -l "$ART/$NAME".*
rm -rf "$WORK"
echo "OK"
