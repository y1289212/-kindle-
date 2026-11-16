#!/bin/sh
# Name: Kindle Jinjiang Software Keyboard and Reading Header v73
# Author: Device Diagnostics

cd / || exit 1
BB=/bin/busybox
MOUNT=
UMOUNT=
# Explicit transport survives launchers that sanitize the environment.
request101=/mnt/us/kindle-system-test/aot-request-v101
request_consumed101=0
if [ -e "$request101" ] || [ -L "$request101" ]; then
    [ -f "$request101" ] && [ ! -L "$request101" ] || { echo 'STOP: invalid AOT request'; exit 1; }
    read request_mode101 < "$request101" || exit 1
    case "$request_mode101" in optimize|rollback) KINDLE_AOT_V101=$request_mode101;;
        *) echo 'STOP: unknown AOT request mode'; exit 1;; esac
    rm -f "$request101" || exit 1
    request_consumed101=1
fi

case "${KINDLE_AOT_V101:-}" in
    optimize) log_tag101=v101-aot;;
    rollback) log_tag101=v101-rollback;;
    *) log_tag101=v116-fix2;;
esac
LOGDIR=$(mktemp -d "/mnt/us/kindle-jinjiang-$log_tag101-logs.XXXXXX") || exit 1
exec > "$LOGDIR/result.txt" 2>&1
echo AOT_NATIVE_CMD_RUNTIME_V101_FIX2
echo AOT_CAPABLE_RUNTIME_V101
echo "AOT_ENTRY_MODE_V101 mode=${KINDLE_AOT_V101:-normal} request_consumed=$request_consumed101"
echo STARTUP_INCREMENTAL_CHECKS_V100
echo "PHASE_V52 script_start uptime=$(cut -d' ' -f1 /proc/uptime)"
runtime_tools110=
ROOT=
IMAGE=
LOOP=
LOOPDIR=
mounted=0
proc_mounted=0
locked=0
ashmem_loaded=0
client=
capture=
guard=
tracer=
probe=
probe_guard=
FBINKDIR=
presenter=
display_guard=
TOUCHDIR=
touch_reader=
touch_relay=
touch_guard=
touch_fifo_open=0
PERSIST_IMAGE=/mnt/us/kindle-system-test/kindle-persistent-v62.img
PERSIST_OWNER=/mnt/us/kindle-system-test/kindle-persistent-v62.owner
warm_v62=0
[ ! -f "$PERSIST_IMAGE" ] || warm_v62=1

ensure_link_v62() {
    link_target_v62=$1
    link_path_v62=$2
    if [ -L "$link_path_v62" ]; then
        [ "$(readlink "$link_path_v62")" = "$link_target_v62" ] || {
            echo "STOP: unexpected existing link $link_path_v62"; return 1;
        }
    elif [ -e "$link_path_v62" ]; then
        echo "STOP: link destination is occupied: $link_path_v62"; return 1
    else
        ln -s "$link_target_v62" "$link_path_v62" || return 1
    fi
}
net_proxy=
net_tools=
header_enabled_v73=0
status_minute_v73=
proc_watch_v71=
ink_updates_v67=0
exit_watcher_v66=
jit_stage_v66=

unmount_retry() {
    target=$1
    attempt=0
    while [ "$attempt" -lt 30 ]; do
        if "$UMOUNT" "$target"; then return 0; fi
        attempt=$((attempt + 1))
        sleep 2
    done
    echo "STOP: mount remains busy: $target"
    cat /proc/mounts > "$LOGDIR/mounts-cleanup-failed.txt"
    for process in /proc/[0-9]*; do
        for handle in "$process"/root "$process"/cwd "$process"/fd/*; do
            link=$(readlink "$handle" 2>/dev/null) || continue
            case "$link" in "$ROOT"|"$ROOT"/*)
                echo "Mount holder: $handle -> $link"
                echo "Holder name: $(cat "$process/comm" 2>/dev/null)";;
            esac
        done
    done
    return 1
}

# Only optimization artifacts in the private Android image are changed.
aot_restore101() {
    backup101="$ROOT/test/aot-backup-v101"
    [ -d "$backup101" ] && [ ! -L "$backup101" ] || return 1
    for entry101 in apk-path old.sha256 base.odex; do
        [ -f "$backup101/$entry101" ] && [ ! -L "$backup101/$entry101" ] || return 1
    done
    read apk101 < "$backup101/apk-path" || return 1
    case "$apk101" in /data/app/com.jjwxc.reader-*/base.apk) ;; *) return 1;; esac
    case "$apk101" in *..*|*'|'*) return 1;; esac
    # Never restore underneath a running Android process or compiler.
    for proc101 in /proc/[0-9]*; do
        [ "$(readlink -f "$proc101/root" 2>/dev/null)" != "$ROOT" ] || return 1
    done
    expected101=$(cat "$backup101/old.sha256") || return 1
    case "$expected101" in ''|*[!0-9a-f]*) return 1;; esac
    [ "${#expected101}" = 64 ] || return 1
    [ "$("$BB" sha256sum "$backup101/base.odex" | awk '{print $1}')" = "$expected101" ] || return 1
    odex101="$ROOT${apk101%/*}/oat/arm/base.odex"
    [ -d "${odex101%/*}" ] && [ ! -L "${odex101%/*}" ] || return 1
    case "$(readlink -f "${odex101%/*}")/" in "$ROOT"/data/app/*/oat/arm/) ;; *) return 1;; esac
    [ ! -L "$odex101" ] && [ ! -L "$odex101.v101-restore" ] || return 1
    cp -p "$backup101/base.odex" "$odex101.v101-restore" || return 1
    [ "$("$BB" sha256sum "$odex101.v101-restore" | awk '{print $1}')" = "$expected101" ] || return 1
    mv -f "$odex101.v101-restore" "$odex101" || return 1
    sync || return 1
    rm -f "$backup101/pending" || return 1
    echo AOT_ORIGINAL_RESTORED_V101
    return 0
}

aot_work101() {
    mode101=${KINDLE_AOT_V101:-}
    case "$mode101" in optimize|rollback) ;; *) return 0;; esac
    [ "$mode101" != rollback ] || { echo 'STOP: rollback must run before Android starts'; return 1; }
    run_probe aot-package-before-v101 /system/bin/dumpsys package com.jjwxc.reader
    [ "$probe_result" = 0 ] || return 1
    if grep -Eq 'compilation_filter=speed,[[:space:]]*status=kOatUpToDate' "$LOGDIR/aot-package-before-v101.txt"; then
        echo AOT_SPEED_ALREADY_READY_V101
        return 0
    fi
    # Native cmd is the Android 7 package shell entry point.
    for lib101 in libutils.so liblog.so libbinder.so libc++.so libdl.so libc.so libm.so; do
        [ -f "$ROOT/system/lib/$lib101" ] || { echo "STOP: cmd dependency missing: $lib101"; return 1; }
    done
    source101=/mnt/us/kindle-system-test/cmd-aot-v101-fix2
    destination101="$ROOT/system/bin/cmd-aot-v101-fix2"
    [ -f "$source101" ] && [ ! -L "$source101" ] || return 1
    [ ! -L "$destination101" ] && [ ! -L "$destination101.new" ] || return 1
    cp "$source101" "$destination101.new" || return 1
    [ "$("$BB" sha256sum "$destination101.new" | awk '{print $1}')" = 01aa5a27c36551f515d01ecb0cdfd8648248f3c0e53fc8fc69a5b7732a614e44 ] || return 1
    chown 0:0 "$destination101.new" || return 1
    chmod 755 "$destination101.new" || return 1
    mv -f "$destination101.new" "$destination101" || return 1
    PROBE_TIMEOUT=15
    run_probe aot-cmd-help-v101 /system/bin/cmd-aot-v101-fix2 package help
    if [ "$probe_result" != 0 ] || ! grep -Eq '^[[:space:]]*compile([[:space:]]|$)' "$LOGDIR/aot-cmd-help-v101.txt"; then
        echo 'STOP: package shell compile capability not confirmed; no optimization attempted'
        return 1
    fi
    echo NATIVE_PACKAGE_COMPILE_CONFIRMED_V101_FIX2
    [ -x "$ROOT/system/bin/dex2oat" ] || { echo 'STOP: installed dex2oat is missing'; return 1; }
    PROBE_TIMEOUT=30
    run_probe aot-apk-path-v101 /system/bin/sh -c 'export KINDLE_INPUT_LOW_HEAP=1; export CLASSPATH=/test/pm-stream-v31.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.pm.Pm path com.jjwxc.reader'
    [ "$probe_result" = 0 ] || return 1
    apk101=$(sed -n 's/^package://p' "$LOGDIR/aot-apk-path-v101.txt" | head -n 1 | tr -d '\r')
    case "$apk101" in /data/app/com.jjwxc.reader-*/base.apk) ;; *) return 1;; esac
    case "$apk101" in *..*|*'|'*) return 1;; esac
    [ -f "$ROOT$apk101" ] && [ ! -L "$ROOT$apk101" ] || return 1
    [ "$("$BB" sha256sum "$ROOT$apk101" | awk '{print $1}')" = fdb9a1165b655c37e5ae6a73bea1f502865951a61b8df319352c67821d0ce056 ] || return 1
    free101=$(df -Pk "$ROOT" | awk 'END {print $4}')
    case "$free101" in ''|*[!0-9]*) return 1;; esac
    [ "$free101" -ge 262144 ] || { echo 'STOP: AOT requires 256 MiB free in image'; return 1; }
    backup101="$ROOT/test/aot-backup-v101"
    [ ! -L "$backup101" ] || return 1
    mkdir -p "$backup101" || return 1
    chmod 700 "$backup101" || return 1
    odex101="$ROOT${apk101%/*}/oat/arm/base.odex"
    [ -f "$odex101" ] && [ ! -L "$odex101" ] || return 1
    if [ -e "$backup101/ready" ]; then
        # Do not overwrite the original backup on a retry.
        [ -f "$backup101/ready" ] && [ ! -L "$backup101/ready" ] || return 1
        [ "$(cat "$backup101/apk-path")" = "$apk101" ] || return 1
        [ "$("$BB" sha256sum "$backup101/base.odex" | awk '{print $1}')" = "$(cat "$backup101/old.sha256")" ] || return 1
    else
        for entry101 in base.odex apk-path old.sha256 ready pending; do
            [ ! -e "$backup101/$entry101" ] && [ ! -L "$backup101/$entry101" ] || {
                echo 'STOP: incomplete AOT backup retained'; return 1;
            }
        done
        cp -p "$odex101" "$backup101/base.odex" || return 1
        "$BB" sha256sum "$odex101" | awk '{print $1}' > "$backup101/old.sha256" || return 1
        [ "$("$BB" sha256sum "$backup101/base.odex" | awk '{print $1}')" = "$(cat "$backup101/old.sha256")" ] || return 1
        printf '%s\n' "$apk101" > "$backup101/apk-path" || return 1
        sync || return 1
        echo ready > "$backup101/ready" || return 1
    fi
    echo pending > "$backup101/pending" || return 1
    sync || return 1
    echo "PHASE_AOT_V101 compile_start uptime=$(cut -d' ' -f1 /proc/uptime)"
    cat /proc/meminfo > "$LOGDIR/aot-memory-before-v101.txt"
    # Explicit filter, one package only. No package clearing or reinstall.
    PROBE_TIMEOUT=900
    run_probe aot-compile-v101 /system/bin/cmd-aot-v101-fix2 package compile -m speed -f com.jjwxc.reader
    compile_result101=$probe_result
    PROBE_TIMEOUT=15
    run_probe aot-package-after-v101 /system/bin/dumpsys package com.jjwxc.reader
    package_result101=$probe_result
    unset PROBE_TIMEOUT
    cat /proc/meminfo > "$LOGDIR/aot-memory-after-v101.txt"
    echo "PHASE_AOT_V101 compile_end uptime=$(cut -d' ' -f1 /proc/uptime)"
    if [ "$compile_result101" != 0 ] || [ "$package_result101" != 0 ] ||
       ! grep -Eq '^[[:space:]]*Success[[:space:]]*$' "$LOGDIR/aot-compile-v101.txt" ||
       ! grep -Eq 'compilation_filter=speed,[[:space:]]*status=kOatUpToDate' "$LOGDIR/aot-package-after-v101.txt"; then
        echo 'AOT_NOT_CONFIRMED_V101: original artifact will be restored after Android stops'
        return 1
    fi
    sync || return 1
    rm -f "$backup101/pending" || return 1
    echo AOT_SPEED_VERIFIED_V101
    return 0
}

