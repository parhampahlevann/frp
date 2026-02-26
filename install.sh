#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check root access
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Backup files
backup_files() {
    if [[ ! -f /etc/sysctl.conf.backup ]]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.backup
        echo -e "${GREEN}Backup created: /etc/sysctl.conf.backup${NC}"
    fi
    
    if [[ ! -f /etc/resolv.conf.backup ]]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup
        echo -e "${GREEN}Backup created: /etc/resolv.conf.backup${NC}"
    fi
}

# Restore backups
restore_backups() {
    if [[ -f /etc/sysctl.conf.backup ]]; then
        cp /etc/sysctl.conf.backup /etc/sysctl.conf
        echo -e "${GREEN}Restored sysctl.conf from backup${NC}"
    fi
    
    if [[ -f /etc/resolv.conf.backup ]]; then
        cp /etc/resolv.conf.backup /etc/resolv.conf
        echo -e "${GREEN}Restored resolv.conf from backup${NC}"
    fi
}

# Get network interface
get_interface() {
    echo $(ip -4 route show default | awk '{print $5}' | head -1)
}

# Install prerequisites
install_prerequisites() {
    echo -e "${YELLOW}Installing prerequisites...${NC}"
    apt-get update
    apt-get install -y ethtool irqbalance nano curl wget
    echo -e "${GREEN}Prerequisites installed${NC}"
}

# Step 1: Disable TSO/GSO/GRO
step1() {
    echo -e "${YELLOW}Step 1: Disabling TSO/GSO/GRO...${NC}"
    IF=$(get_interface)
    if [[ -n "$IF" ]]; then
        ethtool -K $IF tso off gso off gro off
        echo -e "${GREEN}✓ TSO/GSO/GRO disabled on $IF${NC}"
        
        # Make permanent
        if ! grep -q "ethtool -K $IF" /etc/rc.local; then
            sed -i '/exit 0/d' /etc/rc.local 2>/dev/null
            echo "ethtool -K $IF tso off gso off gro off" >> /etc/rc.local
            echo "exit 0" >> /etc/rc.local
            chmod +x /etc/rc.local
        fi
    else
        echo -e "${RED}Failed to detect network interface${NC}"
    fi
}

# Step 2: Set txqueuelen
step2() {
    echo -e "${YELLOW}Step 2: Setting txqueuelen to 2500...${NC}"
    IF=$(get_interface)
    if [[ -n "$IF" ]]; then
        ip link set dev $IF txqueuelen 2500
        echo -e "${GREEN}✓ txqueuelen set to 2500 on $IF${NC}"
        
        # Make permanent
        if ! grep -q "ip link set dev $IF txqueuelen" /etc/rc.local; then
            sed -i '/exit 0/d' /etc/rc.local 2>/dev/null
            echo "ip link set dev $IF txqueuelen 2500" >> /etc/rc.local
            echo "exit 0" >> /etc/rc.local
            chmod +x /etc/rc.local
        fi
    else
        echo -e "${RED}Failed to detect network interface${NC}"
    fi
}

# Step 3: Install and configure irqbalance
step3() {
    echo -e "${YELLOW}Step 3: Configuring irqbalance...${NC}"
    apt-get install -y irqbalance
    systemctl enable irqbalance
    systemctl start irqbalance
    echo -e "${GREEN}✓ irqbalance configured and started${NC}"
}

# Step 4: Apply HTB qdisc configuration
step4() {
    echo -e "${YELLOW}Step 4: Applying HTB qdisc configuration...${NC}"
    IF=$(get_interface)
    if [[ -n "$IF" ]]; then
        tc qdisc del dev $IF root 2>/dev/null
        tc qdisc add dev $IF root handle 1: htb default 20
        tc class add dev $IF parent 1: classid 1:1 htb rate 1gbit ceil 1gbit
        tc class add dev $IF parent 1:1 classid 1:10 htb rate 200mbit ceil 1gbit prio 1
        tc class add dev $IF parent 1:1 classid 1:20 htb rate 800mbit ceil 1gbit prio 2
        tc qdisc add dev $IF parent 1:10 handle 10: fq_codel limit 1000
        tc qdisc add dev $IF parent 1:20 handle 20: netem delay 15ms limit 10000
        tc filter add dev $IF parent 1: protocol ip prio 1 u32 match ip dport 22 0xffff flowid 1:10
        tc filter add dev $IF parent 1: protocol ip prio 1 u32 match ip sport 22 0xffff flowid 1:10
        tc filter add dev $IF parent 1: protocol ip prio 2 u32 match ip protocol 1 0xff flowid 1:10
        echo -e "${GREEN}✓ HTB qdisc configuration applied${NC}"
    else
        echo -e "${RED}Failed to detect network interface${NC}"
    fi
}

