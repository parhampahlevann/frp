#!/bin/bash

# ==============================================
# Advanced Dual Foreign Servers Connection
# با اتصال همزمان دو سرور خارجی به ایران
# Version: 2.0 - Dual Active Connection
# ==============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration files
CONFIG_DIR="/etc/dual-traffic-balancer"
CONFIG_FILE="$CONFIG_DIR/config.conf"
TUN_IFACE1="tun1"
TUN_IFACE2="tun2"
BOND_IFACE="bond0"

# Print colored output
print_message() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_section() {
    echo -e "${CYAN}════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Install required packages
install_dependencies() {
    print_info "Installing required packages for dual connection..."
    
    apt-get update -qq
    apt-get install -y \
        iptables \
        iproute2 \
        net-tools \
        openvpn \
        wireguard \
        strongswan \
        keepalived \
        nftables \
        fail2ban \
        ifenslave \
        bonding \
        mtr \
        tcptrack \
        iftop \
        nload \
        htop \
        -qq
    
    # Load bonding module
    modprobe bonding
    echo "bonding" >> /etc/modules
    
    if [ $? -eq 0 ]; then
        print_success "Dependencies installed successfully"
    else
        print_error "Failed to install dependencies"
        exit 1
    fi
}

# Create configuration directory
setup_config_dir() {
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        mkdir -p "$CONFIG_DIR/scripts"
        mkdir -p "$CONFIG_DIR/backup"
        mkdir -p "$CONFIG_DIR/logs"
        print_success "Configuration directories created"
    fi
}

# Get server information
get_servers_info() {
    print_section "Foreign Servers Configuration"
    
    echo ""
    print_info "برای اتصال همزمان دو سرور خارجی، اطلاعات زیر را وارد کنید:"
    echo ""
    
    # Server 1
    read -p "Enter IPv4 address for Foreign Server #1: " SERVER1_IP
    if [[ ! "$SERVER1_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_error "Invalid IP address format"
        exit 1
    fi
    
    read -p "Enter SSH Port for Server #1 (default 22): " SERVER1_PORT
    SERVER1_PORT=${SERVER1_PORT:-22}
    
    read -p "Enter username for Server #1 (default root): " SERVER1_USER
    SERVER1_USER=${SERVER1_USER:-root}
    
    # Server 2
    echo ""
    read -p "Enter IPv4 address for Foreign Server #2: " SERVER2_IP
    if [[ ! "$SERVER2_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_error "Invalid IP address format"
        exit 1
    fi
    
    read -p "Enter SSH Port for Server #2 (default 22): " SERVER2_PORT
    SERVER2_PORT=${SERVER2_PORT:-22}
    
    read -p "Enter username for Server #2 (default root): " SERVER2_USER
    SERVER2_USER=${SERVER2_USER:-root}
    
    # Load balancing method
    echo ""
    print_info "Select load balancing method:"
    echo "1) Round-Robin (تقسیم مساوی ترافیک)"
    echo "2) Active-Backup (یک فعال، یک آماده به کار)"
    echo "3) Balance-xor (بر اساس آدرس مبدا و مقصد)"
    echo "4) Broadcast (همزمان به هر دو)"
    read -p "Select method [1-4] (default 1): " LB_METHOD
    LB_METHOD=${LB_METHOD:-1}
    
    case $LB_METHOD in
        1) BOND_MODE="balance-rr" ;;
        2) BOND_MODE="active-backup" ;;
        3) BOND_MODE="balance-xor" ;;
        4) BOND_MODE="broadcast" ;;
        *) BOND_MODE="balance-rr" ;;
    esac
    
    # Save configuration
    cat > "$CONFIG_FILE" << EOF
# Dual Server Connection Configuration
SERVER1_IP="$SERVER1_IP"
SERVER1_PORT="$SERVER1_PORT"
SERVER1_USER="$SERVER1_USER"
SERVER2_IP="$SERVER2_IP"
SERVER2_PORT="$SERVER2_PORT"
SERVER2_USER="$SERVER2_USER"
BOND_MODE="$BOND_MODE"
LB_METHOD="$LB_METHOD"
CREATED_DATE="$(date)"
EOF
    
    print_success "Server configuration saved"
}

