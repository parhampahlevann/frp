#!/bin/bash
exec </dev/tty

CONFIG_FILE="/etc/sysctl.d/99-network-optimizer.conf"
BACKUP_FILE="/etc/sysctl.d/99-network-optimizer.conf.bak"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ Run as root"
        exit 1
    fi
}

apply_sysctl() {
    sysctl --system >/dev/null 2>&1
}

# ---------- Iran → Kharej Deep Optimization ----------
iran_kharej_mode() {
    clear
    echo "🇮🇷 Applying Iran → Kharej Deep Optimization..."

    [[ -f $CONFIG_FILE ]] || touch $CONFIG_FILE
cat > $CONFIG_FILE <<'EOF'
# Iran → Kharej Deep Optimization
net.ipv4.tcp_retries2=8
net.ipv4.tcp_syn_retries=5
net.ipv4.tcp_synack_retries=5
net.ipv4.tcp_frto=2
net.ipv4.tcp_recovery=1
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_mtu_probing=2
net.core.netdev_budget=800
net.core.netdev_budget_usecs=10000
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.ipv4.tcp_rmem=4096 262144 67108864
net.ipv4.tcp_wmem=4096 262144 67108864
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_intvl=20
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_slow_start_after_idle=0
EOF

    apply_sysctl
    echo "✅ Iran → Kharej Deep Mode Applied"
}

# ---------- Foreign Server Ultra Mode ----------
foreign_mode() {
    clear
    echo "🌍 Applying Foreign Server Ultra Mode..."

    [[ -f $CONFIG_FILE ]] || touch $CONFIG_FILE
cat > $CONFIG_FILE <<'EOF'
# Foreign Server Ultra Performance
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_low_latency=1
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 524288 134217728
net.ipv4.tcp_wmem=4096 524288 134217728
net.core.netdev_max_backlog=500000
net.ipv4.tcp_max_syn_backlog=16384
net.ipv4.tcp_max_tw_buckets=800000
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5
EOF

    apply_sysctl
    echo "✅ Foreign Server Ultra Mode Applied"
}

# ---------- MTU ----------
set_mtu_auto() {
    IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    ping -c 2 -M do -s 1472 8.8.8.8 >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then MTU=1500; else MTU=1420; fi
    ip link set dev $IFACE mtu $MTU
    echo "MTU set to $MTU on $IFACE"
}

set_mtu_manual() {
    read -r -p "Enter MTU value (e.g. 1400): " mtu < /dev/tty
    IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    ip link set dev $IFACE mtu $mtu
    echo "MTU set to $mtu on $IFACE"
}

# ---------- DNS ----------
set_dns_hn() {
    # هتزنر DNS ایمن
    echo -e "nameserver 213.133.98.98\nnameserver 213.133.99.99" > /etc/resolv.conf
    echo "✅ DNS changed to Hetzner servers safely"
}

# ---------- Status ----------
show_status() {
    clear
    echo "📊 Network Status"
    echo
    echo "Congestion Control:"; sysctl net.ipv4.tcp_congestion_control
    echo "Queue Discipline:"; sysctl net.core.default_qdisc
    echo "MTU:"; ip link | grep mtu
    echo "DNS:"; cat /etc/resolv.conf
}

# ---------- Menu ----------
menu() {
    clear
    echo "=================================="
    echo "   Network Optimization Menu"
    echo "=================================="
    echo "1) 🇮🇷 Iran → Kharej Deep Optimization"
    echo "2) 🌍 Foreign Server Ultra Mode"
    echo "3) Change MTU"
    echo "4) Change DNS to Hetzner"
    echo "5) Reboot System"
    echo "6) Status"
    echo "7) Exit"
    echo "=================================="
    read -r -p "Choose [1-7]: " choice < /dev/tty
}

check_root

while true; do
    menu
    case $choice in
        1) iran_kharej_mode ;;
        2) foreign_mode ;;
        3)
            echo "1) Auto MTU"
            echo "2) Manual MTU"
            read -r -p "Choose [1-2]: " mtu_choice < /dev/tty
            case $mtu_choice in
                1) set_mtu_auto ;;
                2) set_mtu_manual ;;
                *) echo "Invalid MTU option" ;;
            esac
        ;;
        4) set_dns_hn ;;
        5)
            echo "⚠️ Rebooting system..."
            sleep 2
            reboot
        ;;
        6) show_status ;;
        7) exit 0 ;;
        *) echo "Invalid option" ;;
    esac
    echo
    read -r -p "Press Enter to continue..." < /dev/tty
done