# Step 5: Apply Cake qdisc configuration
step5() {
    echo -e "${YELLOW}Step 5: Applying Cake qdisc configuration...${NC}"
    IF=$(get_interface)
    if [[ -n "$IF" ]]; then
        tc qdisc del dev $IF root 2>/dev/null
        tc qdisc add dev $IF root cake bandwidth 1Gbit besteffort ack-filter nat
        echo -e "${GREEN}✓ Cake qdisc configuration applied${NC}"
    else
        echo -e "${RED}Failed to detect network interface${NC}"
    fi
}

# Step 6: Apply sysctl configuration
step6() {
    echo -e "${YELLOW}Step 6: Applying sysctl configuration...${NC}"
    
    cat > /etc/sysctl.conf << 'EOF'
# System Optimization Settings
fs.file-max = 2097152
fs.nr_open = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
vm.swappiness = 5
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.min_free_kbytes = 65536
vm.vfs_cache_pressure = 50
vm.overcommit_memory = 1

# Network Core Settings
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.core.dev_weight = 64
net.core.default_qdisc = fq
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 8388608
net.core.wmem_max = 8388608
net.core.optmem_max = 65536

# IPv4 Settings
net.ipv4.ip_forward = 1
net.ipv4.ip_local_port_range = 1024 65535

# TCP Memory Settings
net.ipv4.tcp_mem = 65536 131072 262144
net.ipv4.udp_mem = 65536 131072 262144
net.ipv4.tcp_rmem = 8192 262144 8388608
net.ipv4.tcp_wmem = 8192 262144 8388608
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# TCP Optimization
net.ipv4.tcp_congestion_control = cubic
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = -2
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_base_mss = 1024
net.ipv4.tcp_min_snd_mss = 536
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_frto = 2
net.ipv4.tcp_early_retrans = 1
net.ipv4.tcp_recovery = 1
net.ipv4.tcp_thin_linear_timeouts = 1
net.ipv4.tcp_thin_dpio = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_fin_timeout = 15

# TCP Keepalive Settings
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_probes = 4
net.ipv4.tcp_keepalive_intvl = 15

# TCP Backlog Settings
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_max_orphans = 32768

# TCP Retry Settings
net.ipv4.tcp_retries1 = 3
net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_orphan_retries = 1
net.ipv4.tcp_abort_on_overflow = 0

# Security Settings
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
EOF

    sysctl -p
    echo -e "${GREEN}✓ sysctl configuration applied${NC}"
}

# Advanced optimization
advanced_optimization() {
    echo -e "${YELLOW}Applying advanced server optimization...${NC}"
    
    cat >> /etc/sysctl.conf << 'EOF'

# Advanced Optimization Settings
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 10
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_tw_buckets = 200000
net.core.default_qdisc = fq_codel
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_base_mss = 1024
net.ipv4.tcp_rmem = 4096 87380 8388608
net.ipv4.tcp_wmem = 4096 16384 8388608
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 33554432
net.core.wmem_default = 33554432
EOF

    sysctl -p
    echo -e "${GREEN}✓ Advanced optimization applied${NC}"
}

# Change DNS
change_dns() {
    echo -e "${YELLOW}Changing DNS servers...${NC}"
    echo "Select DNS provider:"
    echo "1) Google DNS (8.8.8.8, 8.8.4.4)"
    echo "2) Cloudflare DNS (1.1.1.1, 1.0.0.1)"
    echo "3) OpenDNS (208.67.222.222, 208.67.220.220)"
    echo "4) Custom DNS"
    read -p "Choose option (1-4): " dns_choice
    
    case $dns_choice in
        1)
            echo "nameserver 8.8.8.8" > /etc/resolv.conf
            echo "nameserver 8.8.4.4" >> /etc/resolv.conf
            ;;
        2)
            echo "nameserver 1.1.1.1" > /etc/resolv.conf
            echo "nameserver 1.0.0.1" >> /etc/resolv.conf
            ;;
        3)
            echo "nameserver 208.67.222.222" > /etc/resolv.conf
            echo "nameserver 208.67.220.220" >> /etc/resolv.conf
            ;;
        4)
            read -p "Enter primary DNS: " dns1
            read -p "Enter secondary DNS: " dns2
            echo "nameserver $dns1" > /etc/resolv.conf
            echo "nameserver $dns2" >> /etc/resolv.conf
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            return
            ;;
    esac
    
    # Make permanent
    if [[ -f /etc/resolvconf/resolv.conf.d/head ]]; then
        cat /etc/resolv.conf > /etc/resolvconf/resolv.conf.d/head
        resolvconf -u
    fi
    
    echo -e "${GREEN}✓ DNS changed successfully${NC}"
}