# Retain Android until explicit close, USB connection, or runtime failure.
control112=/dev/kindle-return-v112
warm_request111=0
return_cycle=0
warm_ready111=starting
ui_dir111=
ui_guard111=
ui_release111() {
    [ -n "$ui_dir111" ] || return 0
    /bin/sh "$ui_dir111/recover.sh" "$ui_dir111"
}
ui_acquire111() {
    [ -n "$ui_dir111" ] || return 1
    lipc-set-prop com.lab126.pillow disableEnablePillow disable || return 1
    while read pid111 start111; do
        [ -r "/proc/$pid111/stat" ] || return 1
        line111=$(cat "/proc/$pid111/stat") || return 1
        rest111=${line111##*) }
        current111=$(printf '%s\n' "$rest111" | awk '{print $20}')
        [ "$current111" = "$start111" ] || return 1
        kill -STOP "$pid111" || return 1
    done < "$ui_dir111/targets"
}
ui_prepare111() {
    # A stale controller never causes another Android instance to launch.
    if [ -e "$control112" ]; then
        echo STOP_EXISTING_RETURN_CONTROLLER_REBOOT_REQUIRED
        return 1
    fi
    mkdir "$control112" || return 1
    chmod 700 "$control112" || return 1
    echo "$$" > "$control112/pid"
    line112=$(cat /proc/$$/stat) || return 1
    rest112=${line112##*) }
    printf '%s
' "$rest112" | awk '{print $20}' > "$control112/start"
    echo ACTIVE > "$control112/state"
    ui_dir111=$(mktemp -d /dev/kindle-warm-ui111.XXXXXX) || return 1
    chmod 700 "$ui_dir111" || return 1
    : > "$ui_dir111/targets"
    for p111 in /proc/[0-9]*; do
        [ -r "$p111/comm" ] || continue
        read name111 < "$p111/comm"
        [ "$name111" = awesome ] || continue
        line111=$(cat "$p111/stat") || continue
        rest111=${line111##*) }
        state111=$(printf '%s\n' "$rest111" | awk '{print $1}')
        case "$state111" in T|t) echo STOP_WM_ALREADY_PAUSED; return 1;; esac
        start111=$(printf '%s\n' "$rest111" | awk '{print $20}')
        printf '%s %s\n' "${p111##*/}" "$start111" >> "$ui_dir111/targets"
    done
    [ -s "$ui_dir111/targets" ] || return 1
    cat > "$ui_dir111/recover.sh" <<'RECOVER'
#!/bin/sh
while read p s; do
    [ -r "/proc/$p/stat" ] || continue
    line=$(cat "/proc/$p/stat") || continue
    rest=${line##*) }
    current=$(printf '%s\n' "$rest" | awk '{print $20}')
    [ "$current" = "$s" ] || continue
    read name < "/proc/$p/comm"
    [ "$name" = awesome ] && kill -CONT "$p"
done < "$1/targets"
# Bound each native request; process resume above does not depend on LIPC.
bounded() {
    "$@" &
    child=$!
    (sleep 3; kill -TERM "$child" 2>/dev/null) &
    timer=$!
    wait "$child"
    kill "$timer" 2>/dev/null
    wait "$timer" 2>/dev/null
}
bounded lipc-set-prop com.lab126.pillow disableEnablePillow enable
bounded lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home
exit 0
RECOVER
    cat > "$ui_dir111/guard.sh" <<'GUARD'
#!/bin/sh
p=$1
start=$2
d=$3
while [ -r "/proc/$p/stat" ]; do
    line=$(cat "/proc/$p/stat") || break
    rest=${line##*) }
    now=$(printf '%s\n' "$rest" | awk '{print $20}')
    [ "$now" = "$start" ] || break
    [ ! -f "$d/done" ] || break
    sleep 2
done
/bin/sh "$d/recover.sh" "$d"
GUARD
    line111=$(cat /proc/$$/stat) || return 1
    rest111=${line111##*) }
    start111=$(printf '%s\n' "$rest111" | awk '{print $20}')
    /usr/bin/setsid /bin/sh "$ui_dir111/guard.sh" "$$" "$start111" "$ui_dir111" </dev/null >> "$LOGDIR/ui-guard-v111.txt" 2>&1 &
    ui_guard111=$!
    ui_acquire111
}
usb_flag116=/var/local/system/no_transitions
usb_token116=
usb_state116=/sys/class/udc/11211000.usb/state
usb_lun116=/sys/devices/platform/11211000.usb/gadget/lun0/file
usb_local116() {
    [ -r "$usb_lun116" ] && backing116=$(cat "$usb_lun116") && [ -z "$backing116" ] &&
    awk '$2=="/mnt/base-us" && $3=="vfat"{b=1} $2=="/mnt/us"{u=1} END{exit !(b && u)}' /proc/mounts
}
# The image is on the lower VFAT mount. Check its identity separately
# from the user-facing FUSE view, which is needed before resuming.
usb_snapshot116() {
    usb_link_now=$(readlink "$usb_flag116")
    usb_token_ok=0
    [ -f "$usb_token116" ] && usb_token_ok=1
    usb_disk_now=$(cat "$usb_lun116") || usb_disk_now=READ_ERROR
    usb_mounts_now=$(awk '
        $2=="/mnt/base-us" && $1=="/dev/loop/0" && $3=="vfat" {b=1}
        $2=="/mnt/us" && $3 ~ /^fuse/ {u=1}
        END {print (b+0) ":" (u+0)}
    ' /proc/mounts)
}
usb_verified116() {
    usb_snapshot116
    case "$usb_mounts_now" in 1:0|1:1) ;; *) return 1;; esac
    [ -z "$usb_disk_now" ] && [ "$usb_token_ok" = 1 ]
}
usb_marker116() {
    [ "$(readlink "$usb_flag116")" = "$usb_token116" ] && [ -f "$usb_token116" ]
}
usb_rearm116() {
    usb_marker116 && return 0
    [ "$(cat "$usb_state116")" = 'not attached' ] &&
        usb_verified116 && [ ! -e "$usb_flag116" ] && [ ! -L "$usb_flag116" ] &&
        ln -s "$usb_token116" "$usb_flag116" && usb_marker116
}
usb_detail116() {
    echo "USB_CHECK_V116_FIX2 state=$usb116 mounts=$usb_mounts_now expected=$usb_token116 actual=$usb_link_now token=$usb_token_ok lun=${usb_disk_now:-empty}"
}
usb_arm116() {
    [ "$(cat "$usb_state116")" = 'not attached' ] && usb_local116 || return 1
    if [ -n "$usb_token116" ]; then
        usb_rearm116
        return
    fi
    [ "$(kdb get system/driver/filesystem/NO_TRANSITIONS)" = "$usb_flag116" ] || return 1
    prior116=$(readlink "$usb_flag116")
    case "$prior116" in
        /dev/jinjiang-usb116.??????|/var/tmp/jinjiang-usb116.??????)
            if [ ! -e "$prior116" ]; then rm -f "$usb_flag116" || return 1; fi;;
    esac
    [ ! -e "$usb_flag116" ] && [ ! -L "$usb_flag116" ] || return 1
    usb_token116=$(mktemp /var/tmp/jinjiang-usb116.XXXXXX) || return 1
    ln -s "$usb_token116" "$usb_flag116" && [ "$(readlink "$usb_flag116")" = "$usb_token116" ] || return 1
    [ "$(cat "$usb_state116")" = 'not attached' ] && usb_local116
}
usb_release116() {
    [ -n "$usb_token116" ] || return 0
    if [ "$(readlink "$usb_flag116")" = "$usb_token116" ]; then rm -f "$usb_flag116"; fi
    rm -f "$usb_token116"
}
warm_return111() {
    warm_ready111=switching
    warm_request111=0
    return_cycle=$((return_cycle + 1))
    echo "HIDE_CYCLE=$return_cycle"
    rm -f "$control112/resume" "$control112/stop" || return 1
    echo "WARM111_HIDE_BEGIN uptime=$(cut -d' ' -f1 /proc/uptime)"
    # Stop event producers and release EVIOCGRAB, keep FIFO/Android relay alive.
    kill "$exit_watcher_v66" 2>/dev/null
    wait "$exit_watcher_v66" 2>/dev/null
    exit_watcher_v66=
    kill "$touch_guard" 2>/dev/null
    wait "$touch_guard" 2>/dev/null
    touch_guard=
    kill -TERM -"$touch_reader" 2>/dev/null
    "$FBINKDIR/delay-v70" 250
    kill -KILL -"$touch_reader" 2>/dev/null
    wait "$touch_reader" 2>/dev/null
    touch_reader=
    ignored116=$(kdb get system/driver/filesystem/IG_USB_SYSFS)
    case "$ignored116" in /*) ;; *) echo USB_EVENT_PATH_UNKNOWN; return 1;; esac
    [ ! -e "$ignored116" ] || { echo USB_STALE_EVENT; return 1; }
    usb_arm116 || { echo USB_HOLD_ARM_FAILED; return 1; }
    usb_seen116=0
    ui_release111
    if [ "$(cat "$usb_state116")" = 'not attached' ]; then
        usb_rearm116 || { echo USB_REARM_AFTER_HOME_FAILED; return 1; }
    fi
    echo "WARM111_NATIVE_VISIBLE uptime=$(cut -d' ' -f1 /proc/uptime)"
    echo HIDDEN > "$control112/state" || return 1
    echo SESSION_HIDDEN_WITHOUT_TIMEOUT_V114
    health_ticks=0
    while :; do
        if [ -f "$control112/stop" ]; then exit 0; fi
        read usb116 < "$usb_state116" || return 1
        if [ "$usb116" != 'not attached' ]; then
            usb_verified116 || { usb_detail116; return 1; }
            if ! usb_marker116 && [ ! -f "$ignored116" ]; then
                # notifyusb may still be handling the online event. Keep checking
                # the backing device while allowing a short event-delivery delay.
                tries116=0
                while ! usb_marker116 && [ ! -f "$ignored116" ]; do
                    [ "$(cat "$usb_state116")" = 'not attached' ] && break
                    [ "$tries116" -lt 3 ] || { usb_detail116; echo USB_EVENT_UNCONFIRMED; return 1; }
                    sleep 1
                    usb_verified116 || { usb_detail116; return 1; }
                    tries116=$((tries116+1))
                done
            fi
            if [ "$usb_seen116" = 0 ]; then echo USB_SESSION_HELD_V116; usb_seen116=1; fi
            sleep 1
            continue
        fi
        if [ "$usb_seen116" = 1 ]; then
            usb_wait116=0
            while :; do
                usb_verified116 || { usb_detail116; return 1; }
                [ "$usb_mounts_now" = 1:1 ] && break
                [ "$usb_wait116" -lt 10 ] || { usb_detail116; return 1; }
                sleep 1
                usb_wait116=$((usb_wait116 + 1))
            done
            echo USB_DETACHED_V116
            usb_seen116=0
        fi
        usb_rearm116 || { usb_detail116; echo USB_REARM_FAILED; return 1; }
        if [ -f "$control112/resume" ]; then
            rm -f "$control112/resume"
            break
        fi
        if [ "$health_ticks" -ge 60 ]; then
            "$KINDLE_NICE_HELPER_V63" --alive "$ROOT" || { echo SESSION_LOST_V114; return 1; }
            health_ticks=0
        fi
        sleep 1
        health_ticks=$((health_ticks+1))
    done
    echo RESUMING > "$control112/state"
    echo "WARM111_RESUME_BEGIN uptime=$(cut -d' ' -f1 /proc/uptime)"
    "$KINDLE_NICE_HELPER_V63" --alive "$ROOT" || return 1
    kill -0 "$touch_relay" 2>/dev/null || return 1
    ui_acquire111 || return 1
    : > "$LOGDIR/touch-reader.txt"
    : > "$LOGDIR/touch-events-v62.txt"
    rm -f "$TOUCHDIR/reader-status-v62"
    /usr/bin/setsid "$BB" sh -c '("$1" --run-300-seconds; echo "$?" > "$5") | (set -f; control=$6; close_gesture() {
    [ "$#" = 6 ] && [ "$1" = swipe ] || return 1
    case "$2:$3:$4:$5" in *[!0-9:]*) return 1;; esac
    [ "$2" -ge 540 ] && [ "$4" -ge 540 ] && [ "$3" -le 80 ] && [ "$5" -ge 740 ]
}
while IFS= read -r event; do
    if close_gesture $event; then
        : > "$control/stop"
    else
        printf "%s\n" "$event" || exit 1
    fi
done) | "$2" tee -a "$3" > "$4"; read reader_rc < "$5"; exit "$reader_rc"' sh "$TOUCHDIR/kindle_touch_bridge-v30" "$BB" "$LOGDIR/touch-events-v62.txt" "$TOUCHDIR/events.fifo" "$TOUCHDIR/reader-status-v62" "$control112" 9>&- 2>> "$LOGDIR/touch-reader.txt" &
    touch_reader=$!
    (
        sleep 305
        kill -TERM -"$touch_reader" 2>/dev/null
        sleep 1
        kill -KILL -"$touch_reader" 2>/dev/null
    ) 9>&- &
    touch_guard=$!
    sleep 1
    grep -q TOUCH_GRABBED_V30 "$LOGDIR/touch-reader.txt" || return 1
    "$FBINKDIR/controls-v78" "$LOGDIR/touch-events-v62.txt" "$$" "$LOGDIR/settings-request-v78" 9>&- > "$LOGDIR/exit-watcher-v66.txt" 2>&1 &
    exit_watcher_v66=$!
    cp "$ROOT/test/kindle-fb/frame.ppm" "$TOUCHDIR/frame.ppm" || return 1
    rm -f "$FBINKDIR/frame-prev-v76.gray" "$FBINKDIR/frame-state-v76.txt"
    present_desktop "$TOUCHDIR/frame.ppm" warm-return-v111 || return 1
    last_crc=
    last_status_key_v73=
    echo ACTIVE > "$control112/state" || return 1
    warm_ready111=1
    echo "RETURN_CYCLE=$return_cycle"
    echo "WARM111_FRAME_PRESENTED uptime=$(cut -d' ' -f1 /proc/uptime)"
}

cleanup() {
    final=$?
    if [ -r "$control112/pid" ]; then
        read owner112 < "$control112/pid"
        if [ "$owner112" = "$$" ]; then echo CLOSING > "$control112/state"; fi
    fi
    if [ -n "$FBINKDIR" ]; then
        rm -f "$FBINKDIR/frame-prev-v76.gray" "$FBINKDIR/frame-state-v76.txt"
    fi
    read exit_uptime_v73 ignored_v73 < /proc/uptime
    echo "EXIT_PHASE_V77 cleanup_start uptime=$exit_uptime_v73"
    trap - EXIT HUP INT TERM USR1
    if [ -n "$proc_watch_v71" ]; then
        kill "$proc_watch_v71" 2>/dev/null
        wait "$proc_watch_v71" 2>/dev/null
        proc_watch_v71=
    fi
    if [ -n "$FBINKDIR" ]; then rm -f "$FBINKDIR/proc-watch-v71" "$FBINKDIR/frame-v73"; fi
    if [ -n "$exit_watcher_v66" ]; then
        kill "$exit_watcher_v66" 2>/dev/null
        wait "$exit_watcher_v66" 2>/dev/null
        exit_watcher_v66=
    fi
    if [ -n "$FBINKDIR" ]; then rm -f "$FBINKDIR/kindle-tools-v66" "$FBINKDIR/ink-v66.ppm" "$FBINKDIR/controls-v78"; fi
    if [ -n "$jit_stage_v66" ]; then rm -rf "$jit_stage_v66"; fi
    if [ "$touch_fifo_open" = 1 ]; then
        exec 9>&-
        touch_fifo_open=0
    fi
    for touch_pid in "$touch_reader" "$touch_relay"; do
        [ -n "$touch_pid" ] || continue
        kill -TERM -"$touch_pid" 2>/dev/null
    done
    sleep 1
    for touch_pid in "$touch_reader" "$touch_relay"; do
        [ -n "$touch_pid" ] || continue
        kill -KILL -"$touch_pid" 2>/dev/null
        wait "$touch_pid" 2>/dev/null
    done
    if [ -n "$touch_guard" ]; then
        kill "$touch_guard" 2>/dev/null
        wait "$touch_guard" 2>/dev/null
    fi
    if [ -n "$TOUCHDIR" ]; then
        rm -f "$TOUCHDIR/kindle_touch_bridge-v30" "$TOUCHDIR/events.fifo" "$TOUCHDIR/frame.ppm" "$TOUCHDIR/reader-status-v62"
        rmdir "$TOUCHDIR"
    fi
    if [ -n "$display_guard" ]; then
        kill "$display_guard" 2>/dev/null
        wait "$display_guard" 2>/dev/null
    fi
    if [ -n "$presenter" ]; then
        kill -KILL -"$presenter" 2>/dev/null
        wait "$presenter" 2>/dev/null
    fi
    if [ -n "$ui_dir111" ] && [ -f "$ui_dir111/recover.sh" ]; then
        ui_release111
        : > "$ui_dir111/done"
    fi
    if [ -n "$tracer" ]; then
        kill -INT -"$tracer" 2>/dev/null
        sleep 1
        kill -KILL -"$tracer" 2>/dev/null
        wait "$tracer" 2>/dev/null
    fi
    if [ -n "$probe_guard" ]; then
        kill "$probe_guard" 2>/dev/null
        wait "$probe_guard" 2>/dev/null
    fi
    if [ -n "$probe" ]; then
        kill -KILL -"$probe" 2>/dev/null
        wait "$probe" 2>/dev/null
    fi
    if [ -n "$guard" ]; then
        kill "$guard" 2>/dev/null
        wait "$guard" 2>/dev/null
    fi
    if [ -n "$client" ]; then
        kill -TERM -"$client" 2>/dev/null
        wait_count78=0
        while kill -0 -"$client" 2>/dev/null && [ "$wait_count78" -lt 4 ]; do
            if [ -x "$FBINKDIR/delay-v70" ]; then "$FBINKDIR/delay-v70" 250; else sleep 1; break; fi
            wait_count78=$((wait_count78 + 1))
        done
        kill -KILL -"$client" 2>/dev/null
        wait "$client" 2>/dev/null
    fi
    if [ -n "$net_proxy" ]; then
        kill -TERM -"$net_proxy" 2>/dev/null
        wait_count78=0
        while kill -0 -"$net_proxy" 2>/dev/null && [ "$wait_count78" -lt 4 ]; do
            if [ -x "$FBINKDIR/delay-v70" ]; then "$FBINKDIR/delay-v70" 250; else sleep 1; break; fi
            wait_count78=$((wait_count78 + 1))
        done
        kill -KILL -"$net_proxy" 2>/dev/null
        wait "$net_proxy" 2>/dev/null
        net_proxy=
    fi
    if [ -n "$net_tools" ]; then
        rm -f "$net_tools/dnsproxy"
        rmdir "$net_tools" 2>/dev/null
    fi
    if [ "$mounted" = 1 ] && [ -d "$ROOT/data/anr" ]; then
        mkdir -p "$LOGDIR/anr-v59"
        cp -R "$ROOT/data/anr/." "$LOGDIR/anr-v59/" 2>/dev/null
    fi
    if [ -n "$capture" ]; then
        kill -TERM "$capture" 2>/dev/null
        sleep 1
        kill -KILL "$capture" 2>/dev/null
        wait "$capture" 2>/dev/null
        capture=
        read exit_uptime76 exit_idle76 < /proc/uptime
        echo "EXIT_TIME_V76 uptime=$exit_uptime76"
        echo 'Log capture stopped'
    fi
    # Zygote creates its own process group: stop every process rooted in this
    # exact temporary mount, rather than relying solely on the launcher group.
    if [ "$mounted" = 1 ] && [ -n "$ROOT" ]; then
        for signal in TERM KILL KILL; do
            remaining78=0
            for p in /proc/[0-9]*; do
                [ "$(readlink -f "$p/root" 2>/dev/null)" = "$ROOT" ] || continue
                remaining78=$((remaining78 + 1))
                echo "Stopping temporary-root process ${p##*/} ($signal)"
                kill -"$signal" "${p##*/}" 2>/dev/null
            done
            [ "$remaining78" -gt 0 ] || break
            if [ "$signal" = TERM ] && [ -x "$FBINKDIR/delay-v70" ]; then
                grace78=0
                while [ "$grace78" -lt 4 ]; do
                    "$FBINKDIR/delay-v70" 250
                    alive78=0
                    for p in /proc/[0-9]*; do
                        [ "$(readlink -f "$p/root" 2>/dev/null)" = "$ROOT" ] || continue
                        alive78=1; break
                    done
                    [ "$alive78" = 1 ] || break
                    grace78=$((grace78 + 1))
                done
            elif [ -x "$FBINKDIR/delay-v70" ]; then "$FBINKDIR/delay-v70" 250; else sleep 1; fi
        done
    fi
    if [ "$mounted" = 1 ] && [ -e "$ROOT/test/aot-backup-v101/pending" ]; then
        if ! aot_restore101; then
            echo 'AOT_RECOVERY_PENDING_V101: backup retained; do not remove the backup'
            final=1
        fi
    fi
    read stage_uptime76 stage_idle76 < /proc/uptime
    echo "STAGE_TIME_V76 uptime=$stage_uptime76"
    if [ -n "$FBINKDIR" ]; then
        rm -f "$FBINKDIR/fbink-image" "$FBINKDIR/delay-v70"
        rmdir "$FBINKDIR"
    fi
    echo '=== Cleanup ==='    
    clean=1
    if [ "$mounted" = 1 ]; then
        for name in servicemanager.txt surfaceflinger.txt installd.txt keystore.txt zygote.txt integration.properties zygote.pid property-service.pid zygote-trace.txt healthd.txt battery-check.txt audioserver.txt audio-check.txt; do
            [ ! -f "$ROOT/test/$name" ] || cp "$ROOT/test/$name" "$LOGDIR/$name" || clean=0
        done
        if [ -f "$ROOT/test/kindle-fb/frame.ppm" ]; then
            cp "$ROOT/test/kindle-fb/frame.ppm" "$LOGDIR/final-frame.ppm" || clean=0
        fi
        (
            cd "$ROOT/data/ime-rime-v74" || exit 0
            for file85 in default.yaml build/default.yaml kindle_pinyin9.schema.yaml kindle_pinyin26.schema.yaml build/kindle_pinyin9.schema.yaml build/kindle_pinyin26.schema.yaml; do
                echo "=== $file85 ==="
                if [ -f "$file85" ]; then
                    grep -E '^[[:space:]]*(config_version|version|page_size|prism):' "$file85" || :
                else
                    echo missing
                fi
            done
            for file85 in build/kindle_pinyin9_exact83.prism.bin build/kindle_pinyin9.schema.yaml.ready85 build/kindle_pinyin26.schema.yaml.ready85; do
                if [ -f "$file85" ]; then "$BB" ls -l "$file85"; else echo "$file85 missing"; fi
            done
        ) > "$LOGDIR/rime-schema-state-v86.txt" 2>&1
        (
            cd "$ROOT/data/ime-rime-v74" || exit 0
            for file85 in default.yaml build/default.yaml kindle_pinyin9.schema.yaml kindle_pinyin26.schema.yaml build/kindle_pinyin9.schema.yaml build/kindle_pinyin26.schema.yaml; do
                echo "=== $file85 ==="
                if [ -f "$file85" ]; then
                    grep -E '^[[:space:]]*(config_version|version|page_size|prism):' "$file85" || :
                else
                    echo missing
                fi
            done
            for file85 in build/kindle_pinyin9_exact83.prism.bin build/kindle_pinyin9.schema.yaml.ready85 build/kindle_pinyin26.schema.yaml.ready85; do
                if [ -f "$file85" ]; then "$BB" ls -l "$file85"; else echo "$file85 missing"; fi
            done
        ) > "$LOGDIR/rime-schema-state-v86.txt" 2>&1
        if [ "$proc_mounted" = 1 ]; then
            if unmount_retry "$ROOT/proc"; then
                proc_mounted=0
                echo 'proc unmounted'
                read exit_uptime_v73 ignored_v73 < /proc/uptime
                echo "EXIT_PHASE_V77 proc_unmounted uptime=$exit_uptime_v73"
            else
                clean=0
            fi
        fi
        if [ "$proc_mounted" = 0 ]; then
            if unmount_retry "$ROOT"; then
                mounted=0
                echo 'runtime image unmounted'
                read exit_uptime_v73 ignored_v73 < /proc/uptime
                echo "EXIT_PHASE_V77 image_unmounted uptime=$exit_uptime_v73"
            else
                clean=0
            fi
        fi
    fi
    if [ "$mounted" = 0 ] && [ -n "$LOOP" ]; then
        if "$BB" losetup -d "$LOOP"; then
            echo "loop detached: $LOOP"
            LOOP=
        else
            clean=0
        fi
    fi
    if [ "$mounted" = 0 ] && [ -z "$LOOP" ]; then
        if [ -n "$LOOPDIR" ]; then
            rm -f "$LOOPDIR/device" || clean=0
            rmdir "$LOOPDIR" || clean=0
        fi
        [ -z "$IMAGE" ] || echo "PERSISTENT_DATA_RETAINED_V62 image=$IMAGE"
        [ -z "$ROOT" ] || rmdir "$ROOT" || clean=0
    else
        echo "Retained image: $IMAGE"
        echo "Retained mountpoint: $ROOT"
        clean=0
    fi
    if [ "$locked" = 1 ] && [ "$mounted" = 0 ] && [ -z "$LOOP" ]; then
        rmdir /tmp/kindle-java-smoke.lock || clean=0
    fi
    if [ "$ashmem_loaded" = 1 ]; then
        read stage_uptime76 stage_idle76 < /proc/uptime
        echo "STAGE_TIME_V76 uptime=$stage_uptime76"
        echo '=== Unload ashmem loaded by this test ==='
        if rmmod ashmem; then
            ashmem_loaded=0
            echo 'ashmem unloaded'
        else
            echo 'STOP: ashmem unload failed; module retained, no forced removal'
            clean=0
        fi
    fi
    read stage_uptime76 stage_idle76 < /proc/uptime
    echo "STAGE_TIME_V76 uptime=$stage_uptime76"
    echo '=== Final ashmem module state ==='
    grep '^ashmem ' /proc/modules || true
    [ "$clean" = 1 ] || final=1
    if [ -n "$runtime_tools110" ]; then
        rm -f "$runtime_tools110/nice-exec-v63"
        rmdir "$runtime_tools110" 2>/dev/null
    fi
    if [ -r "$control112/pid" ]; then
        read owner112 < "$control112/pid"
        if [ "$owner112" = "$$" ] && [ "$clean" = 1 ]; then
            rm -f "$control112/pid" "$control112/start" "$control112/state" "$control112/resume" "$control112/stop"
            rmdir "$control112" 2>/dev/null
        fi
    fi
    echo "Cleanup status: $clean (1=complete)"
    echo "Overall exit: $final"
    dmesg | tail -n 120 > "$LOGDIR/kernel.txt"
    cat /proc/meminfo > "$LOGDIR/memory-after.txt"
    cat /proc/mounts > "$LOGDIR/mounts-after.txt"
    "$BB" losetup -a > "$LOGDIR/loops-after.txt" 2>&1
    read stage_uptime76 stage_idle76 < /proc/uptime
    echo "STAGE_TIME_V76 uptime=$stage_uptime76"
    echo '=== END ===' 
    cp "$LOGDIR/result.txt" "/mnt/us/kindle-jinjiang-$log_tag101-last-result.txt"
    "$BB" tar -czf "/mnt/us/kindle-jinjiang-$log_tag101-logs.tar.gz" -C "$LOGDIR" .
    if [ "$mounted" = 0 ] && [ -z "$LOOP" ]; then usb_release116; fi
    exit "$final"
}
trap cleanup EXIT
trap 'echo "STOP: interrupted"; exit 1' HUP INT TERM
trap 'case "$warm_ready111" in 1) warm_request111=1;; starting) echo USER_STOP_INDEPENDENT_V66; exit 0;; esac' USR1

read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Kindle Jinjiang Software Keyboard and Reading Header v73 ==='
date
uname -a
id
[ "$(id -u)" = 0 ] || exit 1
# Own the helper for the entire runtime; never depend on the entry script's
# temporary file or inherited environment. /dev is the audited executable tmpfs.
runtime_tools110=$(mktemp -d /dev/kindle-runtime-tools-v110.XXXXXX) || exit 1
chmod 700 "$runtime_tools110" || exit 1
cp /mnt/us/kindle-system-test/nice-exec-v63 "$runtime_tools110/nice-exec-v63" || exit 1
hash110=$("$BB" sha256sum "$runtime_tools110/nice-exec-v63") || exit 1
[ "${hash110%% *}" = 4cbf2748ecc69d4924f3cac98315c2e46e69beaa1eb9c8dc605340c3689f62f3 ] || {
    echo 'STOP: runtime-owned helper checksum mismatch'; exit 1;
}
chmod 700 "$runtime_tools110/nice-exec-v63" || exit 1
export KINDLE_NICE_HELPER_V63="$runtime_tools110/nice-exec-v63"
[ -x "$KINDLE_NICE_HELPER_V63" ] || exit 1
echo "RUNTIME_HELPER_OWNED_V110 path=$KINDLE_NICE_HELPER_V63"
[ -x "$BB" ] && [ -x /usr/bin/setsid ] || exit 1
MOUNT=$(command -v mount)
UMOUNT=$(command -v umount)
case "$MOUNT" in /*) ;; *) echo 'STOP: system mount executable not found'; exit 1;; esac
case "$UMOUNT" in /*) ;; *) echo 'STOP: system umount executable not found'; exit 1;; esac
[ -x "$MOUNT" ] && [ -x "$UMOUNT" ] || exit 1
echo "System mount: $MOUNT"
echo "System umount: $UMOUNT"
cat /proc/mounts > "$LOGDIR/mounts-preflight.txt"
"$BB" losetup -a > "$LOGDIR/loops-preflight.txt" 2>&1
for p in /proc/[0-9]*; do
    process_root=$(readlink -f "$p/root" 2>/dev/null) || continue
    case "$process_root" in /var/tmp/kindle-framework-root.*|/tmp/kindle-framework-root.*)
        echo "PID ${p##*/} root=$process_root"
        tr '\000' ' ' < "$p/cmdline" 2>/dev/null
        echo
        ;;
    esac
done > "$LOGDIR/test-processes-preflight.txt"
if ! mkdir /tmp/kindle-java-smoke.lock; then
    echo 'STOP: another test or an uncleared prior mount exists'
    exit 1
fi
locked=1
cat /proc/meminfo > "$LOGDIR/memory-before.txt"
cat /proc/mounts > "$LOGDIR/mounts-before.txt"
"$BB" losetup -a > "$LOGDIR/loops-before.txt" 2>&1
memory_attempt=0
while :; do
    avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    case "$avail" in ''|*[!0-9]*) echo 'STOP: cannot read MemAvailable'; exit 1;; esac
    echo "MEMORY_PREFLIGHT_V87_FIX4 attempt=$memory_attempt available_kib=$avail"
    [ "$avail" -lt 163840 ] || break
    # Bounded low-memory admission; swap is not counted as physical RAM.
    swap_free103=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)
    swap_total103=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
    case "$swap_free103:$swap_total103" in
        *[!0-9:]*|:*|*:) echo 'STOP: invalid swap statistics'; exit 1;;
    esac
    if [ "$avail" -ge 147456 ] &&
       [ "$swap_free103" -ge 262144 ] &&
       [ "$swap_total103" -ge 393000 ] &&
       awk '$1 == "/dev/zram1" && $3 >= 262000 {ok=1} END {exit !ok}' /proc/swaps; then
        echo "MEMORY_ADMISSION_V103 available_kib=$avail swap_free_kib=$swap_free103"
        break
    fi
    if [ "$memory_attempt" -ge 10 ]; then
        awk '
            FNR == 1 { name=""; pid="" }
            /^Name:/ { name=$2 }
            /^Pid:/ { pid=$2 }
            /^VmRSS:/ && pid != "" { print $2, pid, name }
        ' /proc/[0-9]*/status 2>"$LOGDIR/memory-process-errors.txt" |
            sort -nr | head -n 20 > "$LOGDIR/memory-top-rss-kib.txt"
        echo "STOP: memory admission failed (160 MiB RAM or 144 MiB with verified extra zram and 256 MiB swap free): $avail KiB"
        exit 1
    fi
    memory_attempt=$((memory_attempt + 1))
    sleep 2
done
free_kb=$(df -Pk /mnt/us | awk 'END {print $4}')
case "$free_kb" in ''|*[!0-9]*) echo 'STOP: cannot read USB storage free space'; exit 1;; esac
if [ "$warm_v62" = 1 ]; then
    [ "$free_kb" -ge 262144 ] || { echo 'STOP: retain 256 MiB free USB storage'; exit 1; }
else
    [ "$free_kb" -ge 2097152 ] || { echo 'STOP: first persistent setup needs 2 GiB free'; exit 1; }
fi

read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Binder device preflight ==='
[ -c /dev/vndbinder ] && [ -c /dev/binder ] || exit 1
vdev=$(/bin/busybox stat -L -c '%t:%T' /dev/vndbinder) || exit 1
bdev=$(/bin/busybox stat -L -c '%t:%T' /dev/binder) || exit 1
echo "vndbinder=$vdev original-binder=$bdev"
[ "$vdev" != "$bdev" ] || { echo 'STOP: same Binder device'; exit 1; }
scan_binder_v87() {
    scan_incomplete=0
    for proc in /proc/[0-9]*; do
        [ -d "$proc/fd" ] || continue
        if ! scan_error=$(ls "$proc/fd" 2>&1); then
            if [ -d "$proc/fd" ]; then
                echo "BINDER_SCAN_UNREADABLE attempt=$binder_attempt path=$proc/fd detail=$scan_error"
                scan_incomplete=1
            fi
            continue
        fi
        for fd in "$proc"/fd/*; do
            [ -c "$fd" ] || continue
            if ! dev=$("$BB" stat -L -c '%t:%T' "$fd" 2>&1); then
                if [ -e "$fd" ]; then
                    echo "BINDER_SCAN_STAT_FAILED attempt=$binder_attempt path=$fd detail=$dev"
                    scan_incomplete=1
                fi
                continue
            fi
            if [ "$dev" = "$vdev" ]; then
                echo "STOP: vndbinder user: $fd"
                return 2
            fi
        done
    done
    return "$scan_incomplete"
}

binder_attempt=1
while :; do
    scan_binder_v87
    binder_result=$?
    case "$binder_result" in
        0) echo "BINDER_SCAN_OK attempt=$binder_attempt"; break ;;
        2) exit 1 ;;
    esac
    if [ "$binder_attempt" -ge 3 ]; then
        echo 'STOP: Binder scan incomplete after three attempts'
        exit 1
    fi
    binder_attempt=$((binder_attempt + 1))
    sleep 1
done

# V65: verify two directory views using only an owned temporary probe.
# A same-length write must be immediately visible through the other view.
v65_same_view() {
    source_dir_v65=$1
    base_dir_v65=$2
    probe_v65=$(mktemp "$source_dir_v65/direct-io-v65.XXXXXX") || return 1
    probe_name_v65=${probe_v65##*/}
    lower_probe_v65="$base_dir_v65/$probe_name_v65"
    nonce_a_v65="v65-A-$$-$(cut -d' ' -f1 /proc/uptime)"
    nonce_b_v65=$(echo "$nonce_a_v65" | sed 's/v65-A-/v65-B-/')
    coherent_v65=1
    if printf '%s' "$nonce_a_v65" > "$probe_v65" &&
       [ -f "$lower_probe_v65" ] && [ ! -L "$lower_probe_v65" ] &&
       [ "$(cat "$lower_probe_v65")" = "$nonce_a_v65" ] &&
       [ "$(cat "$probe_v65")" = "$nonce_a_v65" ] &&
       printf '%s' "$nonce_b_v65" > "$lower_probe_v65" &&
       [ "$(cat "$probe_v65")" = "$nonce_b_v65" ]; then
        coherent_v65=0
    fi
    rm -f "$probe_v65" || return 1
    [ ! -e "$lower_probe_v65" ] || return 1
    return "$coherent_v65"
}
v65_sample_hash() {
    sample_file_v65=$(mktemp /var/tmp/kindle-io-sample-v65.XXXXXX) || return 1
    if "$BB" dd if="$1" of="$sample_file_v65" bs=65536 skip="$2" count=4 2>/dev/null &&
       [ "$("$BB" stat -c %s "$sample_file_v65")" = 262144 ]; then
        "$BB" sha256sum "$sample_file_v65" | awk '{print $1}'
        sample_ok_v65=0
    else
        sample_ok_v65=1
    fi
    rm -f "$sample_file_v65" || return 1
    return "$sample_ok_v65"
}
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Verify direct backing-image access v65 ==='
[ "$warm_v62" = 1 ] || { echo 'STOP: existing persistent image required; no new image created'; exit 1; }
awk '$2=="/mnt/base-us" && $3=="vfat" {found=1} END {exit !found}' /proc/mounts || { echo 'STOP: expected lower storage mount unavailable'; exit 1; }
lower_dir_v65=/mnt/base-us/kindle-system-test
lower_image_v65="$lower_dir_v65/kindle-persistent-v62.img"
[ -d "$lower_dir_v65" ] && [ ! -L "$lower_dir_v65" ] &&
[ -f "$lower_image_v65" ] && [ ! -L "$lower_image_v65" ] || { echo 'STOP: direct image path unavailable'; exit 1; }
[ "$(cat "$PERSIST_OWNER")" = kindle-persistent-v62 ] &&
[ "$(cat "$lower_dir_v65/kindle-persistent-v62.owner")" = kindle-persistent-v62 ] || { echo 'STOP: image owner markers differ'; exit 1; }
v65_same_view /mnt/us/kindle-system-test "$lower_dir_v65" || { echo 'STOP: two-way file coherence check failed; image was not modified'; exit 1; }
for image_view_v65 in "$PERSIST_IMAGE" "$lower_image_v65"; do
    [ "$("$BB" stat -c %s "$image_view_v65")" = 1610612736 ] || { echo 'STOP: image size differs'; exit 1; }
done
for sample_offset_v65 in 0 24572; do
    upper_hash_v65=$(v65_sample_hash "$PERSIST_IMAGE" "$sample_offset_v65") || exit 1
    lower_hash_v65=$(v65_sample_hash "$lower_image_v65" "$sample_offset_v65") || exit 1
    [ -n "$upper_hash_v65" ] && [ "$upper_hash_v65" = "$lower_hash_v65" ] || { echo 'STOP: image sample differs; image was not modified'; exit 1; }
done
PERSIST_IMAGE="$lower_image_v65"
echo "DIRECT_IMAGE_PATH_VERIFIED_V65 path=$PERSIST_IMAGE"
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Persistent runtime image v62 ==='
IMAGE="$PERSIST_IMAGE"
if [ "$warm_v62" = 1 ]; then
    [ ! -L "$IMAGE" ] && [ -f "$PERSIST_OWNER" ] && [ ! -L "$PERSIST_OWNER" ] || { echo 'STOP: persistent image ownership marker missing'; exit 1; }
    [ "$(cat "$PERSIST_OWNER")" = kindle-persistent-v62 ] || exit 1
    [ "$("$BB" stat -c %s "$IMAGE")" = 1610612736 ] || exit 1
    echo PERSISTENT_IMAGE_REUSED_V62
else
    [ ! -e "$IMAGE" ] && [ ! -L "$IMAGE" ] || exit 1
    ARCHIVE=/mnt/us/kindle-system-test/root-1536m-v35.img.gz
    [ "$("$BB" sha256sum "$ARCHIVE" | awk '{print $1}')" = 5d20315fcf519284cc5c89581b3e0699cb772791506c08974364723b30fcac5e ] || exit 1
    image_new_v62=$(mktemp /mnt/us/kindle-system-test/kindle-persistent-v62.new.XXXXXX) || exit 1
    "$BB" gzip -dc "$ARCHIVE" > "$image_new_v62" || { rm -f "$image_new_v62"; exit 1; }
    [ "$("$BB" stat -c %s "$image_new_v62")" = 1610612736 ] || { rm -f "$image_new_v62"; exit 1; }
    sync
    mv "$image_new_v62" "$IMAGE" || exit 1
    echo kindle-persistent-v62 > "$PERSIST_OWNER" || exit 1
    echo PERSISTENT_IMAGE_CREATED_V62
fi
ROOT=/var/tmp/kindle-framework-root.persist-v62
[ ! -L "$ROOT" ] || exit 1
awk -v p="$ROOT" '$2 == p || index($2,p "/") == 1 {bad=1} END {exit bad}' /proc/mounts || { echo 'STOP: persistent mountpoint is already mounted'; exit 1; }
if [ -e "$ROOT" ]; then
    rmdir "$ROOT" || { echo 'STOP: persistent mountpoint is not empty'; exit 1; }
fi
mkdir -p "$ROOT" || exit 1
ROOT=$(readlink -f "$ROOT") || exit 1
echo "Canonical runtime root: $ROOT"
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Bind a free loop device using sysfs ==='
echo "Backing image: $IMAGE"
ls -l "$IMAGE"
echo 'BusyBox automatic selection (diagnostic only):'
"$BB" losetup -f 2>&1 || true
LOOPDIR=$(mktemp -d /dev/kindle-framework-loop.XXXXXX) || exit 1
for entry in /sys/block/loop[0-9]*; do
    [ -d "$entry" ] || continue
    [ -r "$entry/dev" ] || continue
    if [ -e "$entry/loop/backing_file" ]; then
        echo "Skip bound device: ${entry##*/}"
        continue
    fi
    devnums=$(cat "$entry/dev") || continue
    devmajor=${devnums%:*}
    devminor=${devnums#*:}
    case "$devmajor:$devminor" in *[!0-9:]*|:*) continue;; esac
    [ -n "$devmajor" ] && [ -n "$devminor" ] || continue
    "$BB" mknod "$LOOPDIR/device" b "$devmajor" "$devminor" || exit 1
    chmod 600 "$LOOPDIR/device" || exit 1
    echo "Trying ${entry##*/} ($devmajor:$devminor) via $LOOPDIR/device"
    if "$BB" losetup "$LOOPDIR/device" "$IMAGE"; then
        LOOP="$LOOPDIR/device"
        echo "Bound device: ${entry##*/}"
        cat "$entry/loop/backing_file" 2>/dev/null || true
        break
    fi
    echo 'Binding failed; no detach attempted for this candidate'
    rm -f "$LOOPDIR/device" || exit 1
done
[ -n "$LOOP" ] || { echo 'STOP: no available loop device could be bound'; exit 1; }
# Use the owned image's mount only. noatime avoids read-induced inode writes.

if [ -f /mnt/us/kindle-system-test/buffered-loop-v99 ]; then
    echo LOOP_BUFFERED_CONTROL_V99
