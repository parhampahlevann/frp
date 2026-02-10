#!/bin/bash
exec </dev/tty

SYSCTL_FILE="/etc/sysctl.d/99-bbr-tcp.conf"
BACKUP_FILE="/etc/sysctl.d/99-bbr-tcp.conf.bak"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ Run as root"
        exit 1
    fi
}

kernel_supports_bbr() {
    sysctl net.ipv4.tcp_available_congestion_control | grep -q bbr
}

install_bbr() {
    clear
    echo "🚀 Installing BBR + TCP Optimization"

    if ! kernel_supports_bbr; then
        echo "❌ Kernel does NOT support BBR"
        echo "👉 Kernel >= 4.9 required"
        exit 1
    fi

    # Backup
    [[ -f $SYSCTL_FILE ]] && cp $SYSCTL_FILE $BACKUP_FILE

    cat > $SYSCTL_FILE <<'EOF'
############################################
# BBR + TCP Advanced Optimization
############################################

# --- Congestion Control ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- TCP Latency & Stability ---
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_window_scaling = 1

# --- Buffers ---
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# --- Queue & Backlog ---
net.core.netdev_max_backlog = 32768
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 600000

# --- Connection Reuse ---
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# --- Protection & Cleanups ---
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_orphans = 32768
EOF

    sysctl --system >/dev/null 2>&1

    echo
    echo "✅ BBR ENABLED"
    sysctl net.ipv4.tcp_congestion_control
    lsmod | grep bbr || true
    echo
    echo "⚠️ Reboot is RECOMMENDED (not mandatory)"
}

remove_bbr() {
    clear
    echo "🧹 Removing BBR + TCP Optimization"

    if [[ -f $BACKUP_FILE ]]; then
        mv $BACKUP_FILE $SYSCTL_FILE
    else
        rm -f $SYSCTL_FILE
    fi

    sysctl --system >/dev/null 2>&1

    echo "✅ Restored system TCP settings"
}

status_bbr() {
    clear
    echo "📊 BBR STATUS"
    echo
    sysctl net.ipv4.tcp_congestion_control
    echo
    echo "Available CC:"
    sysctl net.ipv4.tcp_available_congestion_control
    echo
    echo "Queue Disc:"
    sysctl net.core.default_qdisc
}

menu() {
    clear
    echo "======================================"
    echo "      🚀 BBR + TCP OPTIMIZER"
    echo "======================================"
    echo "1) Install / Enable BBR"
    echo "2) Remove / Restore Defaults"
    echo "3) Show Status"
    echo "4) Exit"
    echo "======================================"
    read -r -p "Choose [1-4]: " choice < /dev/tty
}

check_root

while true; do
    menu
    case $choice in
        1) install_bbr ;;
        2) remove_bbr ;;
        3) status_bbr ;;
        4) exit 0 ;;
        *) echo "❌ Invalid option" ;;
    esac
    echo
    read -r -p "Press Enter to continue..." < /dev/tty
done
