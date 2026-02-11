#!/bin/bash
exec </dev/tty

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CONFIG_FILE="/etc/sysctl.d/99-network-optimizer.conf"
BACKUP_DIR="/root/network-backup"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Run as root${NC}"
        exit 1
    fi
}

create_backup_dir() {
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR/sysctl.d"
    mkdir -p "$BACKUP_DIR/network"
    mkdir -p "$BACKUP_DIR/dns"
}

backup_current_settings() {
    create_backup_dir
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    # Backup sysctl settings
    if [[ -f $CONFIG_FILE ]]; then
        cp "$CONFIG_FILE" "$BACKUP_DIR/sysctl.d/99-network-optimizer.conf.$timestamp"
    fi
    
    # Backup DNS settings
    cp /etc/resolv.conf "$BACKUP_DIR/dns/resolv.conf.$timestamp" 2>/dev/null
    
    # Backup network configs
    cp -r /etc/network/interfaces "$BACKUP_DIR/network/interfaces.$timestamp" 2>/dev/null
    cp -r /etc/netplan/*.yaml "$BACKUP_DIR/network/" 2>/dev/null
    cp -r /etc/systemd/network/* "$BACKUP_DIR/network/" 2>/dev/null
    
    echo -e "${GREEN}✅ Backup created in $BACKUP_DIR${NC}"
}

# ---------- Fix Google Sites Issue ----------
fix_google_sites() {
    clear
    echo -e "${BLUE}🔧 Fixing Google Sites connectivity issue...${NC}"
    
    # 1. Fix IPv6 (disable if problematic)
    echo -e "\n${YELLOW}1. Checking IPv6 configuration...${NC}"
    if sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null | grep -q 0; then
        echo "Disabling IPv6 temporarily for Google sites..."
        sysctl -w net.ipv6.conf.all.disable_ipv6=1
        sysctl -w net.ipv6.conf.default.disable_ipv6=1
        
        # Make it persistent
        cat >> /etc/sysctl.d/99-disable-ipv6.conf <<EOF
# Disable IPv6 for better Google connectivity
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
        echo -e "${GREEN}✅ IPv6 disabled${NC}"
    fi
    
    # 2. Fix MTU for Google services
    echo -e "\n${YELLOW}2. Optimizing MTU for Google services...${NC}"
    IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    
    # Test different MTUs specifically for Google
    for mtu in 1460 1472 1480 1492 1500; do
        echo -n "Testing MTU $mtu with Google... "
        if ping -c 2 -M do -s $((mtu - 28)) -W 2 google.com >/dev/null 2>&1; then
            echo -e "${GREEN}OK${NC}"
            ip link set dev "$IFACE" mtu "$mtu"
            echo -e "${GREEN}✅ MTU set to $mtu on $IFACE${NC}"
            
            # Make persistent
            if [[ -d /etc/systemd/network ]]; then
                mkdir -p /etc/systemd/network
                cat > "/etc/systemd/network/10-$IFACE.link" <<EOF
[Match]
Name=$IFACE

[Link]
MTUBytes=$mtu
EOF
            fi
            break
        else
            echo -e "${RED}FAIL${NC}"
        fi
    done
    
    # 3. Optimize TCP for Google
    echo -e "\n${YELLOW}3. Optimizing TCP for Google services...${NC}"
    cat >> /etc/sysctl.d/99-google-optimizer.conf <<EOF
# Google services optimization
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 2
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_window_scaling = 1
EOF
    sysctl --system >/dev/null 2>&1
    
    # 4. Fix DNS for Google
    echo -e "\n${YELLOW}4. Configuring Google-friendly DNS...${NC}"
    fix_dns_hetzner
    
    # 5. Add Google IPs to hosts file for faster resolution
    echo -e "\n${YELLOW}5. Adding Google IPs to hosts file...${NC}"
    cat >> /etc/hosts <<'EOF'

# Google services direct IPs
142.250.185.46 google.com
142.250.185.46 www.google.com
142.250.185.46 mail.google.com
142.250.185.46 drive.google.com
142.250.185.46 docs.google.com
142.250.185.46 youtube.com
142.250.185.46 www.youtube.com
216.58.200.46 googleapis.com
216.58.200.46 gstatic.com
EOF
    
    echo -e "\n${GREEN}✅ Google sites fix applied!${NC}"
    echo -e "${YELLOW}Testing Google connectivity...${NC}"
    if curl -s -I --connect-timeout 5 https://google.com >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Google is now accessible!${NC}"
    else
        echo -e "${RED}❌ Still having issues. Trying alternative fix...${NC}"
        # Alternative: Use proxy DNS
        fix_dns_hetzner_force
    fi
}

# ---------- Hetzner DNS Fix (Complete Overhaul) ----------
fix_dns_hetzner() {
    clear
    echo -e "${BLUE}🔧 Hetzner DNS Configuration (Safe Mode)${NC}"
    
    # Backup everything first
    backup_current_settings
    
    # Detect Hetzner
    if curl -s --connect-timeout 2 http://169.254.169.254/hetzner-metadata >/dev/null 2>&1 || \
       hostname -f | grep -qi "hetzner"; then
        echo -e "${YELLOW}📡 Hetzner server detected${NC}"
    fi
    
    # Method 1: Disable systemd-resolved if it's causing issues
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        echo -e "\n${YELLOW}1. Disabling systemd-resolved...${NC}"
        systemctl stop systemd-resolved
        systemctl disable systemd-resolved
        
        # Remove symlink and create real resolv.conf
        rm -f /etc/resolv.conf
    fi
    
    # Create fresh resolv.conf
    cat > /etc/resolv.conf <<'EOF'
# Hetzner Optimized DNS Configuration
# Primary: Cloudflare (lowest latency)
nameserver 1.1.1.1
nameserver 1.0.0.1
# Secondary: Google (reliable)
nameserver 8.8.8.8
nameserver 8.8.4.4
# Tertiary: Quad9 (secure)
nameserver 9.9.9.9
nameserver 149.112.112.112
options rotate
options timeout:1
options attempts:3
options edns0
options trust-ad
EOF
    
    # Make it immutable to prevent overwriting
    chattr +i /etc/resolv.conf 2>/dev/null || echo -e "${YELLOW}⚠️  Could not lock resolv.conf${NC}"
    
    # Method 2: For Ubuntu/Debian with netplan
    if [[ -d /etc/netplan ]]; then
        echo -e "\n${YELLOW}2. Configuring Netplan...${NC}"
        for file in /etc/netplan/*.yaml; do
            if [[ -f "$file" ]]; then
                cp "$file" "$file.backup"
                # Simple sed replacement for nameservers
                sed -i '/nameservers:/,/addresses:/ s/addresses:.*/addresses: [1.1.1.1, 1.0.0.1, 8.8.8.8, 8.8.4.4]/' "$file"
            fi
        done
        netplan apply 2>/dev/null
    fi
    
    # Method 3: For Debian with interfaces
    if [[ -f /etc/network/interfaces ]]; then
        echo -e "\n${YELLOW}3. Configuring network interfaces...${NC}"
        cp /etc/network/interfaces /etc/network/interfaces.backup
        # Add DNS if not present
        if ! grep -q "dns-nameservers" /etc/network/interfaces; then
            echo "" >> /etc/network/interfaces
            echo "dns-nameservers 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4" >> /etc/network/interfaces
        fi
    fi
    
    # Method 4: For RHEL/CentOS
    if [[ -f /etc/sysconfig/network-scripts/ifcfg-eth0 ]]; then
        echo -e "\n${YELLOW}4. Configuring NetworkManager...${NC}"
        for ifcfg in /etc/sysconfig/network-scripts/ifcfg-*; do
            sed -i '/^DNS/d' "$ifcfg"
            echo "DNS1=1.1.1.1" >> "$ifcfg"
            echo "DNS2=1.0.0.1" >> "$ifcfg"
            echo "DNS3=8.8.8.8" >> "$ifcfg"
        done
        systemctl restart NetworkManager 2>/dev/null
    fi
    
    # Flush DNS cache
    echo -e "\n${YELLOW}5. Flushing DNS cache...${NC}"
    systemd-resolve --flush-caches 2>/dev/null || resolvectl flush-caches 2>/dev/null || true
    
    # Test DNS
    echo -e "\n${YELLOW}Testing DNS configuration...${NC}"
    if nslookup google.com 1.1.1.1 >/dev/null 2>&1; then
        echo -e "${GREEN}✅ DNS working with Cloudflare${NC}"
    else
        echo -e "${RED}❌ DNS not working, applying emergency fix...${NC}"
        fix_dns_hetzner_emergency
    fi
}