else
    loop_tools99=$(mktemp -d /var/tmp/kindle-loop-io-v99.XXXXXX) || exit 1
    cp /mnt/us/kindle-system-test/loop-io-v99 "$loop_tools99/loop-io-v99" || exit 1
    [ "$("$BB" sha256sum "$loop_tools99/loop-io-v99" | awk '{print $1}')" = f2a91d1fa25740dbb0a2cbc3db76ab83d5357ad0bdaf4abf30e995f2d61f83dd ] || exit 1
    chmod 700 "$loop_tools99/loop-io-v99" || exit 1
    "$loop_tools99/loop-io-v99" "$LOOP" "$IMAGE" > "$LOGDIR/loop-mode-v99.txt" 2>&1
    loop_result99=$?
    cat "$LOGDIR/loop-mode-v99.txt"
    rm -f "$loop_tools99/loop-io-v99"
    rmdir "$loop_tools99"
    case "$loop_result99" in
        0) echo LOOP_DIRECT_MODE_ACTIVE_V99 ;;
        2) echo LOOP_BUFFERED_FALLBACK_V99 ;;
        *) echo 'STOP: loop mode could not be verified'; exit 1 ;;
    esac
fi
"$MOUNT" -t ext3 -o rw,nosuid,exec,noatime "$LOOP" "$ROOT" || exit 1
mounted=1
awk -v p="$ROOT" '$2 == p {print}' /proc/mounts > "$LOGDIR/image-mount-v96.txt"
awk -v p="$ROOT" '$2 == p && ("," $4 ",") ~ /,noatime,/ {ok=1} END {exit !ok}' /proc/mounts || {
    echo 'STOP: noatime image mount not confirmed'
    exit 1
}
echo IMAGE_NOATIME_CONFIRMED_V96
[ "$(cat "$ROOT/kindle-framework-test-root")" = kindle-framework-smoke-v1 ] || exit 1
if [ -e "$ROOT/test/aot-backup-v101/pending" ]; then
    aot_restore101 || { echo 'STOP: pending optimization recovery failed'; exit 1; }
fi
if [ "${KINDLE_AOT_V101:-}" = rollback ]; then
    aot_restore101 || { echo 'STOP: AOT rollback could not be verified'; exit 1; }
    echo AOT_ROLLBACK_COMPLETE_V101
    exit 0
fi

# Reset only transient files inside this owned Android image.
# Reject nested mounts before touching its private /dev.
awk -v p="$ROOT/dev" '$2 == p || index($2,p "/") == 1 {bad=1} END {exit bad}' /proc/mounts || { echo 'STOP: nested device mount detected'; exit 1; }
[ -d "$ROOT/dev" ] && [ ! -L "$ROOT/dev" ] || exit 1
for node_v62 in null zero random urandom ashmem binder; do
    rm -f "$ROOT/dev/$node_v62" || exit 1
done
rm -rf "$ROOT/dev/socket" "$ROOT/dev/__properties__" || exit 1
mkdir -p "$ROOT/dev/socket" || exit 1
rm -f "$ROOT/test/compositor-ready-v54" "$ROOT/test/mesa-swapped-v54" || exit 1

read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
# V100: validate unchanged files using their previously verified metadata.
# This is a performance cache, not a replacement for periodic content audits.
# Missing cache, changed metadata or force-full-check-v100 always hashes content.
verify_index100() (
    index100=$1
    output100=$2
    case "$index100" in /*) ;; *) index100="$ROOT/$index100";; esac
    [ -s "$index100" ] && [ ! -L "$index100" ] || exit 1
    cache100="$ROOT/test/verified-content-v100"
    [ ! -L "$cache100" ] || exit 1
    mkdir -p "$cache100" || exit 1
    chmod 700 "$cache100" || exit 1
    key100=$("$BB" sha256sum "$index100" | awk '{print $1}') || exit 1
    case "$key100" in ''|*[!0-9a-f]*) exit 1;; esac
    [ "${#key100}" = 64 ] || exit 1
    temp100=$(mktemp -d "$cache100/pending.XXXXXX") || exit 1
    trap 'rm -rf "$temp100"' EXIT
    set --
    while IFS= read -r line100 || [ -n "$line100" ]; do
        hash100=${line100%% *}
        rel100=${line100#*  }
        case "$hash100" in ''|*[!0-9a-f]*) exit 1;; esac
        [ "${#hash100}" = 64 ] || exit 1
        case "$rel100" in ''|/*|../*|*/../*|*/..|*'|'*) exit 1;; esac
        [ -f "$ROOT/$rel100" ] && [ ! -L "$ROOT/$rel100" ] || exit 1
        set -- "$@" "$ROOT/$rel100"
    done < "$index100"
    [ "$#" -gt 0 ] || exit 1
    # %y includes subsecond modification time when supported by BusyBox.
    # Deliberately omit ctime: the existing installer re-applies chmod/chown.
    if ! "$BB" stat -c '%i|%s|%y|%n' "$@" > "$temp100/current" ||
       grep -q '%[iysn]' "$temp100/current"; then
        (cd "$ROOT" && "$BB" sha256sum -c "$index100") > "$output100" 2>&1
        exit $?
    fi
    count100=0
    if [ -f "$cache100/$key100.count" ] && [ ! -L "$cache100/$key100.count" ]; then
        read count100 < "$cache100/$key100.count"
    fi
    case "$count100" in ''|*[!0-9]*|????*) count100=0;; esac
    if [ "$count100" -gt 0 ] && [ "$count100" -lt 8 ] &&
       [ ! -e /mnt/us/kindle-system-test/force-full-check-v100 ] &&
       [ -s "$cache100/$key100.stat" ] && [ ! -L "$cache100/$key100.stat" ] &&
       [ "$(wc -l < "$cache100/$key100.stat")" = "$#" ]; then
        awk 'NR==FNR {old[FNR]=$0; next} old[FNR]!=$0 {print FNR}' \
            "$cache100/$key100.stat" "$temp100/current" > "$temp100/changed"
        if [ -s "$temp100/changed" ]; then
            awk 'NR==FNR {changed[$1]=1; next} FNR in changed {print}' \
                "$temp100/changed" "$index100" > "$temp100/check.sha256"
        else
            : > "$temp100/check.sha256"
        fi
        mode100=incremental
    else
        cp "$index100" "$temp100/check.sha256" || exit 1
        count100=0
        mode100=full
    fi
    if [ -s "$temp100/check.sha256" ]; then
        (cd "$ROOT" && "$BB" sha256sum -c "$temp100/check.sha256") > "$output100" 2>&1 || exit 1
    else
        echo VERIFIED_UNCHANGED_FILES_V100 > "$output100"
    fi
    # Never retain a snapshot if files changed during verification.
    "$BB" stat -c '%i|%s|%y|%n' "$@" > "$temp100/after" || exit 1
    cmp -s "$temp100/current" "$temp100/after" || exit 1
    changed100=$(wc -l < "$temp100/check.sha256")
    printf 'INDEX_CHECK_V100 mode=%s hashed=%s total=%s index=%s\n' \
        "$mode100" "$changed100" "$#" "$index100" >> "$LOGDIR/cache-summary-v100.txt"
    chmod 600 "$temp100/current" || exit 1
    mv -f "$temp100/current" "$cache100/$key100.stat" || exit 1
    echo $((count100 + 1)) > "$temp100/count" || exit 1
    mv -f "$temp100/count" "$cache100/$key100.count" || exit 1
    exit 0
)


component_state100() {
    awk -v section100="$2:" -v component100="$3" '
        $1 == "User" {user100=$2; sub(/:$/, "", user100); active100=0}
        { first100=match($0, /[^ \t]/); indent100=first100-1 }
        user100 == "0" && $1 == section100 {active100=1; level100=indent100; next}
        active100 && NF && indent100 <= level100 {active100=0}
        active100 && $1 == component100 {found100=1}
        END {exit !found100}
    ' "$1"
}

# Additional immutable archive reuse. Source archive hashes remain checked at each call.
extract_reuse78() {
    a78=$1
    n78=$2
    c78="$ROOT/test/archive-cache-v78"
    [ ! -L "$c78" ] || return 1
    mkdir -p "$c78" || return 1
    chmod 700 "$c78" || return 1
    key78=$("$BB" sha256sum "$a78" | awk '{print $1}') || return 1
    index78="$c78/$n78-$key78.sha256"
    if [ -s "$index78" ] && [ ! -L "$index78" ] &&
       verify_index100 "$index78" "$LOGDIR/archive-$n78-v78.txt"; then
        echo "ARCHIVE_REUSED_V78 name=$n78"
        return 0
    fi
    "$BB" tar -xzf "$a78" -C "$ROOT" || return 1
    "$BB" tar -tzf "$a78" > "$c78/$n78.list" || return 1
    : > "$index78.new" || return 1
    while IFS= read -r path78; do
        path78=${path78#./}
        case "$path78" in ''|*/) continue;; /*|../*|*/../*|*/..) return 1;; esac
        # Unsupported entries disable reuse, never fail an otherwise valid extraction.
        if [ -L "$ROOT/$path78" ] || [ ! -f "$ROOT/$path78" ]; then
            rm -f "$index78.new" "$index78"
            echo "ARCHIVE_REUSE_NOT_APPLICABLE_V78 name=$n78"
            return 0
        fi
        hash78=$("$BB" sha256sum "$ROOT/$path78" | awk '{print $1}') || return 1
        [ -n "$hash78" ] || return 1
        printf '%s  %s\n' "$hash78" "$path78" >> "$index78.new" || return 1
    done < "$c78/$n78.list"
    [ -s "$index78.new" ] || return 1
    chmod 600 "$index78.new" || return 1
    mv "$index78.new" "$index78" || return 1
    echo "ARCHIVE_INSTALLED_V78 name=$n78"
}
cache87="$ROOT/test/warm-system-v87"
cache_pending87=0

verify_warm_system87() {
    [ "$warm_v62" = 1 ] && [ ! -e /mnt/us/kindle-system-test/disable-warm-system-v87 ] || return 1
    [ -d "$cache87" ] && [ ! -L "$cache87" ] || return 1
    [ "$(cat "$cache87/ready" 2>/dev/null)" = "47724d560da1e5408ec025779e31aeaa6309a3099ac9b7fda98dd765abbb8f3d" ] || return 1
    for item87 in ready files.sha256 links dirs; do
        [ -f "$cache87/$item87" ] && [ ! -L "$cache87/$item87" ] || return 1
    done
    [ -s "$cache87/files.sha256" ] || return 1
    while IFS= read -r entry87; do
        rel87=${entry87#*  }
        [ -f "$ROOT/$rel87" ] && [ ! -L "$ROOT/$rel87" ] || return 1
    done < "$cache87/files.sha256"
    # This script is regenerated below on every launch.
    awk '$2 != "test/run-integration.sh" && $2 != "./test/run-integration.sh"' "$cache87/files.sha256" > "$LOGDIR/warm-static-files-v93.sha256" || return 1
    [ -s "$LOGDIR/warm-static-files-v93.sha256" ] || return 1
    verify_index100 "$LOGDIR/warm-static-files-v93.sha256" "$LOGDIR/warm-system-check-v87.txt" || return 1
    while IFS= read -r rel87; do
        [ -d "$ROOT/$rel87" ] && [ ! -L "$ROOT/$rel87" ] || return 1
    done < "$cache87/dirs"
    while IFS='|' read -r rel87 target87; do
        [ -L "$ROOT/$rel87" ] && [ "$(readlink "$ROOT/$rel87")" = "$target87" ] || return 1
    done < "$cache87/links"
    for rel87 in sbin/healthd system/bin/audioserver system/bin/kindle_socket_exec; do
        [ -x "$ROOT/$rel87" ] || return 1
    done
    return 0
}

save_warm_system87() (
PATCH=/mnt/us/kindle-system-test/runtime-fix-v2.tar.gz
BATCH=/mnt/us/kindle-system-test/runtime-batch-v9.tar.gz
HEALTH_PATCH=/mnt/us/kindle-system-test/health-input-v10.tar.gz
AUDIO_PATCH=/mnt/us/kindle-system-test/audio-runtime-v13.tar.gz
SYNC_PATCH=/mnt/us/kindle-system-test/soundpool-sync-v15.tar.gz
WIDGET_MEDIA=/mnt/us/kindle-system-test/widget-media-v17.tar.gz
    # Record the final installed versions after all overlapping patches.
    [ ! -e /mnt/us/kindle-system-test/disable-warm-system-v87 ] || exit 0
    [ ! -L "$cache87" ] || exit 1
    mkdir -p "$cache87" || exit 1
    chmod 700 "$cache87" || exit 1
    rm -f "$cache87/ready" || exit 1
    pending87=$(mktemp -d "$cache87/pending.XXXXXX") || exit 1
    trap 'rm -rf "$pending87"' EXIT
    : > "$pending87/paths" || exit 1
    for archive87 in "$PATCH" "$BATCH" "$HEALTH_PATCH" "$AUDIO_PATCH" "$SYNC_PATCH" "$WIDGET_MEDIA"; do
        "$BB" tar -tzf "$archive87" >> "$pending87/paths" || exit 1
    done
    printf '%s\n' system/framework/services.jar system/priv-app/SystemUI/SystemUI.apk \
        system/app/Launcher3/Launcher3.apk system/usr/share/zoneinfo/tzdata \
        system/lib/libandroid_runtime.so system/bin/kindle_socket_exec >> "$pending87/paths" || exit 1
    LC_ALL=C sort -u "$pending87/paths" > "$pending87/sorted" || exit 1
    for item87 in files.sha256 links dirs; do : > "$pending87/$item87" || exit 1; done
    while IFS= read -r rel87; do
        rel87=${rel87#./}
        rel87=${rel87%/}
        case "$rel87" in ''|.|test/run-integration.sh) continue;; esac
        case "$rel87" in
            dev|dev/input|sys|sys/class|sys/class/power_supply)
                [ -d "$ROOT/$rel87" ] && [ ! -L "$ROOT/$rel87" ] || exit 1
                continue ;;
            system|system/*|sbin|sbin/*|test|test/*) ;;
            *) echo "WARM_SYSTEM_UNSUPPORTED_V87 path=$rel87"; exit 1 ;;
        esac
        case "/$rel87/" in */../*|*/./*|*'|'*) exit 1;; esac
        parent87=$(readlink -f "$ROOT/${rel87%/*}") || exit 1
        case "$rel87" in */*) case "$parent87/" in "$ROOT/"*) ;; *) exit 1;; esac;; esac
        if [ -L "$ROOT/$rel87" ]; then
            target87=$(readlink "$ROOT/$rel87") || exit 1
            case "$target87" in *'|'*) exit 1;; esac
            printf '%s|%s\n' "$rel87" "$target87" >> "$pending87/links" || exit 1
        elif [ -d "$ROOT/$rel87" ]; then
            printf '%s\n' "$rel87" >> "$pending87/dirs" || exit 1
        elif [ -f "$ROOT/$rel87" ]; then
            (cd "$ROOT" && "$BB" sha256sum "$rel87") >> "$pending87/files.sha256" || exit 1
        else
            exit 1
        fi
    done < "$pending87/sorted"
    [ -s "$pending87/files.sha256" ] || exit 1
    for item87 in files.sha256 links dirs; do
        mv -f "$pending87/$item87" "$cache87/$item87" || exit 1
    done
    printf '%s\n' '47724d560da1e5408ec025779e31aeaa6309a3099ac9b7fda98dd765abbb8f3d' > "$pending87/ready" || exit 1
    mv -f "$pending87/ready" "$cache87/ready" || exit 1
    echo WARM_SYSTEM_CACHE_SAVED_V87
)

repair_warm_services108() (
    [ "$warm_v62" = 1 ] || exit 1
    [ ! -e /mnt/us/kindle-system-test/disable-warm-system-v87 ] || exit 1
    old_cache108="$cache87"
    [ -d "$old_cache108" ] && [ ! -L "$old_cache108" ] || exit 1
    for item108 in files.sha256 links dirs; do
        [ -f "$old_cache108/$item108" ] && [ ! -L "$old_cache108/$item108" ] || exit 1
    done
    [ ! -L "$old_cache108/ready" ] || exit 1
    [ ! -L "$ROOT/system/framework/services.jar" ] || exit 1
    expected108=f083d4f34e47382d17965a12e395ce251ae195ea6f252964f79df960758c723a
    actual108=$("$BB" sha256sum "$ROOT/system/framework/services.jar") || exit 1
    [ "${actual108%% *}" = "$expected108" ] || exit 1
    # No repair needed when the index already records this exact JAR and is ready.
    if [ -f "$old_cache108/ready" ] && grep -q "^$expected108  system/framework/services.jar$" "$old_cache108/files.sha256"; then
        exit 0
    fi
    candidate108=$(mktemp -d "$ROOT/test/warm-repair-v108.XXXXXX") || exit 1
    trap 'rm -rf "$candidate108"' EXIT
    awk -v h="$expected108" '
      $2 == "system/framework/services.jar" || $2 == "./system/framework/services.jar" {print h "  system/framework/services.jar"; n++; next}
      {print}
      END {if (n != 1) exit 1}
    ' "$old_cache108/files.sha256" > "$candidate108/files.sha256" || exit 1
    cp "$old_cache108/links" "$candidate108/links" || exit 1
    cp "$old_cache108/dirs" "$candidate108/dirs" || exit 1
    printf '%s\n' '47724d560da1e5408ec025779e31aeaa6309a3099ac9b7fda98dd765abbb8f3d' > "$candidate108/ready" || exit 1
    chmod 700 "$candidate108" || exit 1
    chmod 600 "$candidate108/"* || exit 1
    cache87="$candidate108"
    verify_warm_system87 || exit 1
    # Publish only after the existing full verifier accepts the candidate.
    mv -f "$candidate108/files.sha256" "$old_cache108/files.sha256" || exit 1
    mv -f "$candidate108/ready" "$old_cache108/ready" || exit 1
    echo WARM_SYSTEM_INDEX_RECOVERED_V108
)
repair_warm_services108 || echo WARM_INDEX_RECOVERY_NOT_APPLICABLE_V108

if verify_warm_system87; then
    echo WARM_SYSTEM_FILES_REUSED_V87
    mkdir -p "$ROOT/sys/class/power_supply" "$ROOT/dev/input" || exit 1
else
    echo WARM_SYSTEM_FULL_PREP_V87
    cache_pending87=1