# Setup WireGuard tunnels
setup_wireguard_tunnels() {
    print_info "Setting up WireGuard tunnels to both servers..."
    
    # Install WireGuard if not present
    apt-get install -y wireguard resolvconf -qq
    
    # Generate keys for both connections
    wg genkey | tee "$CONFIG_DIR/privatekey1" | wg pubkey > "$CONFIG_DIR/publickey1"
    wg genkey | tee "$CONFIG_DIR/privatekey2" | wg pubkey > "$CONFIG_DIR/publickey2"
    
    # Create WireGuard configuration for Server 1
    cat > "$CONFIG_DIR/wg1.conf" << EOF
[Interface]
PrivateKey = $(cat "$CONFIG_DIR/privatekey1")
Address = 10.10.1.1/30
ListenPort = 51821
MTU = 1420

# Save configuration
PostUp = iptables -A FORWARD -i wg1 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg1 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = $(cat "$CONFIG_DIR/publickey1")  # Will be replaced with server's public key
AllowedIPs = 10.10.1.2/32
PersistentKeepalive = 25
EOF

    # Create WireGuard configuration for Server 2
    cat > "$CONFIG_DIR/wg2.conf" << EOF
[Interface]
PrivateKey = $(cat "$CONFIG_DIR/privatekey2")
Address = 10.10.2.1/30
ListenPort = 51822
MTU = 1420

# Save configuration
PostUp = iptables -A FORWARD -i wg2 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg2 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = $(cat "$CONFIG_DIR/publickey2")  # Will be replaced with server's public key
AllowedIPs = 10.10.2.2/32
PersistentKeepalive = 25
EOF

    print_success "WireGuard configurations created"
}

# Setup bonding interface
setup_bonding() {
    print_info "Setting up bonding interface for both connections..."
    
    # Create bonding interface configuration
    cat > "/etc/network/interfaces.d/bond0" << EOF
# Bonding interface for dual servers
auto $BOND_IFACE
iface $BOND_IFACE inet static
    address 10.10.10.1/24
    bond-slaves none
    bond-mode $BOND_MODE
    bond-miimon 100
    bond-downdelay 200
    bond-updelay 200
    bond-lacp-rate fast
    bond-xmit-hash-policy layer3+4
    
    # Post-up scripts
    post-up ip route add default via 10.10.10.254 dev $BOND_IFACE table 100
    post-up ip rule add from 10.10.10.1/32 table 100
    post-up ip rule add fwmark 0x100 table 100
    
    # Load balancing rules
    post-up iptables -t mangle -A PREROUTING -i $BOND_IFACE -j CONNMARK --restore-mark
    post-up iptables -t mangle -A PREROUTING -m mark ! --mark 0 -j ACCEPT
    post-up iptables -t mangle -A PREROUTING -j CONNMARK --save-mark
EOF

    # Load bonding module with specific options
    modprobe bonding mode=$BOND_MODE miimon=100 downdelay=200 updelay=200
    
    print_success "Bonding interface configured in mode: $BOND_MODE"
}