# Emergency DNS fix (nuclear option)
fix_dns_hetzner_emergency() {
    echo -e "${RED}⚠️  Applying emergency DNS fix...${NC}"
    
    # Kill everything that might be managing DNS
    systemctl stop systemd-resolved 2>/dev/null
    systemctl disable systemd-resolved 2>/dev/null
    systemctl stop NetworkManager 2>/dev/null
    systemctl stop resolvconf 2>/dev/null
    
    # Force remove and recreate resolv.conf
    rm -f /etc/resolv.conf
    
    # Create minimal working DNS
    cat > /etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
options timeout:1 attempts:1 rotate
EOF
    
    # Lock it
    chattr +i /etc/resolv.conf 2>/dev/null
    
    # Add to hosts file as backup
    cat >> /etc/hosts <<'EOF'
# DNS Emergency Fallback
1.1.1.1 one.one.one.one
8.8.8.8 google-dns.google.com
EOF
    
    echo -e "${GREEN}✅ Emergency DNS fix applied${NC}"
}

# Force DNS fix (most aggressive)
fix_dns_hetzner_force() {
    echo -e "${RED}💣 Applying FORCE DNS fix...${NC}"
    
    # Remove all DNS managers
    apt-get remove --purge -y resolvconf systemd-resolved 2>/dev/null
    yum remove -y systemd-resolved 2>/dev/null
    
    # Create static resolv.conf
    rm -f /etc/resolv.conf
    cat > /etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
    
    # Lock it forever
    chattr +i /etc/resolv.conf
    
    # Disable IPv6 completely
    cat > /etc/sysctl.d/99-disable-ipv6.conf <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    sysctl --system >/dev/null 2>&1
    
    echo -e "${GREEN}✅ Force DNS fix applied - DNS is now locked${NC}"
}