# Change MTU
change_mtu() {
    echo -e "${YELLOW}Changing MTU...${NC}"
    IF=$(get_interface)
    if [[ -n "$IF" ]]; then
        read -p "Enter MTU value (default: 1500): " mtu_value
        mtu_value=${mtu_value:-1500}
        
        ip link set dev $IF mtu $mtu_value
        echo -e "${GREEN}✓ MTU changed to $mtu_value on $IF${NC}"
        
        # Make permanent
        if ! grep -q "ip link set dev $IF mtu" /etc/rc.local; then
            sed -i '/exit 0/d' /etc/rc.local 2>/dev/null
            echo "ip link set dev $IF mtu $mtu_value" >> /etc/rc.local
            echo "exit 0" >> /etc/rc.local
            chmod +x /etc/rc.local
        fi
    else
        echo -e "${RED}Failed to detect network interface${NC}"
    fi
}

# Uninstall all changes
uninstall_changes() {
    echo -e "${YELLOW}Uninstalling all changes...${NC}"
    
    # Restore sysctl
    restore_backups
    
    # Reset network interface
    IF=$(get_interface)
    if [[ -n "$IF" ]]; then
        tc qdisc del dev $IF root 2>/dev/null
        ethtool -K $IF tso on gso on gro on 2>/dev/null
        ip link set dev $IF txqueuelen 1000
    fi
    
    # Remove rc.local entries
    if [[ -f /etc/rc.local ]]; then
        > /etc/rc.local
        echo "#!/bin/bash" > /etc/rc.local
        echo "exit 0" >> /etc/rc.local
    fi
    
    # Disable irqbalance
    systemctl stop irqbalance
    systemctl disable irqbalance
    
    echo -e "${GREEN}✓ All changes uninstalled${NC}"
    echo -e "${YELLOW}Reboot recommended for complete reset${NC}"
}

# Full installation
full_installation() {
    echo -e "${BLUE}Starting full optimization installation...${NC}"
    backup_files
    install_prerequisites
    step1
    step2
    step3
    step4
    step5
    step6
    advanced_optimization
    echo -e "${GREEN}✓ Full optimization completed successfully${NC}"
}

# Main menu
while true; do
    clear
    echo -e "${BLUE}================================${NC}"
    echo -e "${GREEN}    Server Optimization Script    ${NC}"
    echo -e "${BLUE}================================${NC}"
    echo -e "${YELLOW}Available options:${NC}"
    echo -e "${GREEN}1)${NC} Full installation (all optimizations)"
    echo -e "${GREEN}2)${NC} Uninstall all changes"
    echo -e "${GREEN}3)${NC} Reboot server"
    echo -e "${GREEN}4)${NC} Change DNS"
    echo -e "${GREEN}5)${NC} Change MTU"
    echo -e "${GREEN}6)${NC} Advanced optimization only"
    echo -e "${GREEN}7)${NC} Exit"
    echo -e "${BLUE}================================${NC}"
    
    read -p "Choose an option (1-7): " choice
    
    case $choice in
        1)
            full_installation
            read -p "Press Enter to continue..."
            ;;
        2)
            uninstall_changes
            read -p "Press Enter to continue..."
            ;;
        3)
            echo -e "${YELLOW}Rebooting server...${NC}"
            reboot
            ;;
        4)
            change_dns
            read -p "Press Enter to continue..."
            ;;
        5)
            change_mtu
            read -p "Press Enter to continue..."
            ;;
        6)
            backup_files
            advanced_optimization
            read -p "Press Enter to continue..."
            ;;
        7)
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            read -p "Press Enter to continue..."
            ;;
    esac
done