# Create smart routing script
create_smart_routing() {
    cat > "$CONFIG_DIR/scripts/smart_routing.sh" << 'EOF'
#!/bin/bash

CONFIG_FILE="/etc/dual-traffic-balancer/config.conf"
source $CONFIG_FILE

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to check connection quality
check_connection_quality() {
    local server_ip=$1
    local interface=$2
    
    # Check latency
    local latency=$(ping -c 3 -W 2 -I $interface $server_ip 2>/dev/null | tail -1 | awk '{print $4}' | cut -d '/' -f 2)
    
    # Check packet loss
    local loss=$(ping -c 10 -W 1 -I $interface $server_ip 2>/dev/null | grep -oP '\d+(?=% packet loss)')
    
    # Check bandwidth (simple test)
    local bandwidth=$(timeout 2 iperf3 -c $server_ip -B $interface -P 2 2>/dev/null | grep -oP '\d+(?= Mbits/sec)' | head -1)
    
    echo "$latency|$loss|$bandwidth"
}

# Dynamic routing based on connection quality
while true; do
    echo "$(date): Checking connection qualities..." >> /var/log/dual-balancer-quality.log
    
    # Check Server 1 quality
    QUAL1=$(check_connection_quality "$SERVER1_IP" "wg1")
    LAT1=$(echo $QUAL1 | cut -d'|' -f1)
    LOSS1=$(echo $QUAL1 | cut -d'|' -f2)
    BW1=$(echo $QUAL1 | cut -d'|' -f3)
    
    # Check Server 2 quality
    QUAL2=$(check_connection_quality "$SERVER2_IP" "wg2")
    LAT2=$(echo $QUAL2 | cut -d'|' -f1)
    LOSS2=$(echo $QUAL2 | cut -d'|' -f2)
    BW2=$(echo $QUAL2 | cut -d'|' -f3)
    
    # Dynamic weight calculation
    if [ ! -z "$LAT1" ] && [ ! -z "$LAT2" ]; then
        # Calculate weights based on latency and packet loss
        WEIGHT1=$(echo "scale=2; (100 / $LAT1) * (100 - ${LOSS1:-0})" | bc 2>/dev/null)
        WEIGHT2=$(echo "scale=2; (100 / $LAT2) * (100 - ${LOSS2:-0})" | bc 2>/dev/null)
        
        # Normalize weights
        TOTAL=$(echo "$WEIGHT1 + $WEIGHT2" | bc)
        if [ $(echo "$TOTAL > 0" | bc) -eq 1 ]; then
            PERCENT1=$(echo "scale=2; ($WEIGHT1 / $TOTAL) * 100" | bc)
            PERCENT2=$(echo "scale=2; ($WEIGHT2 / $TOTAL) * 100" | bc)
            
            echo "Server1: ${PERCENT1}% | Server2: ${PERCENT2}%" >> /var/log/dual-balancer-quality.log
            
            # Apply dynamic routing
            iptables -t mangle -F PREROUTING
            iptables -t mangle -A PREROUTING -m statistic --mode random --probability $(echo "scale=2; $PERCENT1/100" | bc) -j MARK --set-mark 1
            iptables -t mangle -A PREROUTING -j MARK --set-mark 2
        fi
    fi
    
    sleep 30
done
EOF

    chmod +x "$CONFIG_DIR/scripts/smart_routing.sh"
    print_success "Smart routing script created"
}

# Create load balancing rules
create_lb_rules() {
    print_info "Creating load balancing rules..."
    
    # Create routing tables
    echo "201 wg1.route" >> /etc/iproute2/rt_tables 2>/dev/null
    echo "202 wg2.route" >> /etc/iproute2/rt_tables 2>/dev/null
    
    # Create load balancing script
    cat > "$CONFIG_DIR/scripts/lb_rules.sh" << 'EOF'
#!/bin/bash

CONFIG_FILE="/etc/dual-traffic-balancer/config.conf"
source $CONFIG_FILE

# Clear existing rules
ip rule flush
ip route flush table wg1.route
ip route flush table wg2.route

# Add routes for each connection
ip route add default dev wg1 table wg1.route
ip route add default dev wg2 table wg2.route

# Add rules for load balancing
ip rule add from 10.10.1.0/30 table wg1.route priority 100
ip rule add from 10.10.2.0/30 table wg2.route priority 200

# Mark-based routing for load balancing
iptables -t mangle -F
iptables -t mangle -A PREROUTING -j CONNMARK --restore-mark

# Round-robin load balancing for new connections
iptables -t mangle -A PREROUTING -m mark ! --mark 0 -j ACCEPT
iptables -t mangle -A PREROUTING -m state --state NEW -m statistic --mode nth --every 2 --packet 0 -j MARK --set-mark 1
iptables -t mangle -A PREROUTING -m state --state NEW -j MARK --set-mark 2

# Save marks to connection
iptables -t mangle -A PREROUTING -j CONNMARK --save-mark

# Masquerade for both interfaces
iptables -t nat -A POSTROUTING -o wg1 -j MASQUERADE
iptables -t nat -A POSTROUTING -o wg2 -j MASQUERADE

# Enable forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv4/conf/all/forwarding

print_success "Load balancing rules applied"
EOF

    chmod +x "$CONFIG_DIR/scripts/lb_rules.sh"
    print_success "Load balancing rules created"
}

