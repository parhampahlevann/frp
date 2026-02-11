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
    sysctl -p "$CONFIG_FILE" >/dev/null 2>&1
}

backup_config() {
    if [[ -f $CONFIG_FILE ]]; then
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        echo "📁 Backup created: $BACKUP_FILE"
    fi
}

restore_config() {
    if [[ -f $BACKUP_FILE ]]; then
        cp "$BACKUP_FILE" "$CONFIG_FILE"
        apply_sysctl
        echo "✅ Configuration restored from backup"
    else
        echo "❌ No backup file found"
    fi
}

# ---------- Iran → Kharej Deep Optimization ----------
iran_kharej_mode() {
    clear
    echo "🇮🇷 Applying Iran → Kharej Deep Optimization..."
    
    backup_config
    
    cat > "$CONFIG_FILE" <<'EOF'
# Iran → Kharej Deep Optimization
# Optimized for high-latency, low-bandwidth connections
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mem = 262144 524288 786432
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_ecn = 2
net.ipv4.tcp_frto = 2
net.ipv4.tcp_recovery = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = hybla
net.core.default_qdisc = fq
net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_max_tw_buckets = 10000
net.ipv4.tcp_max_syn_backlog = 8192
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 8192
EOF

    apply_sysctl
    echo "✅ Iran → Kharej Deep Mode Applied"
    echo "⚠️  Recommended to reboot for full effect"
}

# ---------- Foreign Server Ultra Mode ----------
foreign_mode() {
    clear
    echo "🌍 Applying Foreign Server Ultra Mode..."
    
    backup_config
    
    cat > "$CONFIG_FILE" <<'EOF'
# Foreign Server Ultra Performance
# Optimized for low-latency, high-bandwidth connections
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_mem = 262144 524288 1048576
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_frto = 2
net.ipv4.tcp_recovery = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_max_syn_backlog = 65536
net.core.netdev_max_backlog = 500000
net.core.somaxconn = 65535
net.ipv4.ip_local_port_range = 1024 65535
EOF

    apply_sysctl
    echo "✅ Foreign Server Ultra Mode Applied"
    echo "⚠️  Recommended to reboot for full effect"
}

# ---------- MTU ----------
set_mtu_auto() {
    IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [[ -z "$IFACE" ]]; then
        echo "❌ Could not detect network interface"
        return 1
    fi
    
    echo "🔍 Detecting optimal MTU for $IFACE..."
    
    # Try different MTU sizes
    for mtu in 1500 1492 1480 1472 1460 1440 1400; do
        echo -n "Testing MTU $mtu... "
        if ping -c 2 -M do -s $((mtu - 28)) -W 1 8.8.8.8 >/dev/null 2>&1; then
            echo "OK"
            ip link set dev "$IFACE" mtu "$mtu"
            echo "✅ MTU set to $mtu on $IFACE"
            
            # Make it persistent
            if [[ -f /etc/network/interfaces ]]; then
                sed -i "/iface $IFACE/,/^$/s/mtu [0-9]*/mtu $mtu/" /etc/network/interfaces 2>/dev/null
            fi
            
            # For systemd-networkd
            if command -v networkctl >/dev/null 2>&1; then
                mkdir -p /etc/systemd/network
                cat > "/etc/systemd/network/10-$IFACE.link" <<EOF
[Match]
Name=$IFACE

[Link]
MTUBytes=$mtu
EOF
            fi
            return 0
        else
            echo "FAIL"
        fi
    done
    
    echo "❌ Could not find suitable MTU"
    return 1
}

