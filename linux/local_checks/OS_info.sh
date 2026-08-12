#!/usr/bin/env bash
# ==============================================================================
# Local Check Checkmk: OS Information (Terpisah)
# ==============================================================================

if [ -f /etc/os-release ]; then
    . /etc/os-release
    # Output Checkmk: Status 0 (OK), Nama Service "OS_Detail", Tanpa Perf Data (-), Status Text
    echo "0 \"Sistem Operasi\" - OS: $PRETTY_NAME, Kernel: $(uname -r)"
else
    echo "1 \"Sistem Operasi\" - OS tidak terdeteksi sepenuhnya."
fi