# Create connection monitoring
create_monitoring() {
    cat > "$CONFIG_DIR/scripts/monitor.sh" << 'EOF'
#!/bin/bash

CONFIG_FILE="/etc/dual-traffic-balancer/config.conf"
LOG_FILE="/etc/dual-traffic-balancer/logs/connection.log"
source $CONFIG_FILE

monitor_connection() {
    local server_ip=$1
    local interface=$2
    local name=$3
    
    # Check if interface is up
    if ip link show $interface > /dev/null 2>&1; then
        # Check ping
        if ping -c 2 -W 2 -I $interface $server_ip > /dev/null 2>&1; then
            # Get traffic stats
            RX_BYTES=$(cat /sys/class/net/$interface/statistics/rx_bytes)
            TX_BYTES=$(cat /sys/class/net/$interface/statistics/tx_bytes)
            RX_PACKETS=$(cat /sys/class/net/$interface/statistics/rx_packets)
            TX_PACKETS=$(cat /sys/class/net/$interface/statistics/tx_packets)
            
            echo "$(date): $name - UP - RX: $RX_BYTES bytes, TX: $TX_BYTES bytes" >> $LOG_FILE
            return 0
        else
            echo "$(date): $name - DOWN (ping failed)" >> $LOG_FILE
            return 1
        fi
    else
        echo "$(date): $name - DOWN (interface down)" >> $LOG_FILE
        return 1
    fi
}

while true; do
    # Monitor both connections
    monitor_connection "$SERVER1_IP" "wg1" "Server1"
    monitor_connection "$SERVER2_IP" "wg2" "Server2"
    
    # Show traffic summary
    clear
    echo "════════════════════════════════════════════"
    echo "   Dual Connection Status - $(date)"
    echo "════════════════════════════════════════════"
    echo ""
    
    # Show bandwidth for both interfaces
    if command -v ifstat &> /dev/null; then
        ifstat -i wg1,wg2 1 1
    fi
    
    echo ""
    echo "Connection details:"
    ip -br addr show wg1 2>/dev/null || echo "wg1: Not connected"
    ip -br addr show wg2 2>/dev/null || echo "wg2: Not connected"
    
    echo ""
    echo "Load balancing stats:"
    iptables -t mangle -L PREROUTING -v -n 2>/dev/null | head -10
    
    sleep 5
done
EOF

    chmod +x "$CONFIG_DIR/scripts/monitor.sh"
    print_success "Monitoring script created"
}

# Create systemd services
create_services() {
    # Main service
    cat > "/etc/systemd/system/dual-balancer.service" << EOF
[Unit]
Description=Dual Foreign Servers Connection Service
After=network.target network-online.target
Wants=network.target network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$CONFIG_DIR/scripts/lb_rules.sh
ExecStartPost=/bin/bash -c 'ip link set wg1 up && ip link set wg2 up'
ExecStop=/bin/bash -c 'ip link set wg1 down && ip link set wg2 down'
ExecStopPost=/sbin/iptables -t mangle -F
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF

    # WireGuard services
    cat > "/etc/systemd/system/wg-quick@wg1.service" << 'EOF'
[Unit]
Description=WireGuard for Server 1
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/wg-quick up wg1
ExecStop=/usr/bin/wg-quick down wg1

[Install]
WantedBy=multi-user.target
EOF

    cat > "/etc/systemd/system/wg-quick@wg2.service" << 'EOF'
[Unit]
Description=WireGuard for Server 2
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/wg-quick up wg2
ExecStop=/usr/bin/wg-quick down wg2

[Install]
WantedBy=multi-user.target
EOF

    # Smart routing service
    cat > "/etc/systemd/system/smart-routing.service" << EOF
[Unit]
Description=Smart Routing for Dual Connections
After=dual-balancer.service

[Service]
Type=simple
ExecStart=$CONFIG_DIR/scripts/smart_routing.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    print_success "Systemd services created"
}