echo '=== Apply integration v2 runtime fix ==='
PATCH=/mnt/us/kindle-system-test/runtime-fix-v2.tar.gz
[ -f "$PATCH" ] || { echo "Missing: $PATCH"; exit 1; }
[ "$("$BB" sha256sum "$PATCH" | awk '{print $1}')" = d19fe025f6a0374bebc24437e50dcf05519bfea2acf7c867a722484a2e665306 ] || { echo 'STOP: v2 patch checksum mismatch'; exit 1; }
"$BB" tar -xzf "$PATCH" -C "$ROOT" || exit 1
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install v5 inherited descriptor fix ==='
SOCKET_FIX=/mnt/us/kindle-system-test/kindle_socket_exec-v5
[ -s "$SOCKET_FIX" ] || { echo "Missing: $SOCKET_FIX"; exit 1; }
[ "$("$BB" sha256sum "$SOCKET_FIX" | awk '{print $1}')" = 25c648186d14f22eb17d81a890dbf26e9682404f347b65e845dcf3811174f631 ] || { echo 'STOP: v5 helper checksum mismatch'; exit 1; }
cp "$SOCKET_FIX" "$ROOT/system/bin/kindle_socket_exec" || exit 1
chmod 755 "$ROOT/system/bin/kindle_socket_exec" || exit 1
echo 'FD_FIX_INSTALLED: close inherited descriptors before creating control socket'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install v6 chroot path normalization ==='
RUNTIME_FIX=/mnt/us/kindle-system-test/libandroid_runtime-v6.so
[ -s "$RUNTIME_FIX" ] || { echo "Missing: $RUNTIME_FIX"; exit 1; }
[ "$("$BB" sha256sum "$RUNTIME_FIX" | awk '{print $1}')" = b6b367ec83df4436fefb78369889224c1607d99500860678518aec4c8171ec6d ] || { echo 'STOP: v6 runtime checksum mismatch'; exit 1; }
cp "$RUNTIME_FIX" "$ROOT/system/lib/libandroid_runtime.so" || exit 1
chmod 755 "$ROOT/system/lib/libandroid_runtime.so" || exit 1
echo 'PATH_FIX_INSTALLED: inode-checked normalization; original whitelist retained'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install integrated system applications ==='
BATCH=/mnt/us/kindle-system-test/runtime-batch-v9.tar.gz
[ -s "$BATCH" ] || { echo "Missing: $BATCH"; exit 1; }
[ "$("$BB" sha256sum "$BATCH" | awk '{print $1}')" = bf5ac30ad0f862e785fc3622fe93efc430514f9ed087c2ee2fa01af3e97e50fe ] || { echo 'STOP: v9 batch checksum mismatch'; exit 1; }
"$BB" tar -xzf "$BATCH" -C "$ROOT" || exit 1
chmod -R a+rX "$ROOT/system/app" "$ROOT/system/priv-app" || exit 1
[ -s "$ROOT/system/priv-app/PackageInstaller/PackageInstaller.apk" ] || { echo "STOP: missing PackageInstaller"; exit 1; }
[ -s "$ROOT/system/priv-app/StatementService/StatementService.apk" ] || { echo "STOP: missing StatementService"; exit 1; }
[ -s "$ROOT/system/priv-app/ExtServices/ExtServices.apk" ] || { echo "STOP: missing ExtServices"; exit 1; }
[ -s "$ROOT/system/app/ExtShared/ExtShared.apk" ] || { echo "STOP: missing ExtShared"; exit 1; }
[ -s "$ROOT/system/priv-app/SystemUI/SystemUI.apk" ] || { echo "STOP: missing SystemUI"; exit 1; }
[ -s "$ROOT/system/priv-app/Settings/Settings.apk" ] || { echo "STOP: missing Settings"; exit 1; }
[ -s "$ROOT/system/app/Launcher3/Launcher3.apk" ] || { echo "STOP: missing Launcher3"; exit 1; }
[ -s "$ROOT/system/priv-app/Shell/Shell.apk" ] || { echo "STOP: missing Shell"; exit 1; }
[ -s "$ROOT/system/priv-app/SettingsProvider/SettingsProvider.apk" ] || { echo "STOP: missing SettingsProvider"; exit 1; }
[ -s "$ROOT/system/priv-app/DownloadProvider/DownloadProvider.apk" ] || { echo "STOP: missing DownloadProvider"; exit 1; }
[ -s "$ROOT/system/app/DownloadProviderUi/DownloadProviderUi.apk" ] || { echo "STOP: missing DownloadProviderUi"; exit 1; }
[ -s "$ROOT/system/priv-app/MediaProvider/MediaProvider.apk" ] || { echo "STOP: missing MediaProvider"; exit 1; }
[ -s "$ROOT/system/priv-app/ExternalStorageProvider/ExternalStorageProvider.apk" ] || { echo "STOP: missing ExternalStorageProvider"; exit 1; }
[ -s "$ROOT/system/priv-app/DocumentsUI/DocumentsUI.apk" ] || { echo "STOP: missing DocumentsUI"; exit 1; }
[ -s "$ROOT/system/app/KeyChain/KeyChain.apk" ] || { echo "STOP: missing KeyChain"; exit 1; }
[ -s "$ROOT/system/app/CertInstaller/CertInstaller.apk" ] || { echo "STOP: missing CertInstaller"; exit 1; }
echo 'SYSTEM_APPS_READY: 16 packages installed'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install health and input components ==='
HEALTH_PATCH=/mnt/us/kindle-system-test/health-input-v10.tar.gz
[ -s "$HEALTH_PATCH" ] || { echo "Missing: $HEALTH_PATCH"; exit 1; }
[ "$("$BB" sha256sum "$HEALTH_PATCH" | awk '{print $1}')" = e87fc721659e5d59c98593f9e77a5ea482e868d6fc64c284d3c1f03f0c9e7e1b ] || { echo 'STOP: health/input checksum mismatch'; exit 1; }
extract_reuse78 "$HEALTH_PATCH" health-input || exit 1
chmod 755 "$ROOT/sbin/healthd" || exit 1
[ -s "$ROOT/system/lib/libjni_latinime.so" ] || exit 1
mkdir -p "$ROOT/sys/class/power_supply" "$ROOT/dev/input" || exit 1
echo 'HEALTH_INPUT_READY: healthd, InputDevices, LatinIME'
echo 'BATTERY_MODE: isolated fixed-power fallback, not physical Kindle charge level'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install isolated audio services ==='
AUDIO_PATCH=/mnt/us/kindle-system-test/audio-runtime-v13.tar.gz
[ -s "$AUDIO_PATCH" ] || { echo "Missing: $AUDIO_PATCH"; exit 1; }
[ "$("$BB" sha256sum "$AUDIO_PATCH" | awk '{print $1}')" = cca7230834ac1521da45b8c41862efb3665e68bc342fd896206a3a0524460d47 ] || { echo 'STOP: audio checksum mismatch'; exit 1; }
extract_reuse78 "$AUDIO_PATCH" audio || exit 1
chmod 755 "$ROOT/system/bin/audioserver" || exit 1
echo 'AUDIO_FILES_READY: default silent HAL, no physical audio device access'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install SoundPool and offline sync fix ==='
SYNC_PATCH=/mnt/us/kindle-system-test/soundpool-sync-v15.tar.gz
[ -s "$SYNC_PATCH" ] || { echo "Missing: $SYNC_PATCH"; exit 1; }
[ "$("$BB" sha256sum "$SYNC_PATCH" | awk '{print $1}')" = ed777b11970b044e157273a11553a3f51fc8dc61416582afbfe1f8d97f7c3b99 ] || { echo 'STOP: v15 payload checksum mismatch'; exit 1; }
"$BB" tar -xzf "$SYNC_PATCH" -C "$ROOT" || exit 1
[ "$("$BB" sha256sum "$ROOT/system/framework/services.jar" | awk '{print $1}')" = a1a14059df066fdc9b2f576064fd07038eb06b20e5755b4ab389731f48074047 ] || exit 1
[ "$("$BB" sha256sum "$ROOT/system/lib/libandroid_runtime.so" | awk '{print $1}')" = b6b367ec83df4436fefb78369889224c1607d99500860678518aec4c8171ec6d ] || exit 1
[ -s "$ROOT/system/lib/libsoundpool.so" ] || exit 1
echo 'SOUNDPOOL_SYNC_READY: dependency libraries installed; offline sync queries guarded'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install alarm delivery and test HOME fix ==='
ALARM_HOME_JAR=/mnt/us/kindle-system-test/services-alarm-home-v16.jar
[ -s "$ALARM_HOME_JAR" ] || { echo "Missing: $ALARM_HOME_JAR"; exit 1; }
[ "$("$BB" sha256sum "$ALARM_HOME_JAR" | awk '{print $1}')" = 2abbc92a1e3df1bde6a4a1da731a6770f50266d46940f0a034e5ac1932ffa12b ] || { echo 'STOP: v16 JAR checksum mismatch'; exit 1; }
cp "$ALARM_HOME_JAR" "$ROOT/system/framework/services.jar" || exit 1
chown 0:0 "$ROOT/system/framework/services.jar" || exit 1
chmod 644 "$ROOT/system/framework/services.jar" || exit 1
[ "$("$BB" sha256sum "$ROOT/system/framework/services.jar" | awk '{print $1}')" = 2abbc92a1e3df1bde6a4a1da731a6770f50266d46940f0a034e5ac1932ffa12b ] || exit 1
echo 'ALARM_HOME_READY: listener alarm delivery and explicit test Launcher3 HOME'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install AppWidget feature and media JNI dependencies ==='
WIDGET_MEDIA=/mnt/us/kindle-system-test/widget-media-v17.tar.gz
[ -s "$WIDGET_MEDIA" ] || { echo "Missing: $WIDGET_MEDIA"; exit 1; }
[ "$("$BB" sha256sum "$WIDGET_MEDIA" | awk '{print $1}')" = 30f63e232cd0e375352b3f4e6ad85fe8dd75e5fd4d27c18f74fce1c5bca4ba8c ] || { echo 'STOP: v17 payload checksum mismatch'; exit 1; }
"$BB" tar -xzf "$WIDGET_MEDIA" -C "$ROOT" || exit 1
[ -s "$ROOT/system/lib/libmedia_jni.so" ] || exit 1
[ "$("$BB" sha256sum "$ROOT/system/lib/libandroid_runtime.so" | awk '{print $1}')" = b6b367ec83df4436fefb78369889224c1607d99500860678518aec4c8171ec6d ] || exit 1
grep -q 'android.software.app_widgets' "$ROOT/system/etc/permissions/android.software.app_widgets.xml" || exit 1
chmod 755 "$ROOT/system/etc/permissions" || exit 1
echo 'WIDGET_MEDIA_READY: AppWidget feature declared; media JNI dependencies installed'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install offline SystemUI ==='
SYSTEMUI_APK=/mnt/us/kindle-system-test/SystemUI-software-v20.apk
[ -s "$SYSTEMUI_APK" ] || { echo "Missing: $SYSTEMUI_APK"; exit 1; }
[ "$("$BB" sha256sum "$SYSTEMUI_APK" | awk '{print $1}')" = 87a7daba70ae1e5dd32f05cd60d3087792cf04ab87b9537716efca5ad221cebe ] || { echo 'STOP: SystemUI v20 checksum mismatch'; exit 1; }
mkdir -p "$ROOT/system/priv-app/SystemUI" || exit 1
cp "$SYSTEMUI_APK" "$ROOT/system/priv-app/SystemUI/SystemUI.apk" || exit 1
chown 0:0 "$ROOT/system/priv-app/SystemUI/SystemUI.apk" || exit 1
chmod 755 "$ROOT/system/priv-app/SystemUI" || exit 1
chmod 644 "$ROOT/system/priv-app/SystemUI/SystemUI.apk" || exit 1
[ "$("$BB" sha256sum "$ROOT/system/priv-app/SystemUI/SystemUI.apk" | awk '{print $1}')" = 87a7daba70ae1e5dd32f05cd60d3087792cf04ab87b9537716efca5ad221cebe ] || exit 1
[ "$(cat "$ROOT/kindle-framework-test-root")" = kindle-framework-smoke-v1 ] || exit 1
chmod 644 "$ROOT/kindle-framework-test-root" || exit 1
echo 'SYSTEMUI_OFFLINE_FILES_READY: APK installed; runtime activation must be confirmed in Android logs'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install software-rendered Launcher3 ==='
LAUNCHER_APK=/mnt/us/kindle-system-test/Launcher3-software-v20.apk
[ -s "$LAUNCHER_APK" ] || { echo "Missing: $LAUNCHER_APK"; exit 1; }
[ "$("$BB" sha256sum "$LAUNCHER_APK" | awk '{print $1}')" = 87865f608c03ffa91ec0cc08e1588669cdca85d08a65fc5cfc04d1b2efabbff2 ] || { echo 'STOP: Launcher3 v20 checksum mismatch'; exit 1; }
mkdir -p "$ROOT/system/app/Launcher3" || exit 1
cp "$LAUNCHER_APK" "$ROOT/system/app/Launcher3/Launcher3.apk" || exit 1
chown 0:0 "$ROOT/system/app/Launcher3/Launcher3.apk" || exit 1
chmod 755 "$ROOT/system/app/Launcher3" || exit 1
chmod 644 "$ROOT/system/app/Launcher3/Launcher3.apk" || exit 1
[ "$("$BB" sha256sum "$ROOT/system/app/Launcher3/Launcher3.apk" | awk '{print $1}')" = 87865f608c03ffa91ec0cc08e1588669cdca85d08a65fc5cfc04d1b2efabbff2 ] || exit 1
echo 'UI_SOFTWARE_APKS_READY: SystemUI and Launcher3 installed; rendering must be checked in logs'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install isolated boot lifecycle fix ==='
BOOT_FLOW_JAR=/mnt/us/kindle-system-test/services-boot-flow-v21.jar
[ -s "$BOOT_FLOW_JAR" ] || { echo "Missing: $BOOT_FLOW_JAR"; exit 1; }
[ "$("$BB" sha256sum "$BOOT_FLOW_JAR" | awk '{print $1}')" = e6e3967fa1022f8af89cf85de1aeef140b79441055ccc6b51232a89621a1aa6a ] || { echo 'STOP: boot flow v21 checksum mismatch'; exit 1; }
cp "$BOOT_FLOW_JAR" "$ROOT/system/framework/services.jar" || exit 1
chown 0:0 "$ROOT/system/framework/services.jar" || exit 1
chmod 644 "$ROOT/system/framework/services.jar" || exit 1
[ "$("$BB" sha256sum "$ROOT/system/framework/services.jar" | awk '{print $1}')" = e6e3967fa1022f8af89cf85de1aeef140b79441055ccc6b51232a89621a1aa6a ] || exit 1
echo 'BOOT_FLOW_FILES_READY: installed; check KINDLE_BOOT_FLOW and user lifecycle in Android logs'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install Android timezone database ==='
TZDATA=/mnt/us/kindle-system-test/tzdata-v22
[ -s "$TZDATA" ] || { echo "Missing: $TZDATA"; exit 1; }
[ "$("$BB" sha256sum "$TZDATA" | awk '{print $1}')" = d4078dcc81742b5725bd779447808ab0559024be51e61319477e8482f2b3b8dc ] || { echo 'STOP: tzdata checksum mismatch'; exit 1; }
mkdir -p "$ROOT/system/usr/share/zoneinfo" || exit 1
cp "$TZDATA" "$ROOT/system/usr/share/zoneinfo/tzdata" || exit 1
chown 0:0 "$ROOT/system/usr/share/zoneinfo/tzdata" || exit 1
chmod 755 "$ROOT/system/usr" "$ROOT/system/usr/share" "$ROOT/system/usr/share/zoneinfo" || exit 1
chmod 644 "$ROOT/system/usr/share/zoneinfo/tzdata" || exit 1
[ "$("$BB" sha256sum "$ROOT/system/usr/share/zoneinfo/tzdata" | awk '{print $1}')" = d4078dcc81742b5725bd779447808ab0559024be51e61319477e8482f2b3b8dc ] || exit 1
echo 'TZDATA_READY: installed before Zygote startup'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
fi
echo '=== Prepare physical desktop display ==='
FBINK_SOURCE=/mnt/us/kindle-system-test/fbink-image-v24
[ -s "$FBINK_SOURCE" ] || { echo "Missing: $FBINK_SOURCE"; exit 1; }
[ "$("$BB" sha256sum "$FBINK_SOURCE" | awk '{print $1}')" = 91ac03cd26e4473a93c2d05284bdb34b3ac43370275dc350071cf63bdc0040a9 ] || exit 1
FBINKDIR=$(mktemp -d /tmp/kindle-desktop-fbink.XXXXXX) || exit 1
cp "$FBINK_SOURCE" "$FBINKDIR/fbink-image" || exit 1
chmod 755 "$FBINKDIR/fbink-image" || exit 1
cp /mnt/us/kindle-system-test/frame-v73 "$FBINKDIR/frame-v73" || exit 1
[ "$("$BB" sha256sum "$FBINKDIR/frame-v73" | awk '{print $1}')" = a5ed975e4014ab9d6307f4483b773241fa6f5f9fd62f531287ea545506704f39 ] || exit 1
chmod 700 "$FBINKDIR/frame-v73" || exit 1
cp /mnt/us/kindle-system-test/controls-v78 "$FBINKDIR/controls-v78" || exit 1
[ "$("$BB" sha256sum "$FBINKDIR/controls-v78" | awk '{print $1}')" = 54695458419e45f6b1129d17ed2de1adeb44499f20919fa3aa43cfdeea81bb41 ] || exit 1
chmod 700 "$FBINKDIR/controls-v78" || exit 1
display_style_v73=gray
[ ! -f /mnt/us/kindle-system-test/grayscale-v73 ] || display_style_v73=gray
echo "DISPLAY_STYLE_V73 $display_style_v73"
cp /mnt/us/kindle-system-test/delay-v70 "$FBINKDIR/delay-v70" || exit 1
[ "$("$BB" sha256sum "$FBINKDIR/delay-v70" | awk '{print $1}')" = b42a6099d9ee8a257eefc9f383a7d3e480404e91d5a79f6d1d4923103e380476 ] || exit 1
chmod 700 "$FBINKDIR/delay-v70" || exit 1
"$FBINKDIR/delay-v70" --self-test > "$LOGDIR/delay-preflight-v70.txt" 2>&1 || { echo 'STOP: native millisecond delay preflight failed'; exit 1; }
echo NATIVE_DELAY_PREFLIGHT_PASSED_V70
cp /mnt/us/kindle-system-test/kindle-tools-v66 "$FBINKDIR/kindle-tools-v66" || exit 1
[ "$("$BB" sha256sum "$FBINKDIR/kindle-tools-v66" | awk '{print $1}')" = 4c6088090c6dca21331702cf64de4af7be4ac4e42f52a3ec79602af7a08787ba ] || exit 1
chmod 700 "$FBINKDIR/kindle-tools-v66" || exit 1
present_desktop() {
    frame=$1
    label=$2
    if [ "$label" = touch-live ]; then
        header_battery_v73=off
        if [ "$header_enabled_v73" = 1 ]; then header_battery_v73=${battery_last_v72:-unknown}; fi
        "$FBINKDIR/frame-v73" ink "$frame" "$FBINKDIR/ink-v66.ppm" "$header_battery_v73" "$display_style_v73" "$FBINKDIR/frame-prev-v76.gray" "$FBINKDIR/frame-state-v76.txt" "${settings_file78:-/nonexistent}" || return 1
        read frame_class76 changed_pixels76 < "$FBINKDIR/frame-state-v76.txt" || return 1
        [ "$frame_class76" != skip ] || return 0
        flash_v67=
        waveform_v72=GL16
        case "$frame_class76" in
            first) large_updates76=1; waveform_v72=GC16; flash_v67=-f;;
            large)
                large_updates76=$(( ${large_updates76:-0} + 1 ))
                waveform_v72=GC16
                flash_v67=
                if [ $((large_updates76 % 2)) = 0 ]; then flash_v67=-f; fi;;
            small)
                small_updates89=$(( ${small_updates89:-0} + 1 ))
                if [ $((small_updates89 % 24)) = 0 ]; then
                    waveform_v72=GC16
                    flash_v67=-f
                fi;;
            *) return 1;;
        esac
        echo "FRAME_POLICY_V90 class=$frame_class76 changed=$changed_pixels76 waveform=$waveform_v72 flash=${flash_v67:-none}"
        frame="$FBINKDIR/ink-v66.ppm"
    fi
    /usr/bin/setsid "$FBINKDIR/fbink-image" -w -W "$waveform_v72" $flash_v67 -g "file=$frame,w=1236,h=1648,halign=CENTER,valign=CENTER" 9>&- > "$LOGDIR/fbink-$label.txt" 2>&1 &
    presenter=$!
    (
        sleep 8
        kill -TERM -"$presenter" 2>/dev/null
        sleep 1
        kill -KILL -"$presenter" 2>/dev/null
    ) 9>&- &
    display_guard=$!
    wait "$presenter"
    display_result=$?
    kill "$display_guard" 2>/dev/null
    wait "$display_guard" 2>/dev/null
    display_guard=
    kill -KILL -"$presenter" 2>/dev/null
    if [ "$display_result" = 138 ] && [ "$warm_request111" = 1 ] && [ "$label" = touch-live ]; then
        wait "$presenter" 2>/dev/null
        echo FRAME_INTERRUPTED_BY_HIDE_REQUEST
        presenter=
        return 0
    fi
    presenter=
    echo "PHYSICAL_DISPLAY $label exit=$display_result"
    return "$display_result"
}

read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install standalone input runtime fix ==='
INPUT_RUNTIME=/mnt/us/kindle-system-test/libandroid_runtime-input-v28.so
[ -s "$INPUT_RUNTIME" ] || { echo "Missing: $INPUT_RUNTIME"; exit 1; }
[ "$("$BB" sha256sum "$INPUT_RUNTIME" | awk '{print $1}')" = 86fb4109fe9b2502b1839d355ec701c259731e433eec99133b46d93f2fa96ded ] || { echo 'STOP: input runtime checksum mismatch'; exit 1; }
cp "$INPUT_RUNTIME" "$ROOT/system/lib/libandroid_runtime.so" || exit 1
chown 0:0 "$ROOT/system/lib/libandroid_runtime.so" || exit 1
chmod 755 "$ROOT/system/lib/libandroid_runtime.so" || exit 1
[ "$("$BB" sha256sum "$ROOT/system/lib/libandroid_runtime.so" | awk '{print $1}')" = 86fb4109fe9b2502b1839d355ec701c259731e433eec99133b46d93f2fa96ded ] || exit 1
echo 'INPUT_RUNTIME_V28_INSTALLED: low heap opt-in only; confirm activation in Android log'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Prepare bounded physical touch tools ==='
TOUCH_SOURCE=/mnt/us/kindle-system-test/kindle_touch_bridge-v30
RELAY_SOURCE=/mnt/us/kindle-system-test/kindle-input-relay-v29.jar
[ "$("$BB" sha256sum "$TOUCH_SOURCE" | awk '{print $1}')" = 7ddb95675c60d2ad545e9bb3a55e0b20c375c85c9fe2b192b9412a8b29a63034 ] || { echo 'STOP: touch helper missing or checksum mismatch'; exit 1; }
[ "$("$BB" sha256sum "$RELAY_SOURCE" | awk '{print $1}')" = 20a7bf9edf48d45354ae6bd246ad4d94698c049e218471c3280c585dbc87d8ad ] || { echo 'STOP: relay missing or checksum mismatch'; exit 1; }
[ "$("$BB" sha256sum /mnt/us/kindle-system-test/touch-ready-v30.ppm | awk '{print $1}')" = 9c231174dbb366c61a9ec4d25be3d4c12ba06c1d45dbe505e775151a8286636e ] || exit 1
TOUCHDIR=$(mktemp -d /tmp/kindle-touch-v30.XXXXXX) || exit 1
cp "$TOUCH_SOURCE" "$TOUCHDIR/kindle_touch_bridge-v30" || exit 1
chmod 755 "$TOUCHDIR/kindle_touch_bridge-v30" || exit 1
cp "$RELAY_SOURCE" "$ROOT/test/kindle-input-relay-v29.jar" || exit 1
chown 0:0 "$ROOT/test/kindle-input-relay-v29.jar" || exit 1
chmod 644 "$ROOT/test/kindle-input-relay-v29.jar" || exit 1
[ "$("$BB" sha256sum "$ROOT/test/kindle-input-relay-v29.jar" | awk '{print $1}')" = 20a7bf9edf48d45354ae6bd246ad4d94698c049e218471c3280c585dbc87d8ad ] || exit 1
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install isolated Android power tools ==='
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install required media container service and native dependencies ==='
CONTAINER_PAYLOAD=/mnt/us/kindle-system-test/container-service-v32.tar.gz
[ "$("$BB" sha256sum "$CONTAINER_PAYLOAD" | awk '{print $1}')" = 68c86d8c9895f6620c3fad5e0ab8febaaa3e588738559dd8fad1a361ef85d5cf ] || { echo 'STOP: container payload missing or checksum mismatch'; exit 1; }
"$BB" tar -xzf "$CONTAINER_PAYLOAD" -C "$ROOT" || exit 1
cat > "$ROOT/test/container-files-v32.sha256" <<'CONTAINER_V32_HASHES'
a1d49c7e6c60f8ae033655167117225143cfe2e063436a3e889328d9ba29e046  system/lib/libbacktrace.so
1b1d1702460fc9b2e068259742b7acab05d4c000609af780ec9bf4a6863a183b  system/lib/libbase.so
ff4503006faf60cd5d20017a38d007dd9451ff35d15ce4b35fcb34e3d4c6e223  system/lib/libc++.so
4cb6c95b64a06ce449db9736e3bc64802ba7bca012a7b72d78ac913b6bc67f70  system/lib/libcutils.so
cb202771ff952b545ba3b3b847a0c1eb65c06c4c6c39246569f89a34d26b64d5  system/lib/libdefcontainer_jni.so
02aa0cd72ba7554266c3b0162ac35df24daf011efc60d109ca0538c871a1c696  system/lib/libdl.so
5efd0db22151bfd2afe76f31a361bfd303a7908e026217063917271ec60da877  system/lib/liblog.so
703bb6186c0b6c6fae3cb0c96082663bb5214530dc993a0360bfd5402f9a73d1  system/lib/liblzma.so
95dfc3ada1b8642be1520822bf60b802156e98c20e9155490d536e89c639eb09  system/lib/libm.so
41392e646e0d76ab5882a177222fe72c6747bfadd3d85877fa33a191b0b9d4c0  system/lib/libnativehelper.so
0ea69e9ae719693380ad04d1c2de1c64462e8020bb36c2bfc95f89701ee6eef3  system/lib/libunwind.so
c179c9f0edab6d722ade340e0407f116fa5ab1b3c0e4ef4e5b80be25e7ba5d11  system/lib/libutils.so
f2b1af7b65a29f4b608b15701f3b2d7cf835197e73ca899fa54cc5035c78b566  system/priv-app/DefaultContainerService/DefaultContainerService.apk
cb202771ff952b545ba3b3b847a0c1eb65c06c4c6c39246569f89a34d26b64d5  system/priv-app/DefaultContainerService/lib/arm/libdefcontainer_jni.so
CONTAINER_V32_HASHES
while read expected relative; do
    [ -n "$expected" ] || continue
    chown 0:0 "$ROOT/$relative" || exit 1
    chmod 644 "$ROOT/$relative" || exit 1
    [ "$("$BB" sha256sum "$ROOT/$relative" | awk '{print $1}')" = "$expected" ] || { echo "STOP: container file mismatch: $relative"; exit 1; }
done < "$ROOT/test/container-files-v32.sha256"
chmod 755 "$ROOT/system/priv-app/DefaultContainerService" "$ROOT/system/priv-app/DefaultContainerService/lib" "$ROOT/system/priv-app/DefaultContainerService/lib/arm" || exit 1
[ "$("$BB" sha256sum "$ROOT/system/lib/libandroid_runtime.so" | awk '{print $1}')" = 86fb4109fe9b2502b1839d355ec701c259731e433eec99133b46d93f2fa96ded ] || { echo 'STOP: patched Android runtime changed'; exit 1; }
echo 'CONTAINER_SERVICE_V32_INSTALLED: APK and full native dependency closure verified'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Prepare stream-write PackageManager tool ==='
PM_STREAM=/mnt/us/kindle-system-test/pm-stream-v31.jar
[ "$("$BB" sha256sum "$PM_STREAM" | awk '{print $1}')" = f871bfb11b3a3a6998dd463e7a95af3a11107e9a88889612a04383e3d2f340c9 ] || { echo 'STOP: stream pm JAR missing or checksum mismatch'; exit 1; }
cp "$PM_STREAM" "$ROOT/test/pm-stream-v31.jar" || exit 1
chown 0:0 "$ROOT/test/pm-stream-v31.jar" || exit 1
chmod 644 "$ROOT/test/pm-stream-v31.jar" || exit 1
[ "$("$BB" sha256sum "$ROOT/test/pm-stream-v31.jar" | awk '{print $1}')" = f871bfb11b3a3a6998dd463e7a95af3a11107e9a88889612a04383e3d2f340c9 ] || exit 1
echo 'PM_STREAM_V31_READY: opt-in stream write; commit and APK checks retained'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Prepare PackageManager paths ==='
JINJIANG_APK=/mnt/us/kindle-system-test/JJReader-7.1.7-official.apk
[ -s "$ROOT/system/framework/pm.jar" ] || { echo 'STOP: pm.jar is missing'; exit 1; }
mkdir -p "$ROOT/data/local/tmp" || exit 1
chmod 755 "$ROOT/data/local" "$ROOT/data/local/tmp" || exit 1
TOOL_JAR=/mnt/us/kindle-system-test/input-v23.jar
[ -s "$TOOL_JAR" ] || { echo "Missing: $TOOL_JAR"; exit 1; }
[ "$("$BB" sha256sum "$TOOL_JAR" | awk '{print $1}')" = 52b1a1ee330845527a94eb0aa1459316304033fce72f810f487f201bbc069151 ] || exit 1
cp "$TOOL_JAR" "$ROOT/system/framework/input.jar" || exit 1
chown 0:0 "$ROOT/system/framework/input.jar" || exit 1
chmod 644 "$ROOT/system/framework/input.jar" || exit 1
[ "$("$BB" sha256sum "$ROOT/system/framework/input.jar" | awk '{print $1}')" = 52b1a1ee330845527a94eb0aa1459316304033fce72f810f487f201bbc069151 ] || exit 1
TOOL_JAR=/mnt/us/kindle-system-test/svc-v23.jar
[ -s "$TOOL_JAR" ] || { echo "Missing: $TOOL_JAR"; exit 1; }
[ "$("$BB" sha256sum "$TOOL_JAR" | awk '{print $1}')" = 267af2bdb4ece68aa0929cc4b9e6a4542b289e500377e0ec007d41cf2efe5671 ] || exit 1
cp "$TOOL_JAR" "$ROOT/system/framework/svc.jar" || exit 1
chown 0:0 "$ROOT/system/framework/svc.jar" || exit 1
chmod 644 "$ROOT/system/framework/svc.jar" || exit 1
[ "$("$BB" sha256sum "$ROOT/system/framework/svc.jar" | awk '{print $1}')" = 267af2bdb4ece68aa0929cc4b9e6a4542b289e500377e0ec007d41cf2efe5671 ] || exit 1
TOOL_JAR=/mnt/us/kindle-system-test/settings-v23.jar
[ -s "$TOOL_JAR" ] || { echo "Missing: $TOOL_JAR"; exit 1; }
[ "$("$BB" sha256sum "$TOOL_JAR" | awk '{print $1}')" = 668f327b677d7f84ea19603902b48f79448b5bf93e8e033384e7e817f3ddadb0 ] || exit 1
cp "$TOOL_JAR" "$ROOT/system/framework/settings.jar" || exit 1
chown 0:0 "$ROOT/system/framework/settings.jar" || exit 1
chmod 644 "$ROOT/system/framework/settings.jar" || exit 1
[ "$("$BB" sha256sum "$ROOT/system/framework/settings.jar" | awk '{print $1}')" = 668f327b677d7f84ea19603902b48f79448b5bf93e8e033384e7e817f3ddadb0 ] || exit 1








# Correct ART runtime mode as well as the app_process Java entry mode.
cat > "$ROOT/test/run-integration.sh" <<'KINDLE_ZYGOTE_V4'
#!/system/bin/sh
export PATH=/system/bin:/system/xbin
export ANDROID_ROOT=/system ANDROID_DATA=/data ANDROID_STORAGE=/storage
export EXTERNAL_STORAGE=/sdcard ASEC_MOUNTPOINT=/mnt/asec
export BOOTCLASSPATH=/system/framework/core-oj.jar:/system/framework/core-libart.jar:/system/framework/conscrypt.jar:/system/framework/okhttp.jar:/system/framework/core-junit.jar:/system/framework/bouncycastle.jar:/system/framework/ext.jar:/system/framework/framework.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/ims-common.jar:/system/framework/apache-xml.jar:/system/framework/org.apache.http.legacy.boot.jar
export SYSTEMSERVERCLASSPATH=/system/framework/services.jar
export HOME=/data/local/tmp TMPDIR=/tmp ICU_DATA=/system/usr/icu
/system/bin/servicemanager > /test/servicemanager.txt 2>&1 &
sm=$!
echo "servicemanager=$sm"
sleep 1
/sbin/healthd < /dev/null > /test/healthd.txt 2>&1 &
health=$!
echo "healthd=$health"
health_ready=0
health_attempt=0
while [ "$health_attempt" -lt 20 ]; do
    kill -0 "$health" 2>/dev/null || { echo 'FAIL: healthd exited'; exit 1; }
    battery_check=$(/system/bin/service check batteryproperties 2>&1)
    echo "$battery_check" > /test/battery-check.txt
    if [ "$battery_check" = 'Service batteryproperties: found' ]; then
        health_ready=1
        break
    fi
    sleep 1
    health_attempt=$((health_attempt + 1))
done
[ "$health_ready" = 1 ] || { echo 'FAIL: batteryproperties not registered'; exit 1; }
echo 'BATTERY_SERVICE_READY: batteryproperties registered before Zygote'
/system/bin/audioserver < /dev/null > /test/audioserver.txt 2>&1 &
audio=$!
echo "audioserver=$audio"
audio_ready=0
audio_attempt=0
while [ "$audio_attempt" -lt 30 ]; do
    kill -0 "$audio" 2>/dev/null || { echo 'FAIL: audioserver exited'; exit 1; }
    policy_check=$(/system/bin/service check media.audio_policy 2>&1)
    flinger_check=$(/system/bin/service check media.audio_flinger 2>&1)
    { echo "$policy_check"; echo "$flinger_check"; } > /test/audio-check.txt
    if [ "$policy_check" = 'Service media.audio_policy: found' ] && [ "$flinger_check" = 'Service media.audio_flinger: found' ]; then
        audio_ready=1
        break
    fi
    sleep 1
    audio_attempt=$((audio_attempt + 1))
done
[ "$audio_ready" = 1 ] || { echo 'FAIL: audio services did not register'; exit 1; }
echo 'AUDIO_SERVICES_READY: policy and flinger before Zygote'
/system/bin/kindle_mesa_probe > /test/mesa-preflight-v52.txt 2>&1 || { cat /test/mesa-preflight-v52.txt; exit 1; }
echo MESA_PREFLIGHT_V52_OK
/system/bin/surfaceflinger > /test/surfaceflinger.txt 2>&1 &
sf_v53=$!
echo "surfaceflinger=$sf_v53"
sf_ready_v53=0
sf_wait_v53=0
while [ "$sf_wait_v53" -lt 40 ]; do
    kill -0 "$sf_v53" 2>/dev/null || { echo 'STOP: SurfaceFlinger exited'; exit 1; }
    sf_check_v53=$(/system/bin/service check SurfaceFlinger 2>&1)
    sf_driver_loaded=0
    while IFS= read -r sf_map_line; do
        case "$sf_map_line" in
            *'/system/lib/egl/libGLES.so'*) sf_driver_loaded=1;;
        esac
    done < "/proc/$sf_v53/maps"
    if [ "$sf_check_v53" = 'Service SurfaceFlinger: found' ] && [ "$sf_driver_loaded" = 1 ]; then
        sf_ready_v53=1
        break
    fi
    sleep 1
    sf_wait_v53=$((sf_wait_v53 + 1))
done
[ "$sf_ready_v53" = 1 ] || { echo 'STOP: compositor old-driver readiness timeout'; exit 1; }
echo "$sf_v53" > /test/compositor-ready-v54
swap_wait_v54=0
while [ ! -f /test/mesa-swapped-v54 ] && [ "$swap_wait_v54" -lt 60 ]; do
    sleep 1
    swap_wait_v54=$((swap_wait_v54 + 1))
done
[ -f /test/mesa-swapped-v54 ] || { echo 'STOP: host driver handoff timeout'; exit 1; }
echo COMPOSITOR_OLD_DRIVER_APP_MESA_V53_READY
/system/bin/kindle_socket_exec installd /system/bin/installd > /test/installd.txt 2>&1 &
installer=$!
echo "installd=$installer"
# A first diagnostic launch; keystore UID/capability setup will be refined from logs.
/system/bin/keystore /data/misc/keystore > /test/keystore.txt 2>&1 &
echo "keystore=$!"
sleep 2
kill -0 "$sm" 2>/dev/null || { echo 'FAIL: servicemanager exited before zygote'; exit 1; }
kill -0 "$installer" 2>/dev/null || { echo 'FAIL: installd exited before zygote'; exit 1; }
jit_options_v66=$(cat /test/jit-options-v66.txt)
/system/bin/kindle_socket_exec zygote /system/bin/app_process32 -Xzygote -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat $jit_options_v66 /system/bin --zygote --start-system-server --abi-list=armeabi-v7a,armeabi --socket-name=zygote < /dev/null > /dev/null 2>&1 &
z=$!
echo "zygote=$z"
echo 'Zygote stdio redirected to /dev/null; ART diagnostics are in android-log.bin' > /test/zygote.txt
echo "$z" > /test/zygote.pid
attempt=0
while [ "$attempt" -lt 180 ]; do
    if ! kill -0 "$z" 2>/dev/null; then
        wait "$z"
        rc=$?
        echo "ZYGOTE_EXIT: $rc"
        exit 1
    fi
    sleep 2
    attempt=$((attempt + 1))
    boot_services_ready=1
    for boot_service in activity package window input display; do
        boot_check=$(/system/bin/service check "$boot_service" 2>&1)
        [ "$boot_check" = "Service $boot_service: found" ] || boot_services_ready=0
    done
    [ -s /data/system/packages.xml ] || boot_services_ready=0
    if [ "$boot_services_ready" = 1 ]; then
        stable_ready=$(( ${stable_ready:-0} + 1 ))
    else
        stable_ready=0
    fi
    if [ "$stable_ready" -ge 3 ]; then
        echo "BOOT_READY_V52: stable core services and package database; ticks=$attempt"
        break
    fi