set_mtu_manual() {
    IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [[ -z "$IFACE" ]]; then
        echo "❌ Could not detect network interface"
        return 1
    fi
    
    read -r -p "Enter MTU value (68-1500, recommended 1400-1500): " mtu
    if ! [[ "$mtu" =~ ^[0-9]+$ ]] || [ "$mtu" -lt 68 ] || [ "$mtu" -gt 1500 ]; then
        echo "❌ Invalid MTU value"
        return 1
    fi
    
    # Test the MTU before applying
    echo -n "Testing MTU $mtu... "
    if ping -c 2 -M do -s $((mtu - 28)) -W 1 8.8.8.8 >/dev/null 2>&1; then
        echo "OK"
        ip link set dev "$IFACE" mtu "$mtu"
        echo "✅ MTU set to $mtu on $IFACE"
        
        # Make it persistent
        if [[ -f /etc/network/interfaces ]]; then
            if grep -q "iface $IFACE" /etc/network/interfaces; then
                if grep -q "mtu" /etc/network/interfaces; then
                    sed -i "/iface $IFACE/,/^$/s/mtu [0-9]*/mtu $mtu/" /etc/network/interfaces
                else
                    sed -i "/iface $IFACE/s/$/ mtu $mtu/" /etc/network/interfaces
                fi
            fi
        fi
        
        # For systemd-networkd
        if command -v networkctl >/dev/null 2>&1; then
            mkdir -p /etc/systemd/network
            cat > "/etc/systemd/network/10-$IFACE.link" <<EOF
[Match]
Name=$IFACE

[Link]
MTUBytes=$mtu
EOF
        fi
    else
        echo "FAIL"
        echo "❌ MTU $mtu is not working properly"
        return 1
    fi
}