# Setup auto-reconnect
setup_auto_reconnect() {
    cat > "$CONFIG_DIR/scripts/auto_reconnect.sh" << 'EOF'
#!/bin/bash

CONFIG_FILE="/etc/dual-traffic-balancer/config.conf"
source $CONFIG_FILE

reconnect_server() {
    local server_num=$1
    local interface="wg$server_num"
    
    print_info "Attempting to reconnect Server $server_num..."
    
    # Bring interface down
    ip link set $interface down
    
    # Wait a bit
    sleep 5
    
    # Bring interface up
    ip link set $interface up
    
    # Wait for connection
    sleep 3
    
    # Check if reconnected
    if ip link show $interface | grep -q "UP"; then
        print_success "Server $server_num reconnected successfully"
        return 0
    else
        print_error "Failed to reconnect Server $server_num"
        return 1
    fi
}

while true; do
    # Check Server 1
    if ! ping -c 1 -W 2 -I wg1 $SERVER1_IP > /dev/null 2>&1; then
        reconnect_server 1
    fi
    
    # Check Server 2
    if ! ping -c 1 -W 2 -I wg2 $SERVER2_IP > /dev/null 2>&1; then
        reconnect_server 2
    fi
    
    sleep 30
done
EOF

    chmod +x "$CONFIG_DIR/scripts/auto_reconnect.sh"
    
    # Create service for auto-reconnect
    cat > "/etc/systemd/system/auto-reconnect.service" << EOF
[Unit]
Description=Auto Reconnect Service for Dual Connections
After=dual-balancer.service

[Service]
Type=simple
ExecStart=$CONFIG_DIR/scripts/auto_reconnect.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    print_success "Auto-reconnect configured"
}

# Setup failover and health checks
setup_failover() {
    cat > "$CONFIG_DIR/scripts/failover.sh" << 'EOF'
#!/bin/bash

CONFIG_FILE="/etc/dual-traffic-balancer/config.conf"
source $CONFIG_FILE

check_server_health() {
    local server_ip=$1
    local interface=$2
    
    # Multiple checks for better accuracy
    if ping -c 3 -W 1 -I $interface $server_ip > /dev/null 2>&1; then
        # Check if interface is receiving traffic
        RX_BEFORE=$(cat /sys/class/net/$interface/statistics/rx_bytes)
        sleep 2
        RX_AFTER=$(cat /sys/class/net/$interface/statistics/rx_bytes)
        
        if [ $RX_AFTER -gt $RX_BEFORE ]; then
            return 0  # Healthy
        else
            return 1  # No traffic
        fi
    else
        return 2  # Unreachable
    fi
}

while true; do
    # Check Server 1 health
    check_server_health "$SERVER1_IP" "wg1"
    HEALTH1=$?
    
    # Check Server 2 health
    check_server_health "$SERVER2_IP" "wg2"
    HEALTH2=$?
    
    case $HEALTH1 in
        0) STATUS1="HEALTHY" ;;
        1) STATUS1="NO_TRAFFIC" ;;
        2) STATUS1="UNREACHABLE" ;;
    esac
    
    case $HEALTH2 in
        0) STATUS2="HEALTHY" ;;
        1) STATUS2="NO_TRAFFIC" ;;
        2) STATUS2="UNREACHABLE" ;;
    esac
    
    echo "$(date): Server1: $STATUS1 | Server2: $STATUS2" >> /var/log/dual-balancer-failover.log
    
    # If both are healthy, keep load balancing
    # If one fails, redirect all traffic to the healthy one
    if [ $HEALTH1 -ne 0 ] && [ $HEALTH2 -eq 0 ]; then
        print_info "Server1 failed, redirecting all traffic to Server2"
        iptables -t mangle -F PREROUTING
        iptables -t mangle -A PREROUTING -j MARK --set-mark 2
    elif [ $HEALTH2 -ne 0 ] && [ $HEALTH1 -eq 0 ]; then
        print_info "Server2 failed, redirecting all traffic to Server1"
        iptables -t mangle -F PREROUTING
        iptables -t mangle -A PREROUTING -j MARK --set-mark 1
    elif [ $HEALTH1 -eq 0 ] && [ $HEALTH2 -eq 0 ]; then
        # Both healthy - restore load balancing
        $CONFIG_DIR/scripts/lb_rules.sh
    fi
    
    sleep 10
