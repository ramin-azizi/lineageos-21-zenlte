#!/bin/bash
# Launch the zenlte LineageOS 21 build fully detached.
# Must be run via: setsid nohup bash start_build.sh >/dev/null 2>&1 < /dev/null &
# so that ninja survives the parent shell exiting (a plain background job dies
# with SIGHUP -- that is what killed the 2026-08-01T15:29 run after 80 seconds).

# NOTE: no `set -u` -- build/envsetup.sh references unbound vars (TOP) and
# aborts under nounset, which silently produced an rc=127 no-op build.
ROOT=/mnt/rom-data/s6edgeplus-los-build
SRC=$ROOT/src
TS=$(date -u +%Y%m%dT%H%M%SZ)
LOG=$ROOT/logs/build_$TS.log

ln -sfn "build_$TS.log" "$ROOT/logs/build_latest.log"
cd "$SRC" || exit 1

# Ignore hangups explicitly, belt-and-braces alongside setsid.
trap '' HUP

{
  echo "=== build start $(date -u +%FT%TZ) (detached, -j16) ==="
  source build/envsetup.sh
  breakfast zenlte
  mka -j16 bacon
  rc=$?
  echo "=== build end $(date -u +%FT%TZ) rc=$rc ==="
} > "$LOG" 2>&1

echo $? > "$ROOT/logs/build.rc"