done
[ "${stable_ready:-0}" -ge 3 ] || {
    echo 'FAIL: core services did not become stable before timeout'
    exit 1
}
echo 'OBSERVATION_COMPLETE: zygote remained alive for observation window' 
exit 0
KINDLE_ZYGOTE_V4
[ "$?" = 0 ] || exit 1
chmod 755 "$ROOT/test/run-integration.sh" || exit 1
echo 'ZYGOTE_MODE_FIXED: -Xzygote before /system/bin; --zygote after it'
for name in libandroid.so libcompiler_rt.so libjnigraphics.so; do
    [ -s "$ROOT/system/lib/$name" ] || exit 1
    echo "PRELOAD_LIBRARY_PRESENT: $name"
done
mkdir -p "$ROOT/data/misc/user/0" "$ROOT/data/user_de/0" "$ROOT/data/system_de/0" "$ROOT/data/system_ce/0" "$ROOT/data/app-ephemeral" || exit 1
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Prepare isolated emulated-storage directory layout ==='
mkdir -p "$ROOT/storage/self" "$ROOT/mnt/user/0" || exit 1
chmod 755 "$ROOT/storage" "$ROOT/storage/self" "$ROOT/mnt" || exit 1
chmod 751 "$ROOT/mnt/user" "$ROOT/mnt/user/0" || exit 1
for view in default read write; do
    mkdir -p "$ROOT/mnt/runtime/$view/self" "$ROOT/mnt/runtime/$view/emulated/0" || exit 1
    chmod 755 "$ROOT/mnt/runtime/$view" "$ROOT/mnt/runtime/$view/self" "$ROOT/mnt/runtime/$view/emulated" || exit 1
    chown 1000:1000 "$ROOT/mnt/runtime/$view/emulated/0" || exit 1
    chmod 770 "$ROOT/mnt/runtime/$view/emulated/0" || exit 1
done
chmod 755 "$ROOT/mnt/runtime" || exit 1
ensure_link_v62 /storage/emulated/0 "$ROOT/mnt/user/0/primary" || exit 1
echo 'STORAGE_LAYOUT_READY: default/read/write, self, user 0; temporary test directories only'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Prepare integrated ART runtime ==='
[ -s "$ROOT/data/framework-boot/arm/boot.art" ] || exit 1
chmod -R a+rX "$ROOT/data/framework-boot" || exit 1
chmod 1777 "$ROOT/tmp" || exit 1
chmod 771 "$ROOT/data" || exit 1
for d in system system/users system/users/0 dalvik-cache dalvik-cache/arm resource-cache app app-private data user local local/tmp misc misc/profiles misc/profiles/cur misc/profiles/cur/0 misc/profiles/ref misc/user misc/user/0 user_de user_de/0 system_de system_de/0 system_ce system_ce/0 app-ephemeral; do
    chown 1000:1000 "$ROOT/data/$d" || exit 1
    chmod 775 "$ROOT/data/$d" || exit 1
done
chown 1017:1017 "$ROOT/data/misc/keystore" || exit 1
chmod 700 "$ROOT/data/misc/keystore" || exit 1
chown 1000:2001 "$ROOT/cache" || exit 1
chmod 770 "$ROOT/cache" || exit 1
chmod 755 "$ROOT/dev" "$ROOT/dev/socket" "$ROOT/test" || exit 1
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Prepare minimal runtime ==='
"$BB" mknod "$ROOT/dev/null" c 1 3 || exit 1
"$BB" mknod "$ROOT/dev/zero" c 1 5 || exit 1
"$BB" mknod "$ROOT/dev/random" c 1 8 || exit 1
"$BB" mknod "$ROOT/dev/urandom" c 1 9 || exit 1
chmod 666 "$ROOT/dev/null" "$ROOT/dev/zero" "$ROOT/dev/random" "$ROOT/dev/urandom" || exit 1
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Minimal public native library configuration ==='
mkdir -p "$ROOT/system/etc" || exit 1
# Required by AndroidRuntime even with image compilation disabled.
# Empty preload list keeps this isolated integration test small.
: > "$ROOT/system/etc/preloaded-classes" || exit 1

# This list is for the isolated Java smoke test, not a complete Android product.
for library in libc.so libdl.so libm.so liblog.so libstdc++.so libz.so libandroid.so; do
    [ -f "$ROOT/system/lib/$library" ] || { echo "Missing public library: $library"; exit 1; }
done
cat > "$ROOT/system/etc/public.libraries.txt" <<'LIBRARIES'
libc.so
libdl.so
libm.so
liblog.so
libstdc++.so
libz.so
libandroid.so
LIBRARIES
cat "$ROOT/system/etc/public.libraries.txt"
cp "$ROOT/system/etc/public.libraries.txt" "$LOGDIR/public-libraries.txt" || exit 1
echo "PUBLIC_LIBANDROID_V36_READY: configured before Zygote startup"
# Used only for three immutable, checksum-verified archives.
install_cached_archive_v68() {
    cache_archive_v68=$1
    cache_name_v68=$2
    cache_dir_v68="$ROOT/test/archive-cache-v68"
    [ ! -L "$cache_dir_v68" ] || return 1
    mkdir -p "$cache_dir_v68" || return 1
    chmod 700 "$cache_dir_v68" || return 1
    cache_index_v68="$cache_dir_v68/$cache_name_v68.sha256"
    if [ -s "$cache_index_v68" ] && [ ! -L "$cache_index_v68" ] &&
       verify_index100 "$cache_index_v68" "$LOGDIR/cache-$cache_name_v68.txt"; then
        echo "IMMUTABLE_ARCHIVE_REUSED_V68 name=$cache_name_v68"
        return 0
    fi
    case "$cache_name_v68" in
        webview-v42) expected_archive91=951571b604094e0838a92576781833bcf7fbdfd646912575e9ebaceaaa09cb64;;
        boot-v61) expected_archive91=72ffb72c61d3930bc6a34bef96c5e8a69d42359cebeef38fc4c7dffe8e6bd8b6;;
        font-v47) expected_archive91=4e111b695a0aa1435c3528788e099e08f48e7674a8eb3f7e881959296773dac8;;
        *) echo 'STOP: unknown archive'; return 1;;
    esac
    archive_hash91=$("$BB" sha256sum "$cache_archive_v68" | awk '{print $1}')
    [ "$archive_hash91" = "$expected_archive91" ] || {
        echo "STOP: archive checksum mismatch: $cache_name_v68"
        return 1
    }
    echo "ARCHIVE_SOURCE_VERIFIED_V91 name=$cache_name_v68"
    "$BB" tar -xzf "$cache_archive_v68" -C "$ROOT" || return 1
    "$BB" tar -tzf "$cache_archive_v68" > "$cache_dir_v68/$cache_name_v68.list" || return 1
    cache_new_v68="$cache_index_v68.new"
    : > "$cache_new_v68" || return 1
    while IFS= read -r cache_path_v68; do
        cache_path_v68=${cache_path_v68#./}
        case "$cache_path_v68" in ''|*/) continue;; /*|../*|*/../*|*/..) return 1;; esac
        [ -f "$ROOT/$cache_path_v68" ] && [ ! -L "$ROOT/$cache_path_v68" ] || return 1
        cache_hash_v68=$("$BB" sha256sum "$ROOT/$cache_path_v68" | awk '{print $1}') || return 1
        [ -n "$cache_hash_v68" ] || return 1
        printf '%s  %s\n' "$cache_hash_v68" "$cache_path_v68" >> "$cache_new_v68" || return 1
    done < "$cache_dir_v68/$cache_name_v68.list"
    [ -s "$cache_new_v68" ] || return 1
    chmod 600 "$cache_new_v68" || return 1
    mv "$cache_new_v68" "$cache_index_v68" || return 1
    echo "IMMUTABLE_ARCHIVE_INSTALLED_V68 name=$cache_name_v68"
}

read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install WebView v42 ==='
WV=/mnt/us/kindle-system-test/webview-v42.tar.gz
install_cached_archive_v68 "$WV" webview-v42 || exit 1
chown -R 0:0 "$ROOT/system/app/webview" || exit 1
chmod 755 "$ROOT/system/app/webview" "$ROOT/system/app/webview/lib" "$ROOT/system/app/webview/lib/arm" || exit 1
chmod 644 "$ROOT/system/app/webview/webview.apk" "$ROOT/system/app/webview/lib/arm/libwebviewchromium.so" "$ROOT/system/lib/libwebviewchromium_loader.so" "$ROOT/system/lib/libwebviewchromium_plat_support.so" || exit 1
[ -f "$ROOT/system/lib/libjnigraphics.so" ] || exit 1
grep -qx libjnigraphics.so "$ROOT/system/etc/public.libraries.txt" || echo libjnigraphics.so >> "$ROOT/system/etc/public.libraries.txt"
mkdir -p "$ROOT/data/misc/shared_relro" || exit 1
chown 1037:1037 "$ROOT/data/misc/shared_relro" || exit 1
chmod 771 "$ROOT/data/misc/shared_relro" || exit 1
echo WEBVIEW_FILES_INSTALLED_V42
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo SUPERSEDED_SERVICES_V43_COPY_SKIPPED_V100
echo SUPERSEDED_BOOT_PAYLOAD_SKIPPED_V66
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install paired Wi-Fi compatibility fix v61 ==='
LOGIN_PAYLOAD=/mnt/us/kindle-system-test/login-runtime-v61.tar.gz
install_cached_archive_v68 "$LOGIN_PAYLOAD" boot-v61 || exit 1
verify_index100 "test/login-v61.sha256" "$LOGDIR/login-integrity-v61.txt" || exit 1
chown -R 0:0 "$ROOT/data/framework-boot" || exit 1
chmod -R a+rX "$ROOT/data/framework-boot" || exit 1
chmod a+r "$ROOT/system/framework/"*.jar || exit 1
echo WIFI_MISSING_SERVICE_FIX_V61_READY
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install Chinese font v47 before Zygote ==='
JJ_FONT=/mnt/us/kindle-system-test/chinese-font-v47.tar.gz
cp "$ROOT/system/etc/fonts.xml" "$LOGDIR/fonts-before-v47.xml" || exit 1
install_cached_archive_v68 "$JJ_FONT" font-v47 || exit 1
[ -s "$ROOT/system/fonts/Roboto-Regular.ttf" ] || exit 1
chown 0:0 "$ROOT/system/fonts/NotoSansCJK-Regular.ttc" "$ROOT/system/etc/fonts.xml" || exit 1
chmod 644 "$ROOT/system/fonts/NotoSansCJK-Regular.ttc" "$ROOT/system/etc/fonts.xml" || exit 1
cp "$ROOT/system/etc/fonts.xml" "$LOGDIR/fonts-v47.xml" || exit 1
echo CHINESE_FONT_V47_READY
echo "PHASE_V52 mesa_install uptime=$(cut -d' ' -f1 /proc/uptime)"
JJ_MESA=/mnt/us/kindle-system-test/mesa-runtime-v52.tar.gz
[ "$("$BB" sha256sum "$JJ_MESA" | awk '{print $1}')" = b9086e32b14a846da474ebecbd9eef77e0b2fa9b5c27520a94da7f3e42fcc595 ] || { echo 'STOP: Mesa payload missing or damaged'; exit 1; }
extract_reuse78 "$JJ_MESA" mesa || exit 1
# Restore the original compositor driver before each startup.
if [ -f "$ROOT/test/compositor-original-v62.so" ]; then
    cp "$ROOT/test/compositor-original-v62.so" "$ROOT/system/lib/egl/libGLES.restore-v62.so" || exit 1
    mv -f "$ROOT/system/lib/egl/libGLES.restore-v62.so" "$ROOT/system/lib/egl/libGLES.so" || exit 1
else
    cp "$ROOT/system/lib/egl/libGLES.so" "$ROOT/test/compositor-original-v62.so" || exit 1
fi
# Replace the unsuffixed driver only inside this disposable image.
[ -f "$ROOT/system/lib/egl/libGLES.so" ] || exit 1
cp "$ROOT/system/lib/egl/libGLES.so" "$LOGDIR/libGLES-before-v52.so" || exit 1
# V53: leave the original compositor driver in place until SurfaceFlinger is ready.
chown 0:0 "$ROOT/system/lib/egl/libGLES.so" "$ROOT/system/lib/egl/libGLES_mesa.so" "$ROOT/system/lib/libglapi.so" "$ROOT/system/bin/kindle_mesa_probe" || exit 1
chmod 644 "$ROOT/system/lib/egl/libGLES.so" "$ROOT/system/lib/egl/libGLES_mesa.so" "$ROOT/system/lib/libglapi.so" || exit 1
chmod 755 "$ROOT/system/bin/kindle_mesa_probe" || exit 1
echo MESA_RUNTIME_V52_INSTALLED
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install host networking v59 ==='
NET_PAYLOAD=/mnt/us/kindle-system-test/network-runtime-v59.tar.gz
reuse_network108() (
    index108="$ROOT/test/network-v59.sha256"
    [ -s "$index108" ] && [ ! -L "$index108" ] || exit 1
    candidate108=$(mktemp "$LOGDIR/network-final-v108.XXXXXX") || exit 1
    trap 'rm -f "$candidate108"' EXIT
    # services.jar is intentionally superseded by the verified v107 build.
    # Verify that final version alongside every unchanged networking file.
    awk -v h=f083d4f34e47382d17965a12e395ce251ae195ea6f252964f79df960758c723a '
      $2 == "system/framework/services.jar" || $2 == "./system/framework/services.jar" {print h "  system/framework/services.jar"; n++; next}
      {print}
      END {if (n != 1) exit 1}
    ' "$index108" > "$candidate108" || exit 1
    verify_index100 "$candidate108" "$LOGDIR/network-integrity-v59.txt" || exit 1
)
if reuse_network108; then
    echo NETWORK_FINAL_FILES_REUSED_V108
else
[ "$("$BB" sha256sum "$NET_PAYLOAD" | awk '{print $1}')" = d8765066e1f69a41458ad2dd7187bf6b046b1db0c4835a0f088e045d5e9ae692 ] || { echo 'STOP: network payload checksum mismatch'; exit 1; }
"$BB" tar -xzf "$NET_PAYLOAD" -C "$ROOT" || exit 1
(
    cd "$ROOT" || exit 1
    "$BB" sha256sum -c test/network-v59.sha256
) > "$LOGDIR/network-integrity-v59.txt" 2>&1 || exit 1
fi
chown 0:0 "$ROOT/system/framework/services.jar" "$ROOT/system/framework/kindle-network-probe-v59.jar" || exit 1
chmod 644 "$ROOT/system/framework/services.jar" "$ROOT/system/framework/kindle-network-probe-v59.jar" || exit 1
chmod -R a+rX "$ROOT/system/etc/security/cacerts" || exit 1
[ -x /usr/bin/curl ] && [ -x /usr/bin/getent ] || { echo 'STOP: host curl/getent missing'; exit 1; }
/usr/bin/curl --connect-timeout 5 --max-time 15 -sS -o /dev/null -w '%{http_code}\n' https://www.jjwxc.net/ > "$LOGDIR/host-https-v59.txt" 2>&1
net_host_status=$?
[ "$net_host_status" = 0 ] && grep -qx 200 "$LOGDIR/host-https-v59.txt" || { echo 'STOP: connect Kindle Wi-Fi before this test'; exit 1; }
net_iface=$(ip -4 route show default | awk 'NR==1 {for(i=1;i<=NF;i++)if($i=="dev")print $(i+1)}')
net_gateway=$(ip -4 route show default | awk 'NR==1 {for(i=1;i<=NF;i++)if($i=="via")print $(i+1)}')
case "$net_iface" in ''|*[!a-zA-Z0-9_.-]*) echo 'STOP: missing IPv4 interface'; exit 1;; esac
net_address=$(ip -4 addr show dev "$net_iface" | awk '$1=="inet" {print $2;exit}')
net_dns=$(awk '$1=="nameserver" {if(n++)printf ",";printf "%s",$2} END {printf "\n"}' /etc/resolv.conf)
[ -n "$net_address" ] && [ -n "$net_gateway" ] && [ -n "$net_dns" ] || { echo 'STOP: incomplete host IPv4 settings'; exit 1; }
mkdir -p "$ROOT/dev/socket" "$ROOT/data/anr" || exit 1
chmod 1777 "$ROOT/data/anr" || exit 1
touch "$ROOT/data/anr/traces.txt" || exit 1
chmod 666 "$ROOT/data/anr/traces.txt" || exit 1
{
    echo enabled=1
    echo "iface=$net_iface"
    echo "address=$net_address"
    echo "gateway=$net_gateway"
    echo "dns=$net_dns"
} > "$ROOT/test/kindle-host-network-v59"
chmod 644 "$ROOT/test/kindle-host-network-v59" || exit 1
cp "$ROOT/test/kindle-host-network-v59" "$LOGDIR/host-network-v59.txt"
net_tools=$(mktemp -d /var/tmp/kindle-network-tools.XXXXXX) || exit 1
cp /mnt/us/kindle-system-test/kindle-dnsproxy-v59 "$net_tools/dnsproxy" || exit 1
[ "$("$BB" sha256sum "$net_tools/dnsproxy" | awk '{print $1}')" = 566ba69a5bc850853b29b877ed562766d6ccdfd654793827391590e3e9f6d555 ] || { echo 'STOP: DNS helper checksum mismatch'; exit 1; }
chmod 700 "$net_tools/dnsproxy" || exit 1
/usr/bin/setsid "$net_tools/dnsproxy" "$ROOT" > "$LOGDIR/dnsproxy-v59.txt" 2>&1 &
net_proxy=$!
net_ready=0
net_wait=0
while [ "$net_wait" -lt 10 ]; do
    if [ -S "$ROOT/dev/socket/dnsproxyd" ] && grep -q DNS_PROXY_V59_READY "$LOGDIR/dnsproxy-v59.txt"; then
        net_ready=1
        break
    fi
    kill -0 "$net_proxy" 2>/dev/null || break
    sleep 1
    net_wait=$((net_wait + 1))
done
[ "$net_ready" = 1 ] || { echo 'STOP: DNS proxy failed to start'; exit 1; }
# Reuse the host's routing. Do not start Android netd or reconfigure host Wi-Fi.
export ANDROID_NO_USE_FWMARK_CLIENT=1
unset ANDROID_DNS_MODE
echo HOST_DNS_PROXY_V59_READY
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Prepare ashmem ==='
[ "$(uname -r)" = 4.9.77-lab126 ] || { echo 'STOP: unexpected kernel'; exit 1; }
if ! grep -q '[[:space:]]ashmem$' /proc/misc; then
    if grep -q '^ashmem ' /proc/modules; then
        echo 'STOP: ashmem module present but device not registered'
        exit 1
    fi
    command -v insmod >/dev/null 2>&1 || exit 1
    command -v rmmod >/dev/null 2>&1 || exit 1
    [ -f /mnt/us/kindle-system-test/ashmem.ko ] || { echo 'STOP: /mnt/us/kindle-system-test/ashmem.ko missing'; exit 1; }
    module_hash=$("$BB" sha256sum /mnt/us/kindle-system-test/ashmem.ko | awk '{print $1}')
    [ "$module_hash" = 83651d086b694915082f30f1f61baa7a65af2efe3265f61d60a779a74e6dc658 ] || {
        echo 'STOP: ashmem module checksum mismatch'
        exit 1
    }
    insmod /mnt/us/kindle-system-test/ashmem.ko || exit 1
    ashmem_loaded=1
    echo 'ashmem loaded for this test'
else
    echo 'Reusing registered ashmem; this test will not unload it'
fi
minor=$(awk '$2 == "ashmem" {print $1}' /proc/misc)
case "$minor" in ''|*[!0-9]*) echo 'STOP: invalid ashmem registration'; exit 1;; esac
"$BB" mknod "$ROOT/dev/ashmem" c 10 "$minor" || exit 1
chmod 666 "$ROOT/dev/ashmem" || exit 1
echo "chroot ashmem: 10:$minor"
major_hex=${vdev%:*}
minor_hex=${vdev#*:}
case "$major_hex$minor_hex" in ''|*[!0-9a-fA-F]*) exit 1;; esac
"$BB" mknod "$ROOT/dev/binder" c "$((0x$major_hex))" "$((0x$minor_hex))" || exit 1
chmod 666 "$ROOT/dev/binder" || exit 1
[ "$("$BB" stat -L -c '%t:%T' "$ROOT/dev/binder")" = "$vdev" ] || exit 1
echo 'PASS: chroot binder maps only to host vndbinder' 
ensure_link_v62 /proc/self/fd "$ROOT/dev/fd" || exit 1
ensure_link_v62 /proc/self/fd/0 "$ROOT/dev/stdin" || exit 1
ensure_link_v62 /proc/self/fd/1 "$ROOT/dev/stdout" || exit 1
ensure_link_v62 /proc/self/fd/2 "$ROOT/dev/stderr" || exit 1

"$MOUNT" -t proc proc "$ROOT/proc" || exit 1
proc_mounted=1
unset LD_PRELOAD LD_LIBRARY_PATH ENV BASH_ENV JAVA_TOOL_OPTIONS _JAVA_OPTIONS
export ANDROID_ROOT=/system ANDROID_DATA=/data HOME=/ TMPDIR=/tmp
export ICU_DATA=/system/usr/icu TZ=GMT

# The socket and receiver exist only inside the temporary test root.
[ "$("$BB" sha256sum "$ROOT/system/bin/kindle_log_capture" | awk '{print $1}')" = 39cdeec50f6cbcf2c4d29ce354b42b1d16e8b8d77e7e2fbd15a6632d727d8c87 ] || {
    echo 'STOP: log receiver missing or checksum mismatch'; exit 1;
}
chmod 755 "$ROOT/system/bin/kindle_log_capture" || exit 1
(
    ulimit -c 0
    ulimit -f 32768
    exec "$BB" chroot "$ROOT" /system/bin/kindle_log_capture
) > "$LOGDIR/android-log.bin" 2> "$LOGDIR/log-capture-stderr.txt" &
capture=$!
ready=0
attempt=0
while [ "$attempt" -lt 10 ]; do
    kill -0 "$capture" 2>/dev/null || break
    if [ -S "$ROOT/dev/socket/logdw" ] && grep -q '^LOG_CAPTURE_READY' "$LOGDIR/android-log.bin"; then
        ready=1
        break
    fi
    attempt=$((attempt + 1))
    sleep 1
done
[ "$ready" = 1 ] || { echo 'STOP: log receiver did not become ready'; exit 1; }
echo 'PASS: isolated Android log receiver ready'