# ---------- Iran Optimization (Enhanced) ----------
iran_kharej_mode() {
    clear
    echo -e "${BLUE}🇮🇷 Iran → Kharej Deep Optimization${NC}"
    
    backup_current_settings
    
    cat > "$CONFIG_FILE" <<'EOF'
# Iran → Kharej Deep Optimization
# Optimized for high-latency, packet loss environment

# Buffer settings for high latency
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_mem = 262144 524288 1048576

# Congestion control for high latency
net.ipv4.tcp_congestion_control = hybla
net.core.default_qdisc = fq
net.ipv4.tcp_ecn = 2

# Retransmission optimization
net.ipv4.tcp_retries2 = 10
net.ipv4.tcp_syn_retries = 4
net.ipv4.tcp_synack_retries = 4
net.ipv4.tcp_frto = 2
net.ipv4.tcp_recovery = 1

# Keepalive for unstable connections
net.ipv4.tcp_keepalive_time = 200
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_fin_timeout = 15

# MTU and probing
net.ipv4.tcp_mtu_probing = 2
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 1

# Buffer auto-tuning
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
EOF

    sysctl --system >/dev/null 2>&1
    echo -e "${GREEN}✅ Iran → Kharej Deep Mode Applied${NC}"
    
    # Auto-configure MTU for Iran
    echo -e "\n${YELLOW}Configuring optimal MTU for Iran...${NC}"
    IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    ip link set dev "$IFACE" mtu 1420
    echo -e "${GREEN}✅ MTU set to 1420 on $IFACE${NC}"
}

# ---------- Foreign Server Ultra Mode ----------
foreign_mode() {
    clear
    echo -e "${BLUE}🌍 Foreign Server Ultra Mode${NC}"
    
    backup_current_settings
    
    cat > "$CONFIG_FILE" <<'EOF'
# Foreign Server Ultra Performance
# Optimized for low-latency, high-bandwidth

# Max buffer sizes
net.core.rmem_max = 268435456
net.core.wmem_max = 268435456
net.ipv4.tcp_rmem = 4096 87380 268435456
net.ipv4.tcp_wmem = 4096 65536 268435456
net.ipv4.tcp_mem = 262144 524288 2097152

# Modern congestion control
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_ecn = 1

# High connection handling
net.core.netdev_max_backlog = 500000
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.ip_local_port_range = 1024 65535

# Fast recycling
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
EOF

    sysctl --system >/dev/null 2>&1
    echo -e "${GREEN}✅ Foreign Server Ultra Mode Applied${NC}"
}

# ---------- MTU Optimization ----------
optimize_mtu() {
    clear
    echo -e "${BLUE}📏 MTU Optimization${NC}"
    
    IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [[ -z "$IFACE" ]]; then
        echo -e "${RED}❌ No network interface found${NC}"
        return
    fi
    
    echo "Interface: $IFACE"
    echo "Testing optimal MTU..."
    echo ""
    
    best_mtu=1500
    for mtu in 1500 1492 1480 1472 1460 1450 1440 1430 1420 1410 1400; do
        echo -n "Testing MTU $mtu... "
        if ping -c 2 -M do -s $((mtu - 28)) -W 1 google.com >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC}"
            best_mtu=$mtu
        else
            echo -e "${RED}✗${NC}"
        fi
    done
    
    echo -e "\n${GREEN}✅ Best MTU: $best_mtu${NC}"
    read -p "Apply this MTU? (y/n): " confirm
    if [[ $confirm == "y" ]]; then
        ip link set dev "$IFACE" mtu "$best_mtu"
        echo -e "${GREEN}✅ MTU set to $best_mtu${NC}"
    fi
}