done
EOF

    chmod +x "$CONFIG_DIR/scripts/failover.sh"
    
    # Create failover service
    cat > "/etc/systemd/system/dual-failover.service" << EOF
[Unit]
Description=Failover Service for Dual Connections
After=dual-balancer.service

[Service]
Type=simple
ExecStart=$CONFIG_DIR/scripts/failover.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    print_success "Failover system configured"
}

# Install the dual connection system
install_dual_system() {
    print_section "Installing Dual Server Connection System"
    
    check_root
    install_dependencies
    setup_config_dir
    get_servers_info
    setup_wireguard_tunnels
    setup_bonding
    create_smart_routing
    create_lb_rules
    create_monitoring
    create_services
    setup_auto_reconnect
    setup_failover
    
    # Enable all services
    systemctl daemon-reload
    systemctl enable wg-quick@wg1.service
    systemctl enable wg-quick@wg2.service
    systemctl enable dual-balancer.service
    systemctl enable smart-routing.service
    systemctl enable auto-reconnect.service
    systemctl enable dual-failover.service
    
    # Start services
    systemctl start wg-quick@wg1.service
    systemctl start wg-quick@wg2.service
    systemctl start dual-balancer.service
    systemctl start smart-routing.service
    systemctl start auto-reconnect.service
    systemctl start dual-failover.service
    
    print_success "=== Installation Complete ==="
    echo ""
    print_info "هر دو سرور خارجی به طور همزمان متصل هستند"
    print_info "نوع Load Balancing: $BOND_MODE"
    echo ""
    print_info "برای مشاهده وضعیت: systemctl status dual-balancer"
    print_info "برای مانیتورینگ لحظه‌ای: $CONFIG_DIR/scripts/monitor.sh"
    print_info "برای مشاهده لاگ‌ها: tail -f /var/log/dual-balancer*.log"
}

# Uninstall the system
uninstall_dual_system() {
    print_section "Uninstalling Dual Server Connection System"
    
    # Stop all services
    systemctl stop dual-failover.service
    systemctl stop auto-reconnect.service
    systemctl stop smart-routing.service
    systemctl stop dual-balancer.service
    systemctl stop wg-quick@wg1.service
    systemctl stop wg-quick@wg2.service
    
    # Disable services
    systemctl disable wg-quick@wg1.service
    systemctl disable wg-quick@wg2.service
    systemctl disable dual-balancer.service
    systemctl disable smart-routing.service
    systemctl disable auto-reconnect.service
    systemctl disable dual-failover.service
    
    # Remove configurations
    rm -rf "$CONFIG_DIR"
    rm -f /etc/systemd/system/dual-*.service
    rm -f /etc/systemd/system/wg-quick@*.service
    rm -f /etc/network/interfaces.d/bond0
    
    # Clear iptables rules
    iptables -t nat -F
    iptables -t mangle -F
    iptables -F
    
    # Remove routing tables
    sed -i '/201 wg1.route/d' /etc/iproute2/rt_tables
    sed -i '/202 wg2.route/d' /etc/iproute2/rt_tables
    
    systemctl daemon-reload
    
    print_success "Uninstallation complete"
}