capture_zygote_threads() {
    label=$1
    [ -r "$ROOT/test/zygote.pid" ] || return 0
    z=$(cat "$ROOT/test/zygote.pid")
    case "$z" in ''|*[!0-9]*) return 0;; esac
    [ "$(readlink -f "/proc/$z/root" 2>/dev/null)" = "$ROOT" ] || return 0
    {
        date
        echo "ZYGOTE_PID: $z"
        cat "/proc/$z/status"
        cat "/proc/$z/stat"
        for task in /proc/"$z"/task/[0-9]*; do
            [ -d "$task" ] || continue
            echo "=== THREAD ${task##*/} ==="
            cat "$task/comm" "$task/status"
            echo '--- wchan ---'
            cat "$task/wchan"
            echo
            echo '--- syscall ---'
            cat "$task/syscall"
            echo '--- kernel stack ---'
            cat "$task/stack"
        done
    } > "$LOGDIR/zygote-threads-$label.txt" 2>&1
    cat "/proc/$z/maps" > "$LOGDIR/zygote-maps-$label.txt" 2>&1
    ls -l "/proc/$z/fd" > "$LOGDIR/zygote-fds-$label.txt" 2>&1
    if false; then
        [ -x "$ROOT/system/xbin/strace_kindle_static" ] || { echo 'DIAG: bundled strace unavailable'; return 0; }
        (
            ulimit -c 0
            ulimit -f 4096
            exec /usr/bin/setsid "$BB" chroot "$ROOT" /system/xbin/strace_kindle_static -f -tt -T -s 128 -p "$z" -o /test/zygote-trace.txt
        ) > "$LOGDIR/strace-attach.txt" 2>&1 &
        tracer=$!
        sleep 3
        kill -INT -"$tracer" 2>/dev/null
        sleep 1
        kill -KILL -"$tracer" 2>/dev/null
        wait "$tracer" 2>/dev/null
        tracer=
        echo 'DIAG: bounded Zygote syscall sample completed'
    fi
    return 0
}
run_probe() {
    label=$1
    shift
    echo "PROBE_START_V91 label=$label uptime=$(cut -d' ' -f1 /proc/uptime)"
    KINDLE_CHROOT_ROOT="$ROOT" /usr/bin/setsid "$BB" chroot "$ROOT" "$@" < "${PROBE_STDIN:-/dev/null}" 9>&- > "$LOGDIR/$label.txt" 2>&1 &
    probe=$!
    (
        sleep "${PROBE_TIMEOUT:-3}"
        kill -KILL -"$probe" 2>/dev/null
    ) &
    probe_guard=$!
    wait "$probe"
    probe_result=$?
    kill "$probe_guard" 2>/dev/null
    wait "$probe_guard" 2>/dev/null
    probe_guard=
    kill -KILL -"$probe" 2>/dev/null
    probe=
    echo "PROBE $label exit=$probe_result"
    echo "PROBE_END_V91 label=$label uptime=$(cut -d' ' -f1 /proc/uptime)"
}
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Configure PackageManager compilation policies ==='
# Replace only these keys, retaining all existing identity and heap settings.
sed '/^pm\.dexopt\./d; /^dalvik\.vm\.dex2oat-filter=/d' "$ROOT/test/integration.properties" > "$ROOT/test/integration.properties.v8" || exit 1
cat >> "$ROOT/test/integration.properties.v8" <<'KINDLE_PM_FILTERS'
pm.dexopt.first-boot=interpret-only
pm.dexopt.boot=interpret-only
pm.dexopt.install=interpret-only
pm.dexopt.bg-dexopt=interpret-only
pm.dexopt.ab-ota=interpret-only
pm.dexopt.nsys-library=interpret-only
pm.dexopt.shared-apk=interpret-only
pm.dexopt.forced-dexopt=interpret-only
pm.dexopt.core-app=interpret-only
dalvik.vm.dex2oat-filter=interpret-only
KINDLE_PM_FILTERS
[ "$?" = 0 ] || exit 1
mv "$ROOT/test/integration.properties.v8" "$ROOT/test/integration.properties" || exit 1
chmod 644 "$ROOT/test/integration.properties" || exit 1
grep '^pm\.dexopt\.' "$ROOT/test/integration.properties"
[ "$(grep -c '^pm\.dexopt\.' "$ROOT/test/integration.properties")" = 9 ] || { echo 'STOP: incomplete compiler policy configuration'; exit 1; }
echo 'PMS_FILTERS_READY: all 9 reasons use interpret-only'
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Set ART image paths for package compilation ==='
mkdir -p "$ROOT/system/framework/arm" || exit 1
image_count=0
for image_file in "$ROOT"/data/framework-boot/arm/boot*.art "$ROOT"/data/framework-boot/arm/boot*.oat; do
    [ -f "$image_file" ] || continue
    image_name=${image_file##*/}
    ensure_link_v62 "/data/framework-boot/arm/$image_name" "$ROOT/system/framework/arm/$image_name" || exit 1
    image_count=$((image_count + 1))
done
[ "$image_count" -ge 2 ] || { echo 'STOP: boot images missing'; exit 1; }
sed '/^dalvik\.vm\.dex2oat-flags=/d; /^dalvik\.vm\.boot-dex2oat-threads=/d' "$ROOT/test/integration.properties" > "$ROOT/test/integration.properties.v9" || exit 1
cat >> "$ROOT/test/integration.properties.v9" <<'KINDLE_ART_V9'
dalvik.vm.dex2oat-flags=--boot-image=/data/framework-boot/boot.art --runtime-arg -Xnorelocate
dalvik.vm.boot-dex2oat-threads=1
KINDLE_ART_V9
[ "$?" = 0 ] || exit 1
mv "$ROOT/test/integration.properties.v9" "$ROOT/test/integration.properties" || exit 1
chmod 644 "$ROOT/test/integration.properties" || exit 1
echo "ART_IMAGES_READY: $image_count image aliases; dex2oat uses existing boot image"
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Configure offline window-system test ==='
sed '/^config\.disable_storage=/d; /^config\.disable_network=/d; /^config\.disable_bluetooth=/d; /^config\.disable_location=/d; /^config\.disable_networktime=/d; /^config\.disable_serial=/d; /^config\.disable_consumerir=/d; /^config\.disable_vrmanager=/d; /^config\.disable_cameraservice=/d' "$ROOT/test/integration.properties" > "$ROOT/test/integration.properties.v10" || exit 1
cat >> "$ROOT/test/integration.properties.v10" <<'KINDLE_OFFLINE_V10'
config.disable_storage=false
config.disable_network=true
config.disable_bluetooth=true
config.disable_location=true
config.disable_networktime=true
config.disable_serial=true
config.disable_consumerir=true
config.disable_vrmanager=true
config.disable_cameraservice=true
KINDLE_OFFLINE_V10
[ "$?" = 0 ] || exit 1
mv "$ROOT/test/integration.properties.v10" "$ROOT/test/integration.properties" || exit 1
chmod 644 "$ROOT/test/integration.properties" || exit 1
echo 'OFFLINE_TEST: private internal storage enabled; native vold/netd absent'
# BEGIN_STORAGE_PREPARATION_V12
# Only operate inside the mounted and marker-verified temporary image.
[ "$(cat "$ROOT/kindle-framework-test-root")" = kindle-framework-smoke-v1 ] || exit 1
safe_storage_dir() {
    sd_rest=$1
    sd_path=$ROOT
    while [ -n "$sd_rest" ]; do
        sd_part=${sd_rest%%/*}
        case "$sd_part" in ''|.|..) echo 'STOP: invalid storage path'; return 1;; esac
        sd_path=$sd_path/$sd_part
        [ ! -L "$sd_path" ] || { echo "STOP: unexpected symlink: $sd_path"; return 1; }
        if [ ! -d "$sd_path" ]; then
            mkdir "$sd_path" || return 1
            chown 1000:1000 "$sd_path" || return 1
            chmod 0771 "$sd_path" || return 1
        fi
        case "$sd_rest" in */*) sd_rest=${sd_rest#*/};; *) sd_rest=;; esac
    done
}
safe_storage_dir data/system/users/0 || exit 1
chown 1000:1000 "$ROOT/data/system/users/0" || exit 1
chmod 0700 "$ROOT/data/system/users/0" || exit 1
safe_storage_dir data/misc/profiles/cur/0 || exit 1
chown 1000:1000 "$ROOT/data/misc/profiles/cur/0" || exit 1
chmod 0771 "$ROOT/data/misc/profiles/cur/0" || exit 1
safe_storage_dir data/misc/profiles/cur/0/foreign-dex || exit 1
chown 1000:1000 "$ROOT/data/misc/profiles/cur/0/foreign-dex" || exit 1
chmod 0773 "$ROOT/data/misc/profiles/cur/0/foreign-dex" || exit 1
safe_storage_dir data/system_de/0 || exit 1
chown 1000:1000 "$ROOT/data/system_de/0" || exit 1
chmod 0770 "$ROOT/data/system_de/0" || exit 1
safe_storage_dir data/misc_de/0 || exit 1
chown 1000:9998 "$ROOT/data/misc_de/0" || exit 1
chmod 01771 "$ROOT/data/misc_de/0" || exit 1
safe_storage_dir data/user_de/0 || exit 1
chown 1000:1000 "$ROOT/data/user_de/0" || exit 1
chmod 0771 "$ROOT/data/user_de/0" || exit 1
safe_storage_dir data/system_ce/0 || exit 1
chown 1000:1000 "$ROOT/data/system_ce/0" || exit 1
chmod 0770 "$ROOT/data/system_ce/0" || exit 1
safe_storage_dir data/misc_ce/0 || exit 1
chown 1000:9998 "$ROOT/data/misc_ce/0" || exit 1
chmod 01771 "$ROOT/data/misc_ce/0" || exit 1
safe_storage_dir data/media/0 || exit 1
chown 1023:1023 "$ROOT/data/media/0" || exit 1
chmod 0770 "$ROOT/data/media/0" || exit 1
safe_storage_dir data/data || exit 1
chown 1000:1000 "$ROOT/data/data" || exit 1
chmod 0771 "$ROOT/data/data" || exit 1
safe_storage_dir data/user || exit 1
if [ -L "$ROOT/data/user/0" ]; then
    target=$(readlink "$ROOT/data/user/0")
    case "$target" in /data/data|../data) ;; *) echo "STOP: unexpected user 0 target: $target"; exit 1;; esac
    rm "$ROOT/data/user/0" || exit 1
elif [ -d "$ROOT/data/user/0" ]; then
    # rmdir refuses a non-empty directory; never discard application data.
    rmdir "$ROOT/data/user/0" || { echo 'STOP: user 0 directory is not empty'; exit 1; }
elif [ -e "$ROOT/data/user/0" ]; then
    echo 'STOP: user 0 path is not a directory or expected link'
    exit 1
fi
ensure_link_v62 ../data "$ROOT/data/user/0" || exit 1
[ "$(readlink -f "$ROOT/data/user/0")" = "$ROOT/data/data" ] || exit 1
{
    echo 'Internal unencrypted storage; user 0; external volume intentionally absent'
    ls -ldn "$ROOT/data/data" "$ROOT/data/user/0" "$ROOT/data/user_de/0" "$ROOT/data/system/users/0" "$ROOT/data/system_de/0" "$ROOT/data/system_ce/0" "$ROOT/data/misc_de/0" "$ROOT/data/misc_ce/0" "$ROOT/data/media/0" "$ROOT/data/misc/profiles/cur/0" "$ROOT/data/misc/profiles/cur/0/foreign-dex"
} > "$LOGDIR/storage-layout.txt" 2>&1
sed '/^ro\.kindle\.test_storage=/d; /^ro\.crypto\.state=/d; /^persist\.sys\.emulate_fbe=/d' "$ROOT/test/integration.properties" > "$ROOT/test/integration.properties.v12" || exit 1
cat >> "$ROOT/test/integration.properties.v12" <<'STORAGE_PROPS_V12'
ro.kindle.test_storage=1
ro.crypto.state=unencrypted
persist.sys.emulate_fbe=false
STORAGE_PROPS_V12
[ "$?" = 0 ] || exit 1
mv "$ROOT/test/integration.properties.v12" "$ROOT/test/integration.properties" || exit 1
chmod 644 "$ROOT/test/integration.properties" || exit 1
sed '/^dalvik\.vm\.stack-trace-file=/d' "$ROOT/test/integration.properties" > "$ROOT/test/integration.properties.v59" || exit 1
echo 'dalvik.vm.stack-trace-file=/data/anr/traces.txt' >> "$ROOT/test/integration.properties.v59"
mv "$ROOT/test/integration.properties.v59" "$ROOT/test/integration.properties" || exit 1
cp "$ROOT/test/integration.properties" "$LOGDIR/integration.properties" || exit 1
echo 'STORAGE_LAYOUT_READY_V12: checked private directories, user 0 alias and storage properties'
# END_STORAGE_PREPARATION_V12
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Install matching ART and bounded JIT runtime v68 ==='
jit_archive_v66=/mnt/us/kindle-system-test/jit-runtime-v68.tar.gz
[ "$("$BB" sha256sum "$jit_archive_v66" | awk '{print $1}')" = 4a5f12d547e1161fa6233791e461117127c0ac88b0dccb052b0dc1377aa3afee ] || exit 1
jit_stage_v66=$(mktemp -d /var/tmp/kindle-jit-v68.XXXXXX) || exit 1
"$BB" tar -xzf "$jit_archive_v66" -C "$jit_stage_v66" || exit 1
# First validate the full closure. Only ART and its matching compiler may
# replace a known v66 version. Foundational dependencies must match exactly.
while read digest_v68 relative_v68; do
    case "$relative_v68" in lib/lib*.so) ;; *) exit 1;; esac
    case "$relative_v68" in *..*|*/*/*) exit 1;; esac
    [ "$("$BB" sha256sum "$jit_stage_v66/$relative_v68" | awk '{print $1}')" = "$digest_v68" ] || exit 1
    [ ! -L "$ROOT/system/$relative_v68" ] || exit 1
    if [ -e "$ROOT/system/$relative_v68" ]; then
        existing_v68=$("$BB" sha256sum "$ROOT/system/$relative_v68" | awk '{print $1}')
        if [ "$existing_v68" != "$digest_v68" ]; then
            case "$relative_v68:$existing_v68" in
                lib/libart.so:79c80dfbcb5c5b7cc6addbafddb5993bef4503215980a8294cb04aa3dcecddc1|lib/libart-compiler.so:b5bb117945752f0431a992dce5f00331d5498a4ad4763916405e5bd7ac00b868|lib/libart.so:5b3af2317f0e4c4c8adbf16e8f7be2a7764f2208dfd10afc836ac7d3ebe52776|lib/libart-compiler.so:b5bb117945752f0431a992dce5f00331d5498a4ad4763916405e5bd7ac00b868) ;;
                *) echo "STOP: unexpected installed dependency $relative_v68; retained"; exit 1;;
            esac
        fi
    fi
done < "$jit_stage_v66/jit-sha256-v68.txt"
while read digest_v68 relative_v68; do
    existing_v68=$("$BB" sha256sum "$ROOT/system/$relative_v68" 2>/dev/null | awk '{print $1}')
    if [ "$existing_v68" != "$digest_v68" ]; then
        cp "$jit_stage_v66/$relative_v68" "$ROOT/system/$relative_v68.v68-new" || exit 1
        chown 0:0 "$ROOT/system/$relative_v68.v68-new" || exit 1
        chmod 755 "$ROOT/system/$relative_v68.v68-new" || exit 1
        mv "$ROOT/system/$relative_v68.v68-new" "$ROOT/system/$relative_v68" || exit 1
    fi
done < "$jit_stage_v66/jit-sha256-v68.txt"
cp "$jit_stage_v66/jit-sha256-v68.txt" "$LOGDIR/jit-sha256-v68.txt"
rm -rf "$jit_stage_v66"
jit_stage_v66=
cp /mnt/us/kindle-system-test/kindle-jit-probe-v68.jar "$ROOT/test/kindle-jit-probe-v68.jar" || exit 1
[ "$("$BB" sha256sum "$ROOT/test/kindle-jit-probe-v68.jar" | awk '{print $1}')" = 2af4f718dd4daada9d3352a8c61c3d2825c80def9ccff7bc5c6f758a387509e7 ] || exit 1
chmod 644 "$ROOT/test/kindle-jit-probe-v68.jar" || exit 1
# Unify the properties and command-line settings. Input-only low-heap tools
# retain their explicit -Xint/-Xusejit:false override.
sed '/^dalvik\.vm\.usejit=/d; /^dalvik\.vm\.usejitprofiles=/d; /^dalvik\.vm\.execution-mode=/d; /^dalvik\.vm\.jitinitialsize=/d; /^dalvik\.vm\.jitmaxsize=/d' "$ROOT/test/integration.properties" > "$ROOT/test/integration.properties.v68" || exit 1
if [ -f /mnt/us/kindle-system-test/disable-jit-v66 ]; then
    echo '-Xint -Xusejit:false' > "$ROOT/test/jit-options-v66.txt"
    echo 'dalvik.vm.usejit=false' >> "$ROOT/test/integration.properties.v68"
    echo JIT_DISABLED_BY_USER_V68
else
    echo '-Xusejit:true -Xjitinitialsize:64K -Xjitmaxsize:8M' > "$ROOT/test/jit-options-v66.txt"
    echo 'dalvik.vm.usejit=true' >> "$ROOT/test/integration.properties.v68"
    echo 'dalvik.vm.usejitprofiles=false' >> "$ROOT/test/integration.properties.v68"
    echo 'dalvik.vm.jitinitialsize=64K' >> "$ROOT/test/integration.properties.v68"
    echo 'dalvik.vm.jitmaxsize=8M' >> "$ROOT/test/integration.properties.v68"
    echo JIT_REQUESTED_PENDING_ACTUAL_PROBE_V68
fi
mv "$ROOT/test/integration.properties.v68" "$ROOT/test/integration.properties" || exit 1
cp "$ROOT/test/integration.properties" "$LOGDIR/integration.properties" || exit 1
export KINDLE_JIT_VERIFY_V68=1
if [ -f /mnt/us/kindle-system-test/allow-x5-v75 ]; then
    unset KINDLE_FORCE_SYSTEM_WEBVIEW_V75
    echo JINJIANG_SYSTEM_WEBVIEW_POLICY_DISABLED_V75
else
    export KINDLE_FORCE_SYSTEM_WEBVIEW_V75=1
    echo JINJIANG_SYSTEM_WEBVIEW_POLICY_ARMED_V75
fi
sed '/^persist\.sys\.timezone=/d' "$ROOT/test/integration.properties" > "$ROOT/test/integration.properties.v72" || exit 1
echo 'persist.sys.timezone=Asia/Shanghai' >> "$ROOT/test/integration.properties.v72"
mv "$ROOT/test/integration.properties.v72" "$ROOT/test/integration.properties" || exit 1
cp "$ROOT/test/integration.properties" "$LOGDIR/integration.properties" || exit 1
date -u > "$LOGDIR/host-utc-v72.txt"
echo ANDROID_TIMEZONE_ASIA_SHANGHAI_V72
[ -f "$ROOT/system/app/LatinIME/LatinIME.apk" ] && [ ! -L "$ROOT/system/app/LatinIME/LatinIME.apk" ] || exit 1
if [ "$("$BB" sha256sum "$ROOT/system/app/LatinIME/LatinIME.apk" | awk '{print $1}')" = 9d826d5aa11b8a542bd7e41e318ab2421663ed45258ba7a3f5a55c3b8e972494 ]; then
    echo LATIN_IME_APK_UNCHANGED_V74
else
cp /mnt/us/kindle-system-test/LatinIME-software-v73.apk "$ROOT/system/app/LatinIME/LatinIME.apk.v73-new" || exit 1
[ "$("$BB" sha256sum "$ROOT/system/app/LatinIME/LatinIME.apk.v73-new" | awk '{print $1}')" = 9d826d5aa11b8a542bd7e41e318ab2421663ed45258ba7a3f5a55c3b8e972494 ] || exit 1
chown 0:0 "$ROOT/system/app/LatinIME/LatinIME.apk.v73-new" || exit 1
chmod 644 "$ROOT/system/app/LatinIME/LatinIME.apk.v73-new" || exit 1
mv "$ROOT/system/app/LatinIME/LatinIME.apk.v73-new" "$ROOT/system/app/LatinIME/LatinIME.apk" || exit 1
fi
cp /mnt/us/kindle-system-test/wm-v73.jar "$ROOT/test/wm-v73.jar" || exit 1
[ "$("$BB" sha256sum "$ROOT/test/wm-v73.jar" | awk '{print $1}')" = f5e289e44f7bf5af1c218e000e218144091ec1b5fe327cc351361362d9bd43a4 ] || exit 1
chmod 644 "$ROOT/test/wm-v73.jar" || exit 1
echo SOFTWARE_KEYBOARD_FILES_READY_V73
# Small, immutable IME tools are staged inside the owned private root.
for name74 in Trime-kindle-v74.apk ime-v74.jar; do
    [ ! -L "$ROOT/test/$name74" ] || exit 1
done
if [ ! -f "$ROOT/test/Trime-kindle-v74.apk" ] || [ "$("$BB" sha256sum "$ROOT/test/Trime-kindle-v74.apk" | awk '{print $1}')" != df616f707ea6517d6fc1891575200ccd550b699df5ffd7937b70980bd0ac936e ]; then
    cp /mnt/us/kindle-system-test/Trime-kindle-v74.apk "$ROOT/test/Trime-kindle-v74.apk.new" || exit 1
    [ "$("$BB" sha256sum "$ROOT/test/Trime-kindle-v74.apk.new" | awk '{print $1}')" = df616f707ea6517d6fc1891575200ccd550b699df5ffd7937b70980bd0ac936e ] || exit 1
    chmod 644 "$ROOT/test/Trime-kindle-v74.apk.new" || exit 1
    mv "$ROOT/test/Trime-kindle-v74.apk.new" "$ROOT/test/Trime-kindle-v74.apk" || exit 1
fi
cp /mnt/us/kindle-system-test/ime-v74.jar "$ROOT/test/ime-v74.jar" || exit 1
[ "$("$BB" sha256sum "$ROOT/test/ime-v74.jar" | awk '{print $1}')" = 11e7933050525a86baf73a1ff17c1139dde096932a7c3721d43620d2a05a8e0e ] || exit 1
chmod 644 "$ROOT/test/ime-v74.jar" || exit 1
[ "$("$BB" sha256sum /mnt/us/kindle-system-test/rime-data-v74.tar.gz | awk '{print $1}')" = 981efecaa93c2b3e9a98fb02eb534f3e12aa2ffe8afb481b90e10353fb089929 ] || exit 1
[ "$("$BB" sha256sum /mnt/us/kindle-system-test/trime-prefs-v74.xml | awk '{print $1}')" = 3221d9d7608d7fd788992b5a1481c7dbd633cb5015720a189a131381fa683d1e ] || exit 1
patch_rime_pages86() {
    for rel86 in build/default.yaml build/kindle_pinyin9.schema.yaml build/kindle_pinyin26.schema.yaml; do
        cfg86="$rime74/$rel86"
        [ -f "$cfg86" ] && [ ! -L "$cfg86" ] || continue
        tmp86=$(mktemp "$cfg86.new86.XXXXXX") || return 1
        if ! awk '
            /^menu:[[:space:]]*($|#)/ { in_menu=1; menu_seen=1; print; next }
            /^[^[:space:]#]/ && in_menu {
                if (!page_seen) { print "  page_size: 10"; page_seen=1 }
                in_menu=0
            }
            in_menu && /^  page_size:[[:space:]]*/ {
                if (!page_seen) print "  page_size: 10"
                page_seen=1
                next
            }
            { print }
            END {
                if (!menu_seen) print "menu:"
                if (!page_seen) print "  page_size: 10"
            }
        ' "$cfg86" > "$tmp86"; then
            rm -f "$tmp86"
            return 1
        fi
        if "$BB" cmp -s "$cfg86" "$tmp86"; then
            rm -f "$tmp86"
            continue
        fi
        if [ ! -e "$cfg86.previous86" ]; then
            cp -p "$cfg86" "$cfg86.previous86" || { rm -f "$tmp86"; return 1; }
        fi
        if ! chown "$uid74:$uid74" "$tmp86" || ! chmod 644 "$tmp86" || ! mv -f "$tmp86" "$cfg86"; then
            rm -f "$tmp86"
            return 1
        fi
        echo "RIME_PAGE_SIZE_V86 $rel86=10"
    done
}

seed_rime82() {
        if [ ! -f "$rime74/.data-981efecaa93c2b3e9a98fb02eb534f3e12aa2ffe8afb481b90e10353fb089929.done" ]; then
            "$BB" tar -xzf /mnt/us/kindle-system-test/rime-data-v74.tar.gz -C "$rime74" || return 1
            chmod 755 "$rime74" || return 1
            chmod 644 "$rime74"/*.yaml || return 1
            chown -R "$uid74:$uid74" "$rime74" || return 1
            echo ready > "$rime74/.data-981efecaa93c2b3e9a98fb02eb534f3e12aa2ffe8afb481b90e10353fb089929.done" || return 1
            chown "$uid74:$uid74" "$rime74/.data-981efecaa93c2b3e9a98fb02eb534f3e12aa2ffe8afb481b90e10353fb089929.done" || return 1
            echo CHINESE_IME_DICTIONARY_SEEDED_V74
        fi
    patch_rime_pages86
}
rime74="$ROOT/data/ime-rime-v74"
if [ ! -L "$rime74" ] && [ -f "$rime74/.kindle-ime-owner-v74" ]; then
    uid74=$("$BB" stat -c %u "$rime74")
    case "$uid74" in
        ''|*[!0-9]*) ;;
        *) if [ "$uid74" -ge 10000 ] && [ "$uid74" -lt 100000 ]; then seed_rime82 || exit 1; fi ;;
    esac
fi
echo CHINESE_IME_FILES_READY_V74
[ ! -L "$ROOT/system/framework/services.jar" ] || exit 1
if [ "$("$BB" sha256sum "$ROOT/system/framework/services.jar" | awk '{print $1}')" != f083d4f34e47382d17965a12e395ce251ae195ea6f252964f79df960758c723a ]; then
    cp /mnt/us/kindle-system-test/services-v115.jar "$ROOT/system/framework/services.jar.v76-new" || exit 1
    [ "$("$BB" sha256sum "$ROOT/system/framework/services.jar.v76-new" | awk '{print $1}')" = f083d4f34e47382d17965a12e395ce251ae195ea6f252964f79df960758c723a ] || exit 1
    chown 0:0 "$ROOT/system/framework/services.jar.v76-new" || exit 1
    chmod 644 "$ROOT/system/framework/services.jar.v76-new" || exit 1
    mv "$ROOT/system/framework/services.jar.v76-new" "$ROOT/system/framework/services.jar" || exit 1
    cache_pending87=1
    echo LMKD_SERVICES_INSTALLED_V115
fi
[ ! -L "$ROOT/system/framework/kindle-status-transform-v76.on" ] || exit 1
rm -f "$ROOT/system/framework/kindle-status-transform-v76.on" || exit 1
echo INSTALLER_AND_INPUT_SERVICES_READY_V76
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
cp /mnt/us/documents/kindle-jinjiang-v63-runtime.sh "$LOGDIR/runtime-script-v87.sh" || exit 1
cp /mnt/us/kindle-system-test/setup-inventory-v87.json "$LOGDIR/setup-inventory-v87.json" || exit 1

if [ "$cache_pending87" = 1 ]; then
    save_warm_system87 || echo WARM_SYSTEM_CACHE_NOT_SAVED_V87
fi
if [ "${KINDLE_AOT_V101:-}" = optimize ]; then
    sed 's/^dalvik\.vm\.dex2oat-Xmx=.*/dalvik.vm.dex2oat-Xmx=96m/' "$ROOT/test/integration.properties" > "$ROOT/test/integration.properties.v101" || exit 1
    mv -f "$ROOT/test/integration.properties.v101" "$ROOT/test/integration.properties" || exit 1
    cp "$ROOT/test/integration.properties" "$LOGDIR/integration.properties" || exit 1
fi
echo '=== Flush image writes before starting Android ==='
sync || exit 1
cat /proc/meminfo > "$LOGDIR/memory-prelaunch.txt"
cat /proc/swaps > "$LOGDIR/swaps-prelaunch.txt"
read stage_uptime76 stage_idle76 < /proc/uptime
echo "STAGE_TIME_V76 uptime=$stage_uptime76"
echo '=== Start isolated Android system (420 second limit) ==='
(
    ulimit -c 0
    # Permit the official 88 MiB APK; keep a finite per-file limit.
    # 524288 units is at least 256 MiB with either 512- or 1024-byte units.
    ulimit -f 524288 || exit 1
    echo "ANDROID_FILE_LIMIT_UNITS=$(ulimit -f)"
    export KINDLE_CHROOT_ROOT="$ROOT"
    exec /usr/bin/setsid "$BB" chroot "$ROOT" /system/bin/kindle_property_service /test/integration.properties /system/bin/sh /test/run-integration.sh
) > "$LOGDIR/session.txt" 2>&1 &
client=$!
(
    sleep 420
    if kill -0 "$client" 2>/dev/null; then
        echo 'TIMEOUT: integration observation limit reached'
        kill -TERM -"$client" 2>/dev/null
        sleep 2
        kill -KILL -"$client" 2>/dev/null
    fi
) &
guard=$!
i=0
while kill -0 "$client" 2>/dev/null && [ "$i" -lt 400 ]; do
    if [ -f "$ROOT/test/compositor-ready-v54" ] && [ ! -f "$ROOT/test/mesa-swapped-v54" ]; then
        read sf_pid_v54 < "$ROOT/test/compositor-ready-v54"
        case "$sf_pid_v54" in ''|*[!0-9]*) echo 'STOP: invalid compositor PID'; exit 1;; esac
        [ "$(readlink -f "/proc/$sf_pid_v54/root")" = "$ROOT" ] || exit 1
        cp "/proc/$sf_pid_v54/maps" "$ROOT/test/surfaceflinger-driver-before-v53.txt" || exit 1
        cp "$ROOT/system/lib/egl/libGLES_mesa.so" "$ROOT/system/lib/egl/libGLES.next-v54.so" || exit 1
        chown 0:0 "$ROOT/system/lib/egl/libGLES.next-v54.so" || exit 1
        chmod 644 "$ROOT/system/lib/egl/libGLES.next-v54.so" || exit 1
        mv -f "$ROOT/system/lib/egl/libGLES.next-v54.so" "$ROOT/system/lib/egl/libGLES.so" || exit 1
        cp "/proc/$sf_pid_v54/maps" "$ROOT/test/surfaceflinger-driver-after-v53.txt" || exit 1
        echo HOST_MESA_HANDOFF_V54_OK
        : > "$ROOT/test/mesa-swapped-v54"
    fi
    sleep 1
    i=$((i + 1))
    if [ $((i % 60)) = 0 ]; then
        run_probe "services-$i" /system/bin/service list
        capture_zygote_threads "$i"
        cat /proc/meminfo > "$LOGDIR/memory-$i.txt"
        for p in /proc/[0-9]*; do
            [ "$(readlink -f "$p/root" 2>/dev/null)" = "$ROOT" ] || continue
            echo "PID ${p##*/}"
            tr '\000' ' ' < "$p/cmdline" 2>/dev/null
            echo
            cat "$p/status" 2>/dev/null
        done > "$LOGDIR/processes-$i.txt"
    fi
done
wait "$client"
result=$?
kill "$guard" 2>/dev/null
wait "$guard" 2>/dev/null
guard=
client=
echo "Integration observation exit: $result"
cp "$ROOT/test/mesa-preflight-v52.txt" "$LOGDIR/mesa-preflight-v52.txt" 2>/dev/null
cp "$ROOT/test/surfaceflinger-driver-before-v53.txt" "$LOGDIR/" 2>/dev/null
cp "$ROOT/test/surfaceflinger-driver-after-v53.txt" "$LOGDIR/" 2>/dev/null
echo "PHASE_V52 core_ready uptime=$(cut -d' ' -f1 /proc/uptime)"
run_probe services-final /system/bin/service list
cat "$LOGDIR/session.txt"
cat "$LOGDIR/services-final.txt"
ready=1
for service in activity package window; do
    if grep -q "[[:space:]]$service: \[.[^]]*\]" "$LOGDIR/services-final.txt"; then
        echo "REGISTERED: $service"
    else
        echo "NOT_REGISTERED: $service"
        ready=0
    fi