# ---------- DNS ----------
set_dns_safe() {
    echo "⚠️ Changing DNS settings..."
    
    # Backup current DNS
    cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # Use Cloudflare and Google DNS
    cat > /etc/resolv.conf <<'EOF'
# DNS configured by Network Optimizer
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 8.8.8.8
nameserver 8.8.4.4
options rotate timeout:1 attempts:3
EOF
    
    # Try to make it persistent based on distro
    if [[ -f /etc/debian_version ]]; then
        # For Debian/Ubuntu with resolvconf
        if command -v resolvconf >/dev/null 2>&1; then
            cat > /etc/resolvconf/resolv.conf.d/head <<'EOF'
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
            resolvconf -u
        fi
        
        # For Netplan (Ubuntu 18.04+)
        if [[ -d /etc/netplan ]]; then
            for file in /etc/netplan/*.yaml; do
                [[ -f "$file" ]] || continue
                cp "$file" "$file.backup.$(date +%Y%m%d_%H%M%S)"
                yq e '.network.ethernets.*.nameservers.addresses = ["1.1.1.1", "1.0.0.1", "8.8.8.8", "8.8.4.4"]' -i "$file"
                netplan apply
            done
        fi
    fi
    
    # For systemd-resolved
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        mkdir -p /etc/systemd/resolved.conf.d/
        cat > /etc/systemd/resolved.conf.d/dns.conf <<'EOF'
[Resolve]
DNS=1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4
FallbackDNS=9.9.9.9 149.112.112.112
DNSOverTLS=opportunistic
DNSSEC=allow-downgrade
Cache=yes
EOF
        systemctl restart systemd-resolved
    fi
    
    echo "✅ DNS changed to Cloudflare (1.1.1.1, 1.0.0.1) and Google (8.8.8.8, 8.8.4.4)"
    echo "📁 Backup created: /etc/resolv.conf.backup.*"
    echo "🔍 Testing DNS connectivity..."
    
    if ping -c 2 -W 2 1.1.1.1 >/dev/null 2>&1; then
        echo "✅ DNS servers are reachable"
    else
        echo "⚠️  Warning: Some DNS servers may not be reachable"
    fi
}

# ---------- Test Connection ----------
test_connection() {
    echo "🔍 Testing network connection..."
    
    echo "1. Testing gateway..."
    gateway=$(ip route | grep default | awk '{print $3}')
    if ping -c 2 -W 2 "$gateway" >/dev/null 2>&1; then
        echo "✅ Gateway $gateway is reachable"
    else
        echo "❌ Gateway $gateway is not reachable"
    fi
    
    echo "2. Testing external connectivity..."
    if ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1; then
        echo "✅ External connectivity OK"
    else
        echo "❌ No external connectivity"
    fi
    
    echo "3. Testing DNS resolution..."
    if nslookup google.com >/dev/null 2>&1; then
        echo "✅ DNS resolution OK"
    else
        echo "❌ DNS resolution failed"
    fi
    
    echo "4. Current MTU:"
    ip link | grep mtu
}

# ---------- Status ----------
show_status() {
    clear
    echo "📊 Network Status"
    echo "=================="
    
    echo -e "\n🌐 Network Interfaces:"
    ip -br addr show
    
    echo -e "\n🛣️  Routing:"
    ip route show default
    
    echo -e "\n⚙️  Sysctl Parameters:"
    echo "Congestion Control: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'Not set')"
    echo "Queue Discipline: $(sysctl -n net.core.default_qdisc 2>/dev/null || echo 'Not set')"
    echo "TCP Fast Open: $(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo 'Not set')"
    
    echo -e "\n📏 MTU:"
    ip link | grep mtu
    
    echo -e "\n🔗 Current Connections:"
    ss -tunp | head -20
    
    echo -e "\n📡 DNS:"
    cat /etc/resolv.conf
    
    if [[ -f $CONFIG_FILE ]]; then
        echo -e "\n📁 Active Configuration: $CONFIG_FILE"
    else
        echo -e "\n⚠️  No custom configuration applied"
    fi
}

# ---------- Reset to Default ----------
reset_to_default() {
    clear
    echo "🔄 Resetting network settings to default..."
    
    if [[ -f $CONFIG_FILE ]]; then
        rm -f "$CONFIG_FILE"
        echo "✅ Removed custom sysctl configuration"
    fi
    
    if [[ -f $BACKUP_FILE ]]; then
        rm -f "$BACKUP_FILE"
    fi
    
    # Restore original sysctl settings
    sysctl --system >/dev/null 2>&1
    
    # Restore original DNS if backup exists
    if ls /etc/resolv.conf.backup.* 2>/dev/null | head -1; then
        latest_backup=$(ls -t /etc/resolv.conf.backup.* | head -1)
        cp "$latest_backup" /etc/resolv.conf
        echo "✅ Restored DNS from backup"
    fi
    
    # Reset MTU to default
    IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [[ -n "$IFACE" ]]; then
        ip link set dev "$IFACE" mtu 1500
        echo "✅ Reset MTU to 1500 on $IFACE"
    fi
    
    echo "✅ All settings reset to default"
    echo "⚠️  Reboot recommended for full reset"
}

# ---------- Menu ----------
menu() {
    clear
    echo "=========================================="
    echo "       Network Optimization Menu"
    echo "=========================================="
    echo "1) 🇮🇷 Iran → Kharej Deep Optimization"
    echo "2) 🌍 Foreign Server Ultra Mode"
    echo "3) Change MTU"
    echo "4) Change DNS (Safe Method)"
    echo "5) Test Network Connection"
    echo "6) Show Status"
    echo "7) Restore Backup Configuration"
    echo "8) Reset to Default Settings"
    echo "9) Reboot System"
    echo "0) Exit"
    echo "=========================================="
    read -r -p "Choose [0-9]: " choice
}

check_root

# Check if sysctl.d directory exists
mkdir -p /etc/sysctl.d

while true; do
    menu
    case $choice in
        1) iran_kharej_mode ;;
        2) foreign_mode ;;
        3)
            echo "1) Auto Detect MTU"
            echo "2) Manual MTU"
            read -r -p "Choose [1-2]: " mtu_choice
            case $mtu_choice in
                1) set_mtu_auto ;;
                2) set_mtu_manual ;;
                *) echo "❌ Invalid MTU option" ;;
            esac
        ;;
        4) set_dns_safe ;;
        5) test_connection ;;
        6) show_status ;;
        7) restore_config ;;
        8) reset_to_default ;;
        9)
            echo "⚠️ Rebooting system in 5 seconds..."
            sleep 5
            reboot
        ;;
        0) 
            echo "👋 Goodbye!"
            exit 0
        ;;
        *) echo "❌ Invalid option" ;;
    esac
    echo
    if [[ $choice -ne 6 ]]; then
        read -r -p "Press Enter to continue..."
    fi
done