# Show status
show_status() {
    print_section "Dual Connection Status"
    
    echo ""
    echo "WireGuard Interfaces:"
    echo "────────────────────"
    wg show 2>/dev/null || echo "WireGuard not running"
    
    echo ""
    echo "Interface Status:"
    echo "────────────────"
    ip -br addr show wg1 2>/dev/null || echo "wg1: Not connected"
    ip -br addr show wg2 2>/dev/null || echo "wg2: Not connected"
    
    echo ""
    echo "Load Balancing Rules:"
    echo "────────────────────"
    iptables -t mangle -L PREROUTING -v -n 2>/dev/null | head -20
    
    echo ""
    echo "Traffic Statistics:"
    echo "──────────────────"
    if [ -f /sys/class/net/wg1/statistics/rx_bytes ]; then
        RX1=$(cat /sys/class/net/wg1/statistics/rx_bytes 2>/dev/null || echo "0")
        TX1=$(cat /sys/class/net/wg1/statistics/tx_bytes 2>/dev/null || echo "0")
        RX2=$(cat /sys/class/net/wg2/statistics/rx_bytes 2>/dev/null || echo "0")
        TX2=$(cat /sys/class/net/wg2/statistics/tx_bytes 2>/dev/null || echo "0")
        
        echo "Server 1 - RX: $((RX1/1024/1024)) MB, TX: $((TX1/1024/1024)) MB"
        echo "Server 2 - RX: $((RX2/1024/1024)) MB, TX: $((TX2/1024/1024)) MB"
    fi
    
    echo ""
    echo "Service Status:"
    echo "──────────────"
    systemctl is-active dual-balancer.service --quiet && echo "dual-balancer: ✅ Active" || echo "dual-balancer: ❌ Inactive"
    systemctl is-active smart-routing.service --quiet && echo "smart-routing: ✅ Active" || echo "smart-routing: ❌ Inactive"
    systemctl is-active dual-failover.service --quiet && echo "dual-failover: ✅ Active" || echo "dual-failover: ❌ Inactive"
}

# Main menu
show_menu() {
    clear
    print_section "Dual Foreign Servers Connection Manager"
    echo ""
    echo -e "${GREEN}1)${NC} Install Dual Connection System"
    echo -e "${GREEN}2)${NC} Uninstall System"
    echo -e "${GREEN}3)${NC} Show Status"
    echo -e "${GREEN}4)${NC} Manual Load Balancing Test"
    echo -e "${GREEN}5)${NC} View Real-time Monitor"
    echo -e "${GREEN}6)${NC} View Connection Logs"
    echo -e "${GREEN}7)${NC} Exit"
    echo ""
    read -p "Select an option [1-7]: " OPTION
    
    case $OPTION in
        1)
            install_dual_system
            ;;
        2)
            uninstall_dual_system
            ;;
        3)
            show_status
            ;;
        4)
            if [ -f "$CONFIG_FILE" ]; then
                echo "Testing load balancing..."
                echo "Sending test traffic..."
                ping -c 10 -I wg1 8.8.8.8 > /dev/null 2>&1 &
                ping -c 10 -I wg2 8.8.8.8 > /dev/null 2>&1 &
                sleep 2
                iptables -t mangle -L PREROUTING -v -n | head -10
            else
                print_error "Not installed yet"
            fi
            ;;
        5)
            if [ -f "$CONFIG_DIR/scripts/monitor.sh" ]; then
                $CONFIG_DIR/scripts/monitor.sh
            else
                print_error "Monitor script not found"
            fi
            ;;
        6)
            if [ -f "/var/log/dual-balancer-quality.log" ]; then
                tail -30 /var/log/dual-balancer-quality.log
            else
                print_error "No logs found"
            fi
            ;;
        7)
            print_message "Exiting..."
            exit 0
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
}

# Main execution
main() {
    if [ "$1" == "--menu" ] || [ $# -eq 0 ]; then
        while true; do
            show_menu
            echo ""
            read -p "Press Enter to continue..."
        done
    else
        case $1 in
            install)
                install_dual_system
                ;;
            uninstall)
                uninstall_dual_system
                ;;
            status)
                show_status
                ;;
            monitor)
                if [ -f "$CONFIG_DIR/scripts/monitor.sh" ]; then
                    $CONFIG_DIR/scripts/monitor.sh
                fi
                ;;
            *)
                echo "Usage: $0 [--menu|install|uninstall|status|monitor]"
                ;;
        esac
    fi
}

main "$@"