done
if [ "$ready" = 1 ] && [ "$result" = 0 ]; then
    echo 'CORE_SERVICES_REGISTERED: activity package window'
    read stage_uptime76 stage_idle76 < /proc/uptime
    echo "STAGE_TIME_V76 uptime=$stage_uptime76"
    echo '=== Attempt to start the installed HOME application ==='
    export BOOTCLASSPATH=/system/framework/core-oj.jar:/system/framework/core-libart.jar:/system/framework/conscrypt.jar:/system/framework/okhttp.jar:/system/framework/core-junit.jar:/system/framework/bouncycastle.jar:/system/framework/ext.jar:/system/framework/framework.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/ims-common.jar:/system/framework/apache-xml.jar:/system/framework/org.apache.http.legacy.boot.jar
    PROBE_TIMEOUT=30
    PROBE_TIMEOUT=5
    run_probe power-settings-v92 /system/bin/dumpsys power
    # PowerManager can register before it loads persisted Settings.
    settings_wait93=0
    while [ "$probe_result" = 0 ] &&
          grep -Eq '^[[:space:]]*mMinimumScreenOffTimeoutConfig=0[[:space:]]*$' "$LOGDIR/power-settings-v92.txt" &&
          [ "$settings_wait93" -lt 3 ]; do
        sleep 2
        settings_wait93=$((settings_wait93 + 1))
        run_probe power-settings-v92 /system/bin/dumpsys power
    done
    if [ "$probe_result" = 0 ] &&
       grep -Eq '^[[:space:]]*mScreenOffTimeoutSetting=1800000[[:space:]]*$' "$LOGDIR/power-settings-v92.txt"; then
        echo SCREEN_TIMEOUT_REUSED_V92
    else
        PROBE_TIMEOUT=30
    run_probe screen-timeout /system/bin/sh -c 'export CLASSPATH=/system/framework/settings.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.settings.SettingsCmd put system screen_off_timeout 1800000'
        [ "$probe_result" = 0 ] || exit 1
    fi
    PROBE_TIMEOUT=30
    if grep -Eq '^[[:space:]]*mWakefulness=Awake[[:space:]]*$' "$LOGDIR/power-settings-v92.txt" &&
       grep -Eq '^[[:space:]]*mStayOn=true[[:space:]]*$' "$LOGDIR/power-settings-v92.txt" &&
       grep -Eq '^[[:space:]]*mStayOnWhilePluggedInSetting=7[[:space:]]*$' "$LOGDIR/power-settings-v92.txt"; then
        echo POWER_STAYON_STATE_REUSED_V100
    else
    run_probe power-stayon /system/bin/sh -c 'export CLASSPATH=/system/framework/svc.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.svc.Svc power stayon true'
    [ "$probe_result" = 0 ] || exit 1
    fi
    power_wait92=0
    while :; do
        PROBE_TIMEOUT=5
        run_probe power-before-home /system/bin/dumpsys power
        if [ "$probe_result" = 0 ] &&
           grep -q 'mWakefulness=Awake' "$LOGDIR/power-before-home.txt"; then break; fi
        [ "$power_wait92" -lt 3 ] || break
        power_wait92=$((power_wait92 + 1))
        sleep 1
    done
    if ! grep -q 'mWakefulness=Awake' "$LOGDIR/power-before-home.txt"; then
        echo 'POWER_WAKE_NOT_CONFIRMED: return logs before further testing'
        exit 1
    fi
    unset PROBE_TIMEOUT
    echo "PHASE_V52 skip_home uptime=$(cut -d' ' -f1 /proc/uptime)"
    PROBE_TIMEOUT=30
    run_probe container-package-state /system/bin/dumpsys package com.android.defcontainer
    if [ "$probe_result" != 0 ] ||
       ! grep -Fq 'Package [com.android.defcontainer]' "$LOGDIR/container-package-state.txt" ||
       ! grep -Eq '^[[:space:]]*codePath=/system/priv-app/DefaultContainerService[[:space:]]*$' "$LOGDIR/container-package-state.txt" ||
       ! grep -Eq 'User 0:.*installed=true.*hidden=false' "$LOGDIR/container-package-state.txt"; then
        echo 'CONTAINER_QUERY_FALLBACK_V104_FIX2'
        PROBE_TIMEOUT=30
        run_probe container-service-path /system/bin/sh -c 'export KINDLE_INPUT_LOW_HEAP=1; export CLASSPATH=/test/pm-stream-v31.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.pm.Pm path com.android.defcontainer'
        if [ "$probe_result" != 0 ] || ! grep -q '^package:/system/priv-app/DefaultContainerService/' "$LOGDIR/container-service-path.txt"; then
            echo 'STOP: container service package not recognized'; exit 1
        fi
    else
        echo CONTAINER_QUERY_COMBINED_V104_FIX2
    fi
    echo 'CONTAINER_SERVICE_PACKAGE_RECOGNIZED'
    read stage_uptime76 stage_idle76 < /proc/uptime
    echo "STAGE_TIME_V76 uptime=$stage_uptime76"
    echo '=== V38 temporary Android memory reduction ==='
    cat /proc/meminfo > "$LOGDIR/memory-before-trim.txt"
    PROBE_TIMEOUT=30
    trim_reuse97=0
    PROBE_TIMEOUT=20
    trim_reuse97=1
    for check_pkg105 in com.android.systemui com.android.launcher3; do
        run_probe "disabled-$check_pkg105-v105" /system/bin/dumpsys package "$check_pkg105"
        if [ "$probe_result" != 0 ] ||
           ! grep -Fq "Package [$check_pkg105]" "$LOGDIR/disabled-$check_pkg105-v105.txt" ||
           ! grep -Eq 'User 0:.*installed=true.*enabled=(2|3)([[:space:]]|$)' "$LOGDIR/disabled-$check_pkg105-v105.txt"; then
            trim_reuse97=0
        fi
    done
    if [ "$trim_reuse97" = 0 ]; then
    run_probe disabled-packages-v97 /system/bin/sh -c 'export KINDLE_INPUT_LOW_HEAP=1; export CLASSPATH=/test/pm-stream-v31.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.pm.Pm list packages -d'
    if [ "$probe_result" = 0 ] &&
       grep -Fxq 'package:com.android.systemui' "$LOGDIR/disabled-packages-v97.txt" &&
       grep -Fxq 'package:com.android.launcher3' "$LOGDIR/disabled-packages-v97.txt"; then
        trim_reuse97=1
    fi
    fi
    optional_running105() (
        for p105 in /proc/[0-9]*; do
            root105=$(readlink -f "$p105/root" 2>/dev/null) || {
                [ ! -d "$p105" ] && continue
                return 0
            }
            [ "$root105" = "$ROOT" ] || continue
            cmd105=$(tr '\000' '\n' < "$p105/cmdline" 2>/dev/null | head -n 1)
            case "$cmd105" in "$1"|"$1":*) return 0;; '') [ ! -d "$p105" ] || return 0;; esac
        done
        return 1
    )
    PROBE_TIMEOUT=30
    if [ "$trim_reuse97" = 1 ]; then
        echo OPTIONAL_PACKAGES_STATE_VERIFIED_V97
        # A disabled package can still have a surviving process from boot.
        for pkg in com.android.systemui com.android.launcher3; do
            if ! optional_running105 "$pkg"; then
                echo "OPTIONAL_PROCESS_ABSENT_V105 package=$pkg"
                continue
            fi
            jj_trim_label=$(echo "$pkg" | tr . _)
            run_probe "stop-$jj_trim_label" /system/bin/sh -c 'export KINDLE_INPUT_LOW_HEAP=1; export CLASSPATH=/system/framework/am.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.am.Am force-stop "$1"' sh "$pkg"
            [ "$probe_result" = 0 ] || exit 1
        done
        cat /proc/meminfo > "$LOGDIR/memory-after-trim-v97.txt"
        echo ISOLATED_HOME_PROCESSES_STOPPED_V97
    else
        echo OPTIONAL_PACKAGES_STATE_REPAIR_V97
    for pkg in com.android.systemui com.android.launcher3; do
        jj_trim_label=$(echo "$pkg" | tr . _)
        run_probe "disable-$jj_trim_label" /system/bin/sh -c 'export KINDLE_INPUT_LOW_HEAP=1; export CLASSPATH=/test/pm-stream-v31.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.pm.Pm disable-user --user 0 "$1"' sh "$pkg"
        if [ "$probe_result" != 0 ] || ! grep -q disabled-user "$LOGDIR/disable-$jj_trim_label.txt"; then
            echo "STOP: could not disable temporary Android package $pkg"
            exit 1
        fi
        run_probe "stop-$jj_trim_label" /system/bin/sh -c 'export KINDLE_INPUT_LOW_HEAP=1; export CLASSPATH=/system/framework/am.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.am.Am force-stop "$1"' sh "$pkg"
        [ "$probe_result" = 0 ] || exit 1
    done
    run_probe trim-cached /system/bin/sh -c 'export KINDLE_INPUT_LOW_HEAP=1; export CLASSPATH=/system/framework/am.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.am.Am kill-all'
    sleep 3
    cat /proc/meminfo > "$LOGDIR/memory-after-trim.txt"
    echo 'TEMP_ANDROID_TRIMMED: SystemUI and Launcher3 disabled; keyboard retained'
        echo disabled > "$ROOT/test/optional-packages-disabled-v62"
    fi
    read stage_uptime76 stage_idle76 < /proc/uptime
    echo "STAGE_TIME_V76 uptime=$stage_uptime76"
    if [ "${KINDLE_AOT_V101:-}" = optimize ]; then
        aot_work101 || exit 1
        echo AOT_OPTIMIZATION_FINISHED_V101
        exit 0
    fi
    echo '=== Restore the persisted system keyboard v67 ==='
    PROBE_TIMEOUT=5
    run_probe keyboard-package-v109 /system/bin/dumpsys package com.android.inputmethod.latin
    if [ "$probe_result" = 0 ] &&
       grep -Fq 'Package [com.android.inputmethod.latin]' "$LOGDIR/keyboard-package-v109.txt" &&
       grep -Eq 'User 0:.*installed=true.*hidden=false.*enabled=1([[:space:]]|$)' "$LOGDIR/keyboard-package-v109.txt"; then
        echo LATIN_PACKAGE_ALREADY_ENABLED_V109
    else
    PROBE_TIMEOUT=30
    run_probe keyboard-enable-v67 /system/bin/sh -c 'export KINDLE_INPUT_LOW_HEAP=1; export CLASSPATH=/test/pm-stream-v31.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.pm.Pm enable --user 0 com.android.inputmethod.latin'
    if [ "$probe_result" != 0 ] || ! grep -q 'new state: enabled' "$LOGDIR/keyboard-enable-v67.txt"; then
        echo 'STOP: could not restore LatinIME'; exit 1
    fi
    fi
    PROBE_TIMEOUT=10
    run_probe keyboard-state-v67 /system/bin/dumpsys input_method
    unset PROBE_TIMEOUT
    echo KEYBOARD_PACKAGE_ENABLED_V67
    if [ ! -f "$ROOT/test/ui-settings-v72.done" ]; then
        PROBE_TIMEOUT=45
        run_probe ui-settings-v72 /system/bin/sh -c '
            export KINDLE_INPUT_LOW_HEAP=1
            export CLASSPATH=/system/framework/settings.jar
            settings72() {
                /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.settings.SettingsCmd "$@"
            }
            settings72 put secure show_ime_with_hard_keyboard 1 || exit 1
            settings72 put global window_animation_scale 0 || exit 1
            settings72 put global transition_animation_scale 0 || exit 1
            settings72 put global animator_duration_scale 0 || exit 1
            settings72 put system time_12_24 24 || exit 1
            allowed72=$(settings72 get secure show_ime_with_hard_keyboard) || exit 1
            echo "SOFT_KEYBOARD_ALLOWED_V72=$allowed72"
            [ "$allowed72" = 1 ]
        '
        if [ "$probe_result" = 0 ] && grep -q '^SOFT_KEYBOARD_ALLOWED_V72=1$' "$LOGDIR/ui-settings-v72.txt"; then
            echo configured > "$ROOT/test/ui-settings-v72.done"
            echo UI_SETTINGS_CONFIGURED_V72
        else
            echo UI_SETTINGS_NOT_CONFIRMED_V72
        fi
        unset PROBE_TIMEOUT
    else
        echo UI_SETTINGS_REUSED_V72
    fi
    PROBE_TIMEOUT=20
    run_probe webview-provider /system/bin/dumpsys webviewupdate
    PROBE_TIMEOUT=10
    run_probe connectivity-v43-check /system/bin/service list
    if [ "$probe_result" != 0 ] || ! grep -q 'connectivity:.*android.net.IConnectivityManager' "$LOGDIR/connectivity-v43-check.txt"; then
        echo 'STOP: offline connectivity service was not registered'
        exit 1
    fi
    echo OFFLINE_CONNECTIVITY_REGISTERED_V43
