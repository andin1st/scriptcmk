#!/usr/bin/env bash
# fan_health.sh - fan speed and thermal health check
#
# Detects fan RPM from sysfs hwmon (fan*_input) or the sensors(1) tool.
# On HP laptops like the 14s-cf series the fan RPM is usually NOT exposed
# to Linux (the EC controls the fan, hwmon only shows pwm1_enable=2), so in
# that case only a thermal health report is produced.
#
# Usage:
#   fan_health.sh              one-shot report
#   fan_health.sh --watch      continuous monitoring
#   fan_health.sh -w 75 -c 95  custom warn/crit CPU thresholds (Celsius)

set -u

WARN=70
CRIT=88
WATCH=0
INTERVAL=3

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

to_c() {
    # millidegrees -> integer degrees
    awk -v t="$1" 'BEGIN{ printf "%d", t/1000 }'
}

highest_cpu_temp() {
    local best=0 cur t
    local d
    for d in /sys/class/hwmon/hwmon*; do
        [ -f "$d/name" ] || continue
        case "$(cat "$d/name")" in
            coretemp|x86_pkg_temp)
                for f in "$d"/temp*_input; do
                    [ -f "$f" ] || continue
                    cur=$(cat "$f" 2>/dev/null)
                    [ -n "${cur:-}" ] || continue
                    if [ "$cur" -gt "$best" ]; then best=$cur; fi
                done
                ;;
        esac
    done
    printf '%s' "$best"
}

fan_rpms() {
    local name d f n v
    for d in /sys/class/hwmon/hwmon*; do
        [ -f "$d/name" ] || continue
        name=$(cat "$d/name")
        for f in "$d"/fan*_input; do
            [ -f "$f" ] || continue
            v=$(cat "$f" 2>/dev/null)
            [ -n "$v" ] || continue
            echo "$name:${f##*/}:$v"
        done
    done
}

fan_rpms_sensors() {
    command -v sensors >/dev/null 2>&1 || return 0
    sensors -A 2>/dev/null | sed -n 's/^\([^:]*\): *\([0-9][0-9 ]*\) RPM.*/\1:\2/p' \
        | while IFS=: read -r chip rpm; do echo "sensors:$chip:$rpm"; done
}

thermal_from_sensors() {
    command -v sensors >/dev/null 2>&1 || return 0
    sensors -A 2>/dev/null | rg -i 'Package id|Tctl|Tdie' | sed -n 's/^.*+\([0-9.]*\)°C.*/\1/p' \
        | sort -n | tail -1 | awk '{printf "%d", $0+0.5}'
}

ec_fan_rpm() {
    # EC-backed RPM read: requires root, ec_sys loaded and debugfs mounted.
    [ "$(id -u)" -eq 0 ] || return 1
    [ -d /sys/kernel/debug/ec/ec0 ] || return 1
    # HP laptops typically expose fan RPM at EC RAM 0x44..0x47.
    # RPM usually = (lo | hi<<8) or (hi<<8 | lo); try both, keep largest.
    local v
    v=$(cat /sys/kernel/debug/ec/ec0/io 2>/dev/null) || return 1
    echo "$v" | awk '
        BEGIN { FS=" " }
        { for (i=1; i<=NF; i++) x[i-1]=strtonum("0x" $i) }
        END {
            a1 = x[0x44] + x[0x45]*256
            a2 = x[0x45] + x[0x44]*256
            b1 = x[0x46] + x[0x47]*256
            b2 = x[0x47] + x[0x46]*256
            m = a1; if (a2>m) m=a2; if (b1>m) m=b1; if (b2>m) m=b2
            if (m > 0 && m < 20000) printf "EC:ec:%d", m
        }'
}

report() {
    local rpms fans r tmp t pwm_line ec
    tmp=$(highest_cpu_temp)
    rpms=$(fan_rpms)
    [ -n "$rpms" ] || rpms=$(fan_rpms_sensors)

    if [ -z "$rpms" ]; then
        pwm_line=$(cat /sys/class/hwmon/hwmon*/pwm*_enable 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
        ec=$(ec_fan_rpm)
        [ -n "$ec" ] && rpms="$ec"
    fi

    if [ -n "$tmp" ]; then
        t=$(to_c "$tmp")
    else
        t=$(thermal_from_sensors)
        [ -n "$t" ] || t=0
    fi

    printf 'CPU  temp : %sC\n' "${t:-N/A}"
    if [ -n "$rpms" ]; then
        fans=$(printf '%s\n' "$rpms" | awk -F: '{s+=$3} END {print s}')
        n=$(printf '%s\n' "$rpms" | wc -l)
        printf 'FAN  ; '
        printf '%s\n' "$rpms" | while IFS=: read -r src name rpm; do
            printf 'rpm  : %4d RPM\n' "$rpm"
        done | sed 's/^/      /'
        printf 'FAN  total: %4d RPM across %d sensor(s)\n' "$fans" "$n"
    else
        printf 'FAN  status: NO fan RPM sensor exposed\n'
        printf '      (HP EC controls fan; hwmon reports pwm1_enable=%s)\n' "${pwm_line:-N/A}"
    fi

    if [ -n "$rpms" ]; then
        if [ "$fans" -eq 0 ] && [ "$t" -ge "$WARN" ]; then
            printf 'STATUS     : WARNING - fan idle but CPU at %dC\n' "$t"
            return 2
        fi
    fi
    if [ "$t" -ge "$CRIT" ]; then
        printf 'STATUS     : CRITICAL - CPU at %dC exceeds %dC\n' "$t" "$CRIT"
        return 3
    fi
    if [ "$t" -ge "$WARN" ]; then
        printf 'STATUS     : WARNING - CPU at %dC exceeds %dC\n' "$t" "$WARN"
        return 2
    fi
    if [ -z "$rpms" ] && [ -n "$tmp" ]; then
        printf 'STATUS     : OK (thermals only; no fan RPM available)\n'
        return 0
    fi
    printf 'STATUS     : OK\n'
    return 0
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --watch|-w) WATCH=1 ;;
        -i) INTERVAL="$2"; shift ;;
        -c) CRIT="$2"; shift ;;
        -t) WARN="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'unknown option: %s\n\n' "$1"; usage; exit 1 ;;
    esac
    shift
done

if [ "$WATCH" -eq 1 ]; then
    while :; do
        clear
        command -v date >/dev/null 2>&1 && date '+%Y-%m-%d %H:%M:%S'
        report
        sleep "$INTERVAL"
    done
else
    report
    exit $?
fi