# ---------- Complete System Fix ----------
complete_fix() {
    clear
    echo -e "${BLUE}🛠️  Complete System Network Fix${NC}"
    echo "=================================="
    
    # 1. Fix DNS
    echo -e "\n${YELLOW}1. Fixing DNS...${NC}"
    fix_dns_hetzner_force
    
    # 2. Fix Google sites
    echo -e "\n${YELLOW}2. Fixing Google sites...${NC}"
    sysctl -w net.ipv6.conf.all.disable_ipv6=1
    sysctl -w net.ipv6.conf.default.disable_ipv6=1
    
    # 3. Optimize MTU
    echo -e "\n${YELLOW}3. Optimizing MTU...${NC}"
    IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    ip link set dev "$IFACE" mtu 1460
    
    # 4. Apply BBR
    echo -e "\n${YELLOW}4. Enabling BBR...${NC}"
    modprobe tcp_bbr 2>/dev/null
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr
    sysctl -w net.core.default_qdisc=fq
    
    # 5. Restart network
    echo -e "\n${YELLOW}5. Restarting network...${NC}"
    systemctl restart networking 2>/dev/null || systemctl restart NetworkManager 2>/dev/null
    
    echo -e "\n${GREEN}✅ Complete system fix applied!${NC}"
    echo -e "${YELLOW}Please reboot for all changes to take effect.${NC}"
}

# ---------- Menu ----------
menu() {
    clear
    echo "=========================================="
    echo "     Network Optimization Menu v3.0"
    echo "=========================================="
    echo "1) 🇮🇷 Iran → Kharej (Deep Optimize)"
    echo "2) 🌍 Foreign Server (Ultra Mode)"
    echo "3) 📏 MTU Optimization"
    echo "4) 🔧 DNS Fix (Hetzner Safe Mode)"
    echo "5) 💣 DNS Fix (Force Mode - Recommended for Hetzner)"
    echo "6) 🔧 Fix Google Sites (Not Loading)"
    echo "7) 🛠️  Complete System Fix (Fix All)"
    echo "8) 📊 Show Status"
    echo "9) 📁 Backup Current Settings"
    echo "10) 🔄 Restore from Backup"
    echo "11) ⚠️  Reboot System"
    echo "0) ❌ Exit"
    echo "=========================================="
    read -r -p "Choose [0-11]: " choice
}

# ---------- Main ----------
check_root

while true; do
    menu
    case $choice in
        1) iran_kharej_mode ;;
        2) foreign_mode ;;
        3) optimize_mtu ;;
        4) fix_dns_hetzner ;;
        5) fix_dns_hetzner_force ;;
        6) fix_google_sites ;;
        7) complete_fix ;;
        8) 
            clear
            echo -e "${BLUE}📊 System Status${NC}"
            echo "================"
            echo -e "\n${YELLOW}DNS:${NC}"
            cat /etc/resolv.conf
            echo -e "\n${YELLOW}IPv6:${NC}"
            sysctl -n net.ipv6.conf.all.disable_ipv6
            echo -e "\n${YELLOW}MTU:${NC}"
            ip link | grep mtu | head -1
            echo -e "\n${YELLOW}TCP CC:${NC}"
            sysctl -n net.ipv4.tcp_congestion_control
            echo -e "\n${YELLOW}Google Test:${NC}"
            curl -s -I --connect-timeout 3 https://google.com -o /dev/null -w "HTTP Status: %{http_code}\n" || echo "Failed"
            ;;
        9) backup_current_settings ;;
        10) 
            echo "Available backups:"
            ls -la "$BACKUP_DIR/dns/" 2>/dev/null || echo "No backups found"
            read -p "Enter timestamp to restore: " ts
            if [[ -f "$BACKUP_DIR/dns/resolv.conf.$ts" ]]; then
                cp "$BACKUP_DIR/dns/resolv.conf.$ts" /etc/resolv.conf
                echo -e "${GREEN}✅ DNS restored${NC}"
            fi
            ;;
        11)
            echo -e "${RED}⚠️  Rebooting in 5 seconds...${NC}"
            sleep 5
            reboot
            ;;
        0) 
            echo -e "${GREEN}👋 Goodbye!${NC}"
            exit 0
            ;;
        *) echo -e "${RED}❌ Invalid option${NC}" ;;
    esac
    echo
    read -r -p "Press Enter to continue..."
done