PROBE_TIMEOUT=45
echo NETWORK_PROBE_USES_GLOBAL_VM_MODE_V69
run_probe network-preflight-v59 /system/bin/sh -c 'export CLASSPATH=/system/framework/kindle-network-probe-v59.jar; exec /system/bin/app_process32 -Xmx32m -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin KindleNetworkProbe59'
unset PROBE_TIMEOUT
[ "$probe_result" = 0 ] && grep -q ANDROID_HOST_NETWORK_V59_OK "$LOGDIR/network-preflight-v59.txt" || { echo 'STOP: Android network preflight failed; return logs'; exit 1; }
echo ANDROID_NETWORK_PREFLIGHT_V59_PASSED
echo JIT_STANDALONE_DIAGNOSTIC_OMITTED_V105
# Runtime JIT settings and library verification remain unchanged.
    read stage_uptime76 stage_idle76 < /proc/uptime
    echo "STAGE_TIME_V76 uptime=$stage_uptime76"
    echo '=== Install real APK into private Android data partition ==='
    zpid=$(cat "$ROOT/test/zygote.pid")
    fsize=$(awk '/^Max file size/ {print $4}' "/proc/$zpid/limits")
    case "$fsize" in ''|*[!0-9]*) echo 'STOP: cannot verify bounded Zygote file limit'; exit 1;; esac
    [ "$fsize" -ge 268435456 ] || { echo "STOP: Zygote file limit too small: $fsize"; exit 1; }
    echo "APK_FILE_LIMIT_READY: Zygote soft limit=$fsize bytes"

    df -Pk "$ROOT" > "$LOGDIR/storage-before-install.txt"
    install_free=$(df -Pk "$ROOT" | awk 'END {print $4}')
    case "$install_free" in ''|*[!0-9]*) echo 'STOP: cannot check image space'; exit 1;; esac
    [ "$install_free" -ge 163840 ] || { echo "STOP: runtime image needs 160 MiB free for Jinjiang; available=$install_free KiB"; exit 1; }
    reuse_apk_v62=0
    if [ "$warm_v62" = 1 ]; then
        PROBE_TIMEOUT=30
        run_probe existing-apk-v62 /system/bin/sh -c 'export KINDLE_INPUT_LOW_HEAP=1; export CLASSPATH=/test/pm-stream-v31.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.pm.Pm path com.jjwxc.reader'
        apk_path_v62=$(sed -n 's/^package://p' "$LOGDIR/existing-apk-v62.txt" | head -n 1)
        if [ -n "$apk_path_v62" ]; then
            case "$apk_path_v62" in /data/app/com.jjwxc.reader-*/base.apk) ;; *) echo 'STOP: unexpected installed APK path'; exit 1;; esac
            printf '%s  %s\n' fdb9a1165b655c37e5ae6a73bea1f502865951a61b8df319352c67821d0ce056 "${apk_path_v62#/}" > "$LOGDIR/apk-expected-v100.sha256" || exit 1
            verify_index100 "$LOGDIR/apk-expected-v100.sha256" "$LOGDIR/apk-integrity-v100.txt" || { echo 'STOP: installed APK differs; retained without reinstall'; exit 1; }
            reuse_apk_v62=1
        fi
    fi
    if [ "$reuse_apk_v62" = 1 ]; then
        echo JINJIANG_APK_AND_DATA_REUSED_V62
        echo USB_APK_INSTALL_CHECK_SKIPPED_V87_FIX5
    else
    [ "$("$BB" sha256sum "$JINJIANG_APK" | awk '{print $1}')" = fdb9a1165b655c37e5ae6a73bea1f502865951a61b8df319352c67821d0ce056 ] || { echo 'STOP: jinjiang APK missing or checksum mismatch'; exit 1; }
    echo 'JJ_APK_VERIFIED: official APK will be streamed from USB storage'
    : > "$LOGDIR/android-process-limits.txt"
    for p in /proc/[0-9]*; do
        [ "$(readlink "$p/root" 2>/dev/null)" = "$ROOT" ] || continue
        echo "=== $p $(cat "$p/comm" 2>/dev/null) ===" >> "$LOGDIR/android-process-limits.txt"
        cat "$p/limits" >> "$LOGDIR/android-process-limits.txt" 2>/dev/null
    done
    PROBE_STDIN="$JINJIANG_APK"
    PROBE_TIMEOUT=300
    echo "PHASE_V52 apk_install uptime=$(cut -d' ' -f1 /proc/uptime)"
    run_probe jinjiang-install /system/bin/sh -c 'export KINDLE_INPUT_LOW_HEAP=1; export KINDLE_APK_STREAM_WRITE=1; export CLASSPATH=/test/pm-stream-v31.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.pm.Pm install -r --user 0 -S 92249242'
    unset PROBE_STDIN
    if [ "$probe_result" != 0 ] || ! grep -q '^Success' "$LOGDIR/jinjiang-install.txt" || ! grep -q 'KINDLE_APK_STREAM_WRITE_V31' "$LOGDIR/jinjiang-install.txt"; then
        echo 'STOP: APK installation or stream-write activation did not complete successfully'
        PROBE_TIMEOUT=15
        run_probe jinjiang-install-state /system/bin/dumpsys package
        run_probe container-running-state /system/bin/dumpsys activity services com.android.defcontainer
        exit 1
    fi
    fi
    PROBE_TIMEOUT=30
    if [ "$reuse_apk_v62" = 1 ]; then
        printf 'package:%s\n' "$apk_path_v62" > "$LOGDIR/jinjiang-installed-path.txt" || exit 1
    else
    run_probe jinjiang-installed-path /system/bin/sh -c 'export KINDLE_INPUT_LOW_HEAP=1; export KINDLE_APK_STREAM_WRITE=1; export CLASSPATH=/test/pm-stream-v31.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.pm.Pm path com.jjwxc.reader'
    if [ "$probe_result" != 0 ] || ! grep -q '^package:/data/app/' "$LOGDIR/jinjiang-installed-path.txt"; then
        echo 'STOP: cannot verify APK installation under /data/app'
        exit 1
    fi
    fi
    echo 'JINJIANG_APK_INSTALLED: PackageManager install and data-app path verified'
    read stage_uptime76 stage_idle76 < /proc/uptime
    echo "STAGE_TIME_V76 uptime=$stage_uptime76"
    echo '=== V41 temporary-root pathname compatibility experiment ==='
    jj_path_zpid=$(cat "$ROOT/test/zygote.pid")
    case "$jj_path_zpid" in ''|*[!0-9]*) exit 1;; esac
    [ "$(readlink -f "/proc/$jj_path_zpid/root")" = "$ROOT" ] || exit 1
    PROBE_TIMEOUT=10
    run_probe jj-path-before /system/bin/sh -c '
        echo "Expected prefix: $1"
        if [ "$1/system/lib/libart.so" -ef /system/lib/libart.so ]; then
            echo PREFIX_RESOLVES_BEFORE
        else
            echo PREFIX_DOES_NOT_RESOLVE_BEFORE
        fi
        echo "=== Zygote maps read INSIDE Android ==="
        while IFS= read -r line; do
            case "$line" in *libart.so*|*framework-boot*) echo "$line";; esac
        done < "/proc/$2/maps"
    ' sh "$ROOT" "$jj_path_zpid"
    [ "$probe_result" = 0 ] || exit 1
    # Only create a self-root alias inside the disposable mounted image.
    case "$ROOT" in /var/tmp/kindle-framework-root.*) ;;
        *) echo 'STOP: unexpected canonical root'; exit 1;;
    esac
    jj_alias_name=${ROOT##*/}
    case "$jj_alias_name" in *[!a-zA-Z0-9._-]*) exit 1;; esac
    for jj_alias_parent in "$ROOT/var" "$ROOT/var/tmp"; do
        [ ! -L "$jj_alias_parent" ] || { echo 'STOP: alias parent is a symlink'; exit 1; }
        mkdir -p "$jj_alias_parent" || exit 1
    done
    if [ -e "$ROOT$ROOT" ] || [ -L "$ROOT$ROOT" ]; then
        [ -L "$ROOT$ROOT" ] && [ "$(readlink "$ROOT$ROOT")" = / ] || {
            echo 'STOP: unexpected persistent root alias'; exit 1;
        }
    fi
    ensure_link_v62 / "$ROOT$ROOT" || exit 1
    run_probe jj-path-after /system/bin/sh -c '
        [ "$1/system/lib/libart.so" -ef /system/lib/libart.so ] || exit 1
        [ "$1/data/app" -ef /data/app ] || exit 1
        echo PREFIX_RESOLVES_TO_SAME_ANDROID_FILES
    ' sh "$ROOT"
    [ "$probe_result" = 0 ] || { echo 'STOP: alias verification failed'; exit 1; }
    echo 'TEMP_ROOT_ALIAS_READY_V41: runtime and APK unchanged'
    PROBE_TIMEOUT=15
    run_probe jinjiang-package /system/bin/dumpsys package com.jjwxc.reader
    PROBE_TIMEOUT=30
    read stage_uptime76 stage_idle76 < /proc/uptime
    echo "STAGE_TIME_V76 uptime=$stage_uptime76"
    echo '=== Disable Jinjiang push service before first launch ==='
    PROBE_TIMEOUT=30
    if component_state100 "$LOGDIR/jinjiang-package.txt" disabledComponents com.example.jinjiangshucheng.push.PushService; then
        echo JINJIANG_PUSH_STATE_REUSED_V100
    else
    run_probe jj-disable-push /system/bin/sh -c 'export KINDLE_INPUT_LOW_HEAP=1; export KINDLE_APK_STREAM_WRITE=1; export CLASSPATH=/test/pm-stream-v31.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.pm.Pm disable --user 0 com.jjwxc.reader/com.example.jinjiangshucheng.push.PushService'
    unset PROBE_TIMEOUT
    if [ "$probe_result" != 0 ] || ! grep -q 'new state: disabled' "$LOGDIR/jj-disable-push.txt"; then
        echo 'STOP: unable to disable Jinjiang push service'
        cat "$LOGDIR/jj-disable-push.txt"
        exit 1
    fi
    fi
    echo JINJIANG_PUSH_DISABLED_V46
    cat /proc/meminfo > "$LOGDIR/memory-before-jinjiang-v46.txt"
    cat /proc/swaps > "$LOGDIR/swaps-before-jinjiang-v46.txt"
    read stage_uptime76 stage_idle76 < /proc/uptime
    echo "STAGE_TIME_V76 uptime=$stage_uptime76"
    ui_prepare111 || { echo STOP_UI_PREPARE_V111; exit 1; }
    echo '=== Prepare persistent input before starting Jinjiang ==='
    echo "PHASE_V64 input_prewarm uptime=$(cut -d' ' -f1 /proc/uptime)"
    "$BB" mkfifo "$TOUCHDIR/events.fifo" || exit 1
    exec 9<>"$TOUCHDIR/events.fifo" || exit 1
    touch_fifo_open=1
    KINDLE_CHROOT_ROOT="$ROOT" /usr/bin/setsid "$BB" chroot "$ROOT" /system/bin/sh -c 'export KINDLE_INPUT_LOW_HEAP=1; export CLASSPATH=/test/kindle-input-relay-v29.jar:/system/framework/input.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat -Xint -Xusejit:false /system/bin KindleInputRelay' < "$TOUCHDIR/events.fifo" 9>&- > "$LOGDIR/touch-relay.txt" 2>&1 &
    touch_relay=$!
    touch_ready=0
    touch_wait=0
    while [ "$touch_wait" -lt 60 ]; do
        if grep -q KINDLE_TOUCH_RELAY_READY_V29 "$LOGDIR/touch-relay.txt"; then
            touch_ready=1
            break
        fi
        kill -0 "$touch_relay" 2>/dev/null || break
        sleep 1
        touch_wait=$((touch_wait + 1))
        if [ "$touch_wait" = 10 ] || [ "$touch_wait" = 30 ]; then
            {
                echo "relay_pid=$touch_relay wait=$touch_wait"
                readlink "/proc/$touch_relay/root"
                cat "/proc/$touch_relay/status" "/proc/$touch_relay/wchan"
                for relay_task_v64 in /proc/"$touch_relay"/task/*; do
                    echo "=== $relay_task_v64 ==="
                    cat "$relay_task_v64/comm" "$relay_task_v64/wchan" "$relay_task_v64/stack" 2>/dev/null
                done
            } > "$LOGDIR/relay-startup-v64-$touch_wait.txt" 2>&1
        fi
    done
    [ "$touch_ready" = 1 ] || { echo 'STOP: persistent input relay failed to start'; exit 1; }
    echo 'RELAY_READY: no automatic BACK or consent input for third-party app'
    /usr/bin/setsid "$BB" sh -c '("$1" --run-300-seconds; echo "$?" > "$5") | (set -f; control=$6; close_gesture() {
    [ "$#" = 6 ] && [ "$1" = swipe ] || return 1
    case "$2:$3:$4:$5" in *[!0-9:]*) return 1;; esac
    [ "$2" -ge 540 ] && [ "$4" -ge 540 ] && [ "$3" -le 80 ] && [ "$5" -ge 740 ]
}
while IFS= read -r event; do
    if close_gesture $event; then
        : > "$control/stop"
    else
        printf "%s\n" "$event" || exit 1
    fi
done) | "$2" tee -a "$3" > "$4"; read reader_rc < "$5"; exit "$reader_rc"' sh "$TOUCHDIR/kindle_touch_bridge-v30" "$BB" "$LOGDIR/touch-events-v62.txt" "$TOUCHDIR/events.fifo" "$TOUCHDIR/reader-status-v62" "$control112" 9>&- 2>> "$LOGDIR/touch-reader.txt" &
    touch_reader=$!
    (
        sleep 305
        kill -TERM -"$touch_reader" 2>/dev/null
        sleep 1
        kill -KILL -"$touch_reader" 2>/dev/null
    ) 9>&- &
    touch_guard=$!
    sleep 1
    if ! grep -q TOUCH_GRABBED_V30 "$LOGDIR/touch-reader.txt"; then
        echo 'STOP: touch device not acquired; see touch-reader.txt'
        exit 1
    fi
    echo 'PHYSICAL_TOUCH_READY: triple tap top right to hide; swipe down the full right edge to close'
    [ -f "$LOGDIR/touch-events-v62.txt" ] || : > "$LOGDIR/touch-events-v62.txt"
    "$FBINKDIR/controls-v78" "$LOGDIR/touch-events-v62.txt" "$$" "$LOGDIR/settings-request-v78" 9>&- > "$LOGDIR/exit-watcher-v66.txt" 2>&1 &
    exit_watcher_v66=$!
    sleep 1
    kill -0 "$exit_watcher_v66" 2>/dev/null || { echo 'STOP: independent exit watcher failed'; exit 1; }
# Read one host Battery capacity node; never write host sysfs or power services.
battery_last_v72=
mirror_battery_v72() {
    battery_node_v72=
    for supply_v72 in /sys/class/power_supply/*; do
        [ -r "$supply_v72/type" ] && [ -r "$supply_v72/capacity" ] || continue
        read -r battery_type_v72 < "$supply_v72/type"
        [ "$battery_type_v72" = Battery ] || continue
        battery_node_v72="$supply_v72/capacity"
        break
    done
    if [ -z "$battery_node_v72" ]; then
        echo HOST_BATTERY_NODE_UNAVAILABLE_V72
        return 0
    fi
    read -r battery_level_v72 < "$battery_node_v72" || return 0
    case "$battery_level_v72" in ''|*[!0-9]*) echo HOST_BATTERY_INVALID_V72; return 0;; esac
    if [ "${#battery_level_v72}" -gt 3 ] || [ "$battery_level_v72" -lt 1 ] || [ "$battery_level_v72" -gt 100 ]; then
        echo HOST_BATTERY_OUT_OF_RANGE_V72
        return 0
    fi
    [ "$battery_level_v72" != "$battery_last_v72" ] || return 0
    {
        echo "source=$battery_node_v72"
        echo "capacity=$battery_level_v72"
        date -u
    } > "$LOGDIR/host-battery-v72.txt"
    PROBE_TIMEOUT=4
    run_probe battery-level-set-v72 /system/bin/dumpsys battery set level "$battery_level_v72"
    if [ "$probe_result" = 0 ]; then
        run_probe battery-level-state-v72 /system/bin/dumpsys battery
        if [ "$probe_result" = 0 ] && grep -Eq "^[[:space:]]*level: $battery_level_v72$" "$LOGDIR/battery-level-state-v72.txt"; then
            battery_last_v72=$battery_level_v72
            echo "HOST_BATTERY_LEVEL_MIRRORED_V72 level=$battery_level_v72"
        else
            echo BATTERY_LEVEL_NOT_CONFIRMED_V72
        fi
    else
        echo BATTERY_LEVEL_UPDATE_FAILED_V72
    fi
    unset PROBE_TIMEOUT
    return 0
}
    mirror_battery_v72
    next_battery_v72=60
    PROBE_TIMEOUT=12
    header_enabled_v73=0
    run_probe viewport-reset-v76 /system/bin/sh -c 'export KINDLE_INPUT_LOW_HEAP=1; export CLASSPATH=/test/wm-v73.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.wm.Wm overscan "$1"' sh 0,0,0,0
    if [ "$probe_result" = 0 ] && [ ! -f /mnt/us/kindle-system-test/no-header-v74 ]; then
        run_probe viewport-state-v76 /system/bin/dumpsys window policy
        if [ "$probe_result" = 0 ] && grep -Eq 'mUnrestrictedScreen=\(0,[[:space:]]*0\)[[:space:]]+618x824' "$LOGDIR/viewport-state-v76.txt"; then
            run_probe input-support-v76 /system/bin/dumpsys input
            if [ "$probe_result" = 0 ] && grep -q KINDLE_STATUS_TOUCH_MAPPING_V76 "$LOGDIR/input-support-v76.txt"; then
                echo enabled > "$ROOT/system/framework/kindle-status-transform-v76.on" || exit 1
                chmod 644 "$ROOT/system/framework/kindle-status-transform-v76.on" || exit 1
                header_enabled_v73=1
                echo RESCALED_HEADER_READY_V76
            fi
        fi
    fi
    if [ "$header_enabled_v73" != 1 ]; then
        rm -f "$ROOT/system/framework/kindle-status-transform-v76.on"
        echo HEADER_AND_MAPPING_DISABLED_V76
    fi
    unset PROBE_TIMEOUT
    # Optional Chinese IME. The existing LatinIME remains installed for recovery.
    ime74() {
        run_probe "$1" /system/bin/sh -c '
            export KINDLE_INPUT_LOW_HEAP=1
            export CLASSPATH=/test/ime-v74.jar
            shift
            exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.ime.Ime "$@"
        ' sh "$@"
    }
    pm75() {
        run_probe "$1" /system/bin/sh -c '
            export KINDLE_INPUT_LOW_HEAP=1
            export PATH=/system/bin:/system/xbin
            export CLASSPATH=/system/framework/pm.jar
            shift
            exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.pm.Pm "$@"
        ' sh "$@"
    }
    settings80() {
        run_probe "$1" /system/bin/sh -c '
            export KINDLE_INPUT_LOW_HEAP=1
            export CLASSPATH=/system/framework/settings.jar
            shift
            exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat -Xint -Xusejit:false /system/bin com.android.commands.settings.SettingsCmd "$@"
        ' sh "$@"
    }
    confirm_chinese_default80() {
        PROBE_TIMEOUT=12
        settings80 "$1" get secure default_input_method
        grep -Fxq "$chinese_id77" "$LOGDIR/$1.txt"
    }
    prepare_chinese74() {
        pm75 chinese-path-v74 path com.osfans.trime
        installed74=$(sed -n 's/^package://p' "$LOGDIR/chinese-path-v74.txt" | head -n 1 | tr -d '\r')
        reuse74=0
        case "$installed74" in
            /data/app/com.osfans.trime-*/base.apk)
                if [ -f "$ROOT$installed74" ] && [ "$("$BB" sha256sum "$ROOT$installed74" | awk '{print $1}')" = df616f707ea6517d6fc1891575200ccd550b699df5ffd7937b70980bd0ac936e ]; then reuse74=1; fi;;
        esac
        if [ "$reuse74" != 1 ]; then
            PROBE_TIMEOUT=180
            pm75 chinese-install-v74 install -r --abi armeabi-v7a /test/Trime-kindle-v74.apk
            [ "$probe_result" = 0 ] && grep -q '^Success' "$LOGDIR/chinese-install-v74.txt" || return 1
            echo CHINESE_IME_FIRST_INSTALL_V74
        else
            echo CHINESE_IME_APK_REUSED_V74
            if [ ! -L "$ROOT/data/ime-rime-v74" ] &&
               [ -f "$ROOT/data/ime-rime-v74/.kindle-ime-owner-v74" ] &&
               grep -Eq '^[[:space:]]*mCurMethodId=com[.]osfans[.]trime/(com[.]osfans[.]trime)?[.]TrimeImeService[[:space:]]*$' "$LOGDIR/keyboard-state-v67.txt"; then
                echo CHINESE_IME_ACTIVE_REUSED_V87
                return 0
            fi
        fi
        PROBE_TIMEOUT=30
        run_probe chinese-package-v74 /system/bin/dumpsys package com.osfans.trime
        [ "$probe_result" = 0 ] || return 1
        uid74=$(sed -n 's/^[[:space:]]*userId=\([0-9][0-9]*\).*$/\1/p' "$LOGDIR/chinese-package-v74.txt" | head -n 1)
        case "$uid74" in ''|*[!0-9]*) return 1;; esac
        [ "$uid74" -ge 10000 ] && [ "$uid74" -lt 100000 ] || return 1
        # This is a new dedicated directory, never Jinjiang's data directory.
        rime74="$ROOT/data/ime-rime-v74"
        [ ! -L "$rime74" ] || return 1
        if [ -e "$rime74" ] && [ ! -f "$rime74/.kindle-ime-owner-v74" ]; then
            echo CHINESE_IME_UNOWNED_DIRECTORY_V74
            return 1
        fi
        mkdir -p "$rime74" || return 1
        echo kindle-ime-v74 > "$rime74/.kindle-ime-owner-v74" || return 1
        seed_rime82 || return 1
        if [ ! -s "$rime74/default.custom.yaml" ]; then
            printf 'patch:\n  schema_list:\n    - schema: kindle_pinyin26\n    - schema: kindle_pinyin9\n' > "$rime74/default.custom.yaml" || return 1
            chown "$uid74:$uid74" "$rime74/default.custom.yaml" || return 1
            chmod 644 "$rime74/default.custom.yaml" || return 1
        fi
        # Android may select credential- or device-protected preferences.
        # Seed absent preference files only; keep all later user customizations.
        found74=0
        for appdata74 in "$ROOT/data/user/0/com.osfans.trime" "$ROOT/data/data/com.osfans.trime" "$ROOT/data/user_de/0/com.osfans.trime"; do
            [ -d "$appdata74" ] || continue
            prefs74="$appdata74/shared_prefs"
            mkdir -p "$prefs74" || return 1
            chown "$uid74:$uid74" "$prefs74" || return 1
            chmod 700 "$prefs74" || return 1
            for name74 in com.osfans.trime_preferences shared_prefs; do
                if [ ! -e "$prefs74/$name74.xml" ]; then
                    cp /mnt/us/kindle-system-test/trime-prefs-v74.xml "$prefs74/$name74.xml" || return 1
                    chown "$uid74:$uid74" "$prefs74/$name74.xml" || return 1
                    chmod 600 "$prefs74/$name74.xml" || return 1
                fi
            done
            found74=1
        done
        [ "$found74" = 1 ] || return 1
        PROBE_TIMEOUT=15
        echo CHINESE_INIT_BY_IME_SERVICE_V79
        # Do not infer success from ime's exit code: the Android 7 CLI catches
        # some errors and exits zero. First wait for an actual registered ID.
        pm75 chinese-component-enable-v77 enable --user 0 com.osfans.trime/.TrimeImeService
        chinese_id77=
        attempt77=1
        read ime_uptime77 ime_idle77 < /proc/uptime
        ime_deadline77=$(( ${ime_uptime77%%.*} + 25 ))
        while [ "$attempt77" -le 5 ]; do
            read ime_uptime77 ime_idle77 < /proc/uptime
            ime_remaining77=$(( ime_deadline77 - ${ime_uptime77%%.*} ))
            [ "$ime_remaining77" -gt 0 ] || break
            PROBE_TIMEOUT=8
            if [ "$ime_remaining77" -lt 8 ]; then PROBE_TIMEOUT=$ime_remaining77; fi
            ime74 "chinese-list-v77-$attempt77" list -a -s
            if [ -s "$LOGDIR/chinese-list-v77-$attempt77.txt" ]; then
                while IFS= read -r line77; do
                    case "$line77" in
                        com.osfans.trime/.TrimeImeService|com.osfans.trime/com.osfans.trime.TrimeImeService)
                            chinese_id77=$line77; break;;
                    esac
                done < "$LOGDIR/chinese-list-v77-$attempt77.txt"
            fi
            [ -z "$chinese_id77" ] || break
            attempt77=$((attempt77 + 1))
            if [ "$attempt77" -le 5 ]; then sleep 1; fi
        done
        PROBE_TIMEOUT=15
        if [ -z "$chinese_id77" ]; then
            echo CHINESE_IME_NOT_REGISTERED_V77
            run_probe chinese-user-state-v77 /system/bin/dumpsys user
            return 1
        fi
        ime74 chinese-enable-v77 enable "$chinese_id77"
        if [ "$probe_result" != 0 ] || ! grep -Eq 'now enabled|already enabled' "$LOGDIR/chinese-enable-v77.txt"; then
            echo CHINESE_IME_ENABLE_NOT_CONFIRMED_V77
            return 1
        fi
        # Confirm the saved Android default independently of the CLI exit code.
        if ! confirm_chinese_default80 chinese-default-before-v80; then
            PROBE_TIMEOUT=20
            ime74 chinese-select-v80 set "$chinese_id77"
            echo "CHINESE_SELECT_COMMAND_V80 exit=$probe_result"
            if ! confirm_chinese_default80 chinese-default-after-ime-v80; then
                # Trime has been verified registered and enabled above. Use the
                # secure setting if the standard IME command did not take effect.
                PROBE_TIMEOUT=12
                settings80 chinese-select-secure-v80 put secure default_input_method "$chinese_id77"
                if ! confirm_chinese_default80 chinese-default-after-secure-v80; then
                    echo CHINESE_IME_DEFAULT_NOT_CONFIRMED_V80
                    return 1
                fi
            fi
        fi
        echo "CHINESE_IME_SELECTED_V80 id=$chinese_id77"
    }
    PROBE_TIMEOUT=30
    if [ -f /mnt/us/kindle-system-test/english-keyboard-v74 ]; then
        ime74 latin-fallback-v74 set com.android.inputmethod.latin/.LatinIME
        echo CHINESE_IME_DISABLED_BY_USER_V74
    elif ! prepare_chinese74; then
        echo CHINESE_IME_SETUP_NOT_CONFIRMED_V80
    fi
    unset PROBE_TIMEOUT
    echo ROUTINE_THREAD_OBSERVER_DISABLED_V72
    # Recover component state left by the v94 experiment before launching the app.
    PROBE_TIMEOUT=20
    if component_state100 "$LOGDIR/jinjiang-package.txt" enabledComponents org.acra.sender.JobSenderService; then
        echo REQUIRED_REPORT_SERVICE_STATE_REUSED_V100
    else
    pm75 acra-enable-v95 enable --user 0 com.jjwxc.reader/org.acra.sender.JobSenderService
    if [ "$probe_result" != 0 ] ||
       ! grep -Eq 'new state: enabled[[:space:]]*$' "$LOGDIR/acra-enable-v95.txt"; then
        echo 'STOP: required Jinjiang report service could not be enabled'
        exit 1
    fi
    fi
    PROBE_TIMEOUT=5
    run_probe acra-package-v95 /system/bin/dumpsys package com.jjwxc.reader
    unset PROBE_TIMEOUT
    echo JINJIANG_REQUIRED_SERVICE_ENABLED_V95
    io_snapshot96() (
        sample96=$1
        echo "uptime=$(cut -d' ' -f1 /proc/uptime)"
        echo '=== block device counters ==='
        cat /proc/diskstats
        echo '=== memory and swap counters ==='
        cat /proc/meminfo /proc/vmstat
        for proc96 in /proc/[0-9]*; do
            IFS= read -r name96 < "$proc96/comm" 2>/dev/null || continue
            case "$name96" in *jjwxc*|*reader*|*acra*) ;; *) continue;; esac
            [ "$(readlink -f "$proc96/root" 2>/dev/null)" = "$ROOT" ] || continue
            echo "=== process=${proc96##*/} name=$name96 ==="
            cat "$proc96/io" "$proc96/status" "$proc96/wchan" "$proc96/stack" 2>/dev/null
        done
        exit 0
    ) > "$LOGDIR/startup-io-v96-$1.txt" 2>&1
    io_snapshot96 before-app
    # Service registration is not user readiness. Do not launch CE applications
    # while Android user 0 is still booting/locked.
    echo "USER_READY_WAIT_BEGIN_V106 uptime=$(cut -d' ' -f1 /proc/uptime)"
    ready106=0
    read begin106 unused106 < /proc/uptime
    begin106=${begin106%%.*}
    PROBE_TIMEOUT=5
    run_probe boot-window-before-v106 /system/bin/dumpsys window
    while :; do
        run_probe boot-user-v106 /system/bin/dumpsys user
        cat "$LOGDIR/boot-user-v106.txt" >> "$LOGDIR/boot-user-history-v106.txt"
        if [ "$probe_result" = 0 ] &&
           grep -Eq 'Started users state:.*[\{,][[:space:]]*0=3([,}]|[[:space:]])' "$LOGDIR/boot-user-v106.txt"; then
            ready106=1
            break
        fi
        read now106 unused106 < /proc/uptime
        now106=${now106%%.*}
        [ "$((now106 - begin106))" -lt 90 ] || break
        sleep 1
    done
    unset PROBE_TIMEOUT
    if [ "$ready106" != 1 ]; then
        echo 'STOP: Android user 0 did not reach unlocked state; leaving app data intact'
        exit 1
    fi
    echo "USER_READY_CONFIRMED_V106 uptime=$(cut -d' ' -f1 /proc/uptime)"
    echo "PHASE_V52 app_launch uptime=$(cut -d' ' -f1 /proc/uptime)"
    PROBE_TIMEOUT=60
    run_probe jinjiang-start /system/bin/sh -c 'export KINDLE_INPUT_LOW_HEAP=1; export CLASSPATH=/system/framework/am.jar; exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.am.Am start -n com.jjwxc.reader/com.jjwxc.reader.AppPrivacyActivity'
    unset PROBE_TIMEOUT
    if [ "$probe_result" != 0 ] || grep -Eq '^[[:space:]]*(Error:|Error type|Exception|SecurityException)' "$LOGDIR/jinjiang-start.txt"; then
        cat "$LOGDIR/jinjiang-start.txt"
        echo 'STOP: jinjiang launch command failed'
        PROBE_TIMEOUT=10
        run_probe launch-failure-package-v104-fix2 /system/bin/dumpsys package com.jjwxc.reader
        run_probe launch-failure-users-v104-fix2 /system/bin/dumpsys user
        run_probe launch-failure-activity-v104-fix2 /system/bin/dumpsys activity activities
        exit 1
    fi
    jinjiang_ready=0
    jinjiang_wait=0
    window_scope87=windows
    PROBE_TIMEOUT=10
    while [ "$jinjiang_wait" -lt 24 ]; do
        sleep 5
        cat /proc/meminfo > "$LOGDIR/jj-start-memory-$jinjiang_wait.txt"
        case "$jinjiang_wait" in 0|6|12|18) io_snapshot96 "$jinjiang_wait";; esac
        if [ "$window_scope87" = windows ]; then
            run_probe jinjiang-window /system/bin/dumpsys window windows
            grep -q 'mCurrentFocus=' "$LOGDIR/jinjiang-window.txt" || window_scope87=full
        fi
        if [ "$window_scope87" = full ]; then
            run_probe jinjiang-window /system/bin/dumpsys window
        fi
        if grep -q 'mCurrentFocus=.*com.jjwxc.reader' "$LOGDIR/jinjiang-window.txt"; then
            jinjiang_ready=1
            break
        fi
        jinjiang_wait=$((jinjiang_wait + 1))
    done
    unset PROBE_TIMEOUT
    if [ "$jinjiang_ready" != 1 ]; then
        PROBE_TIMEOUT=20
        run_probe jinjiang-startup-activity /system/bin/dumpsys activity
        run_probe jinjiang-startup-memory /system/bin/dumpsys meminfo com.jjwxc.reader
        cp "$ROOT/test/kindle-fb/frame.ppm" "$LOGDIR/jinjiang-startup-frame.ppm" 2>/dev/null
        echo 'STOP: Jinjiang did not gain window focus; inspect Android crash log'
        exit 1
    fi
    echo "PHASE_V52 app_focused uptime=$(cut -d' ' -f1 /proc/uptime)"
    io_snapshot96 focused
    echo 'JINJIANG_ACTIVITY_FOCUSED: beginning physical app interaction'
    read stage_uptime76 stage_idle76 < /proc/uptime
    echo "STAGE_TIME_V76 uptime=$stage_uptime76"
    echo '=== Start bounded physical touch and live display test ==='
    cp "$ROOT/test/kindle-fb/frame.ppm" "$LOGDIR/before-touch.ppm" || exit 1
    echo 'INPUT_PREWARMED_V64: physical touch starts after the app is focused'
    touch_start=$(awk '{print int($1)}' /proc/uptime)
    touch_tick=0
    main_missing_v63=0
    next_main_v67=0
    next_binder_v67=0
    next_snapshot_v67=0
    binder_failed_v63=0
    [ -x "$KINDLE_NICE_HELPER_V63" ] || { echo 'STOP: priority/health helper missing'; exit 1; }
    last_crc=
    last_status_key_v73=
    unstable_frames_v67=0
    live_failed=0
    warm_ready111=1
    while :; do
        if [ -f "$control112/stop" ]; then
            echo MANUAL_READING_EXIT_V114
            exit 0
        fi
        if [ "$warm_request111" = 1 ]; then
            warm_return111 || { echo STOP_WARM_RETURN_V111; exit 1; }
        fi
        if ! kill -0 "$touch_reader" 2>/dev/null; then
            wait "$touch_reader"
            restart_rc_v62=$?
            [ "$restart_rc_v62" = 0 ] || { live_failed=1; break; }
            kill "$touch_guard" 2>/dev/null
            wait "$touch_guard" 2>/dev/null
            /usr/bin/setsid "$BB" sh -c '("$1" --run-300-seconds; echo "$?" > "$5") | (set -f; control=$6; close_gesture() {
    [ "$#" = 6 ] && [ "$1" = swipe ] || return 1
    case "$2:$3:$4:$5" in *[!0-9:]*) return 1;; esac
    [ "$2" -ge 540 ] && [ "$4" -ge 540 ] && [ "$3" -le 80 ] && [ "$5" -ge 740 ]
}
while IFS= read -r event; do
    if close_gesture $event; then
        : > "$control/stop"
    else
        printf "%s\n" "$event" || exit 1
    fi
done) | "$2" tee -a "$3" > "$4"; read reader_rc < "$5"; exit "$reader_rc"' sh "$TOUCHDIR/kindle_touch_bridge-v30" "$BB" "$LOGDIR/touch-events-v62.txt" "$TOUCHDIR/events.fifo" "$TOUCHDIR/reader-status-v62" "$control112" 9>&- 2>> "$LOGDIR/touch-reader.txt" &
            touch_reader=$!
            (
                sleep 305
                kill -TERM -"$touch_reader" 2>/dev/null
                sleep 1
                kill -KILL -"$touch_reader" 2>/dev/null
            ) 9>&- &
            touch_guard=$!
            sleep 1
            kill -0 "$touch_reader" 2>/dev/null || { live_failed=1; break; }
            echo INPUT_READER_RESTARTED_V62
        fi
        if ! kill -0 "$touch_relay" 2>/dev/null; then
            echo 'STOP: input relay exited during touch test'
            live_failed=1
            break
        fi
        now=$(awk '{print int($1)}' /proc/uptime)
        elapsed=$((now - touch_start))
        if [ "$elapsed" -ge "$next_main_v67" ]; then
            next_main_v67=$((elapsed + 10))
            if "$KINDLE_NICE_HELPER_V63" --alive "$ROOT" > "$LOGDIR/main-health-v63.txt" 2>&1; then
                main_missing_v63=0
            else
                main_missing_v63=$((main_missing_v63 + 1))
                echo "MAIN_PROCESS_MISSING_V63 consecutive=$main_missing_v63"
            fi
            if [ "$main_missing_v63" -ge 3 ]; then
                echo 'STOP: Jinjiang main process exited; ending session and retaining data'
                live_failed=1
                break
            fi
        fi
        if [ "$elapsed" -ge "$next_battery_v72" ]; then
            next_battery_v72=$((elapsed + 60))
            mirror_battery_v72
        fi
        if [ "$elapsed" -ge "$next_binder_v67" ]; then
            status_minute_v73=$(date -u +%Y%m%d%H%M)
            next_binder_v67=$((elapsed + 30))
            PROBE_TIMEOUT=8
            run_probe binder-health-v63 /system/bin/service check activity
            unset PROBE_TIMEOUT
            if [ "$probe_result" = 0 ] && grep -q '^Service activity: found' "$LOGDIR/binder-health-v63.txt"; then
                binder_failed_v63=0
            else
                binder_failed_v63=$((binder_failed_v63 + 1))
                echo "BINDER_HEALTH_FAILED_V63 consecutive=$binder_failed_v63"
            fi
            if [ "$binder_failed_v63" -ge 2 ]; then
                echo 'STOP: Android service unresponsive; ending session and retaining data'
                live_failed=1
                break
            fi
        fi
        if [ -f "$LOGDIR/settings-request-v78" ]; then
            rm -f "$LOGDIR/settings-request-v78"
            PROBE_TIMEOUT=8
            run_probe settings-open-v78 /system/bin/sh -c '
                export KINDLE_INPUT_LOW_HEAP=1
                export CLASSPATH=/system/framework/am.jar
                exec /system/bin/app_process32 -Ximage:/data/framework-boot/boot.art -Xnorelocate -Xnoimage-dex2oat -Xnodex2oat /system/bin com.android.commands.am.Am start --user 0 --activity-single-top -n com.osfans.trime/.KindleControlActivity78
            '
            unset PROBE_TIMEOUT
        fi
        settings_file78="$ROOT/data/user_de/0/com.osfans.trime/files/reading-settings-v78.txt"
        if [ ! -f "$settings_file78" ]; then settings_file78="$ROOT/data/user/0/com.osfans.trime/files/reading-settings-v78.txt"; fi
        config_key78=defaults
        if [ -f "$settings_file78" ]; then config_key78=$(cksum < "$settings_file78"); fi
        cp "$ROOT/test/kindle-fb/frame.ppm" "$TOUCHDIR/frame.ppm" || { live_failed=1; break; }
        crc=$(cksum < "$TOUCHDIR/frame.ppm")
        status_key_v73="$status_minute_v73:${battery_last_v72:-unknown}:$config_key78"
        if [ "$crc" != "$last_crc" ] || { [ "$header_enabled_v73" = 1 ] && [ "$status_key_v73" != "$last_status_key_v73" ]; }; then
            # Avoid sending short-lived page-turn animation frames to e-ink.
            "$FBINKDIR/delay-v70" 60 || { live_failed=1; break; }
            stable_crc_v67=$(cksum < "$ROOT/test/kindle-fb/frame.ppm")
            if [ "$crc" != "$stable_crc_v67" ]; then
                unstable_frames_v67=$((unstable_frames_v67 + 1))
                if [ "$unstable_frames_v67" -lt 4 ]; then "$FBINKDIR/delay-v70" 100 || { live_failed=1; break; }; continue; fi
            fi
            unstable_frames_v67=0
            present_desktop "$TOUCHDIR/frame.ppm" touch-live || { live_failed=1; break; }
            if [ "$warm_request111" = 1 ]; then continue; fi
            last_crc=$crc
            last_status_key_v73=$status_key_v73
            echo "LIVE_FRAME tick=$touch_tick elapsed=$elapsed crc=$crc"
        fi
        if [ "$elapsed" -ge "$next_snapshot_v67" ]; then
            next_snapshot_v67=$((elapsed + 120))
            cp "$TOUCHDIR/frame.ppm" "$LOGDIR/latest-touch-frame.ppm"
        fi
        touch_tick=$((touch_tick + 1))
        "$FBINKDIR/delay-v70" 100 || { live_failed=1; break; }
    done
    kill "$exit_watcher_v66" 2>/dev/null
    wait "$exit_watcher_v66" 2>/dev/null
    exit_watcher_v66=
    kill -TERM -"$touch_reader" 2>/dev/null
    wait "$touch_reader"
    reader_result=0
    touch_reader=
    kill "$touch_guard" 2>/dev/null
    wait "$touch_guard" 2>/dev/null
    touch_guard=
    exec 9>&-
    touch_fifo_open=0
    relay_wait=0
    while kill -0 "$touch_relay" 2>/dev/null && [ "$relay_wait" -lt 5 ]; do
        sleep 1
        relay_wait=$((relay_wait + 1))
    done
    if kill -0 "$touch_relay" 2>/dev/null; then
        echo 'STOP: relay did not drain before timeout'
        kill -KILL -"$touch_relay" 2>/dev/null
        live_failed=1
    fi
    wait "$touch_relay"
    relay_result=$?
    touch_relay=
    cp "$ROOT/test/kindle-fb/frame.ppm" "$LOGDIR/touch-final.ppm"
    cat /proc/meminfo > "$LOGDIR/touch-memory-after.txt"
    if [ "$live_failed" = 0 ]; then
        PROBE_TIMEOUT=15
        run_probe touch-input-after /system/bin/dumpsys input
        run_probe touch-window-after /system/bin/dumpsys window
        unset PROBE_TIMEOUT
    else
        echo HEALTH_FAILURE_SKIP_BLOCKING_DIAGNOSTICS_V63
    fi
    echo "TOUCH_PHASE_COMPLETE reader=$reader_result relay=$relay_result display_failed=$live_failed"
    [ "$reader_result" = 0 ] && [ "$relay_result" = 0 ] && [ "$live_failed" = 0 ] || exit 1
    echo 'TOUCH_TEST_FINISHED: verify gesture/relay logs and user observations'
    PROBE_TIMEOUT=15
    run_probe user-after-home /system/bin/dumpsys user
    run_probe activity-after-home /system/bin/dumpsys activity
    run_probe window-after-home /system/bin/dumpsys window
    run_probe jinjiang-package-after /system/bin/dumpsys package com.jjwxc.reader
    unset PROBE_TIMEOUT

    exit 0
fi
echo 'INTEGRATION_INCOMPLETE: return logs for startup diagnosis'
exit 1
