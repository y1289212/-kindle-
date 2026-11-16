#!/bin/sh
# One visible document handles both cold launch and warm return.
session=/dev/kindle-return-v112
if [ -d "$session" ]; then
    [ -r "$session/state" ] || exit 0
    read state < "$session/state"
    [ "$state" = HIDDEN ] || exit 0
    read pid < "$session/pid" && read expected < "$session/start" || exit 1
    case "$pid" in ""|*[!0-9]*) exit 1;; esac
    line=$(cat "/proc/$pid/stat") || exit 1
    fields=${line##*) }
    actual=$(printf '%s\n' "$fields" | awk '{print $20}')
    [ "$actual" = "$expected" ] || exit 1
    : > "$session/resume" || exit 1
    exit 0
fi
cold_lock=/dev/jinjiang-entry-v114.lock
mkdir "$cold_lock" 2>/dev/null || exit 0
trap 'rmdir "$cold_lock" 2>/dev/null' EXIT
# Add a separate zram swap device, then run the existing v55 runtime.
# No swapoff: keep the added swap until reboot, including after Android exits.
LOG=/mnt/us/kindle-jinjiang-v101-startup-launch.log
(
BB=/bin/busybox
echo 'V101_STARTUP_LAUNCHER_STARTED'
date
for required in /mnt/us/documents/kindle-jinjiang-v63-runtime.sh /mnt/us/kindle-system-test/setup-inventory-v87.json; do
    if [ ! -s "$required" ] || [ ! -r "$required" ]; then
        echo "STOP: missing or unreadable: $required"
        exit 1
    fi
done
if [ ! -x "$BB" ]; then
    echo "STOP: BusyBox unavailable: $BB"
    exit 1
fi
runtime_hash=$("$BB" sha256sum /mnt/us/documents/kindle-jinjiang-v63-runtime.sh) || exit 1
if [ "${runtime_hash%% *}" != 'c6313fd03b3999b88fd93f229e85c45f6d39c31df80c0679fce02c10df4afaf2' ]; then
    echo 'STOP: v87 runtime checksum differs'
    exit 1
fi
echo V87_RUNTIME_FILES_VERIFIED
STATE=/var/run/kindle-extra-zram-v56
LOCK=/var/run/kindle-extra-zram-v56.lock
HELP=/var/tmp/kindle-zram-format-enable-v56
active() {
    while read path rest; do
        [ "$path" = "$1" ] && return 0
    done < /proc/swaps
    return 1
}
snapshot() {
    cat /proc/swaps
    "$BB" grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' /proc/meminfo
}
setup() (
    set -e
    [ "$(id -u)" = 0 ] || { echo 'STOP: root required'; exit 1; }
    [ -r /mnt/us/documents/kindle-jinjiang-v63-runtime.sh ] || {
        echo 'STOP: documents/kindle-jinjiang-v63-runtime.sh missing'; exit 1;
    }
    mkdir "$LOCK" || { echo 'STOP: setup already running'; exit 1; }
    new_id=
    activated=0
    cleanup_setup() {
        # Only remove an inactive device created by this invocation.
        if [ -n "$new_id" ] && [ "$activated" = 0 ]; then
            if ! active "/dev/zram$new_id"; then
                echo "$new_id" > /sys/class/zram-control/hot_remove || true
            fi
        fi
        rmdir "$LOCK" || true
    }
    trap cleanup_setup EXIT
    trap 'exit 1' HUP INT TERM
    if [ -r "$STATE" ]; then
        read existing < "$STATE"
        case "$existing" in ''|*[!0-9]*) echo 'STOP: invalid state'; exit 1;; esac
        [ "$existing" -gt 0 ] || exit 1
        if active "/dev/zram$existing"; then
            echo "REUSING_EXTRA_ZRAM /dev/zram$existing"
            exit 0
        fi
        echo 'STOP: saved extra device is not active; reboot before retry'
        exit 1
    fi
    cp /mnt/us/kindle-system-test/zram-format-enable-v56 "$HELP" || exit 1
    chmod 700 "$HELP" || exit 1
    [ -r /sys/class/zram-control/hot_add ] || exit 1
    new_id=$(cat /sys/class/zram-control/hot_add) || exit 1
    case "$new_id" in ''|*[!0-9]*) echo 'STOP: invalid new device id'; new_id=; exit 1;; esac
    [ "$new_id" -gt 0 ] || { new_id=; exit 1; }
    sys=/sys/block/zram$new_id
    dev=/dev/zram$new_id
    # Use lzo, matching the existing device. Storage is allocated on demand.
    echo lzo > "$sys/comp_algorithm" || exit 1
    if [ -w "$sys/mem_limit" ]; then
        echo 134217728 > "$sys/mem_limit" || exit 1
    fi
    echo 268435456 > "$sys/disksize" || exit 1
    if [ ! -b "$dev" ]; then
        IFS=: read major minor < "$sys/dev" || exit 1
        "$BB" mknod "$dev" b "$major" "$minor" || exit 1
    fi
    "$HELP" "$dev" || exit 1
    activated=1
    echo "$new_id" > "$STATE" || exit 1
    active "$dev" || { echo 'STOP: verification failed'; exit 1; }
)
echo '=== EXTRA ZRAM V56 ==='
date
snapshot
if setup; then
    echo '=== READY: existing 128 MiB + extra 256 MiB ==='
    snapshot
    echo '=== Launching network v59 ==='
    nice_dir_v63=$(mktemp -d /var/tmp/kindle-priority-v63.XXXXXX) || exit 1
    cp /mnt/us/kindle-system-test/nice-exec-v63 "$nice_dir_v63/nice-exec-v63" || exit 1
    [ "$(/bin/busybox sha256sum "$nice_dir_v63/nice-exec-v63" | awk '{print $1}')" = 4cbf2748ecc69d4924f3cac98315c2e46e69beaa1eb9c8dc605340c3689f62f3 ] || { echo 'STOP: priority helper checksum differs'; exit 1; }
    chmod 700 "$nice_dir_v63/nice-exec-v63" || exit 1
    export KINDLE_NICE_HELPER_V63="$nice_dir_v63/nice-exec-v63"
    "$KINDLE_NICE_HELPER_V63" /bin/sh /mnt/us/documents/kindle-jinjiang-v63-runtime.sh > /mnt/us/kindle-nice-v101-startup.txt 2>&1
    status=$?
    rm -f "$nice_dir_v63/nice-exec-v63"
    rmdir "$nice_dir_v63" 2>/dev/null
    echo "Runtime script exit: $status"
    echo '=== AFTER TEST: extra swap remains active until reboot ==='
    snapshot
    if [ -r "$STATE" ]; then
        read final_id < "$STATE"
        cat "/sys/block/zram$final_id/mm_stat" 2>/dev/null
    fi
    exit "$status"
else
    echo 'STOP: swap setup failed; Android was not started'
    exit 1
fi
) > "$LOG" 2>&1
