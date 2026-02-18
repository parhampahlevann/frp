#!/bin/bash

# ==============================================
# Traffic Load Balancer with Failover
# Between Iran Server and Two Foreign Servers
# Version: 1.0
# ==============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration files
CONFIG_DIR="/etc/traffic-balancer"
CONFIG_FILE="$CONFIG_DIR/config.conf"
SERVICE_FILE="/etc/systemd/system/traffic-balancer.service"
TUN_IFACE="tun0"

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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Install required packages
install_dependencies() {
    print_info "Installing required packages..."
    
    # Update package list
    apt-get update -qq
    
    # Install necessary packages
    apt-get install -y \
        iptables \
        iproute2 \
        net-tools \
        wget \
        curl \
        openvpn \
        wireguard \
        resolvconf \
        keepalived \
        nftables \
        fail2ban \
        -qq
    
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
        print_success "Configuration directory created: $CONFIG_DIR"
    fi
}

# Get foreign server IPs
get_foreign_servers() {
    echo ""
    print_info "=== Foreign Servers Configuration ==="
    echo ""
    
    read -p "How many foreign servers do you have? (1-5): " SERVER_COUNT
    
    if [[ ! "$SERVER_COUNT" =~ ^[1-5]$ ]]; then
        print_error "Invalid number. Please enter a number between 1 and 5"
        exit 1
    fi
    
    # Create array for server IPs
    SERVER_IPS=()
    
    for ((i=1; i<=SERVER_COUNT; i++)); do
        echo ""
        read -p "Enter IPv4 address for Foreign Server #$i: " SERVER_IP
        
        # Validate IP format
        if [[ ! "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            print_error "Invalid IP address format"
            exit 1
        fi
        
        SERVER_IPS+=("$SERVER_IP")
    done
    
    # Save configuration
    echo "SERVER_COUNT=$SERVER_COUNT" > "$CONFIG_FILE"
    for ((i=0; i<${#SERVER_IPS[@]}; i++)); do
        echo "SERVER_$((i+1))=${SERVER_IPS[$i]}" >> "$CONFIG_FILE"
    done
    
    print_success "Server configuration saved"
}

# Setup routing tables
setup_routing() {
    print_info "Setting up routing tables..."
    
    # Create routing tables for each foreign server
    for ((i=1; i<=SERVER_COUNT; i++)); do
        echo "200 table$i" >> /etc/iproute2/rt_tables 2>/dev/null
    done
    
    # Enable IP forwarding
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    
    # Apply sysctl settings
    sysctl -p > /dev/null 2>&1
    
    print_success "Routing tables configured"
}

# Create health check script
create_health_check() {
    cat > "$CONFIG_DIR/health_check.sh" << 'EOF'
#!/bin/bash

CONFIG_FILE="/etc/traffic-balancer/config.conf"
ACTIVE_SERVER=1

source $CONFIG_FILE

check_server() {
    local server_ip=$1
    local server_num=$2
    
    # Ping test
    if ping -c 2 -W 2 $server_ip > /dev/null 2>&1; then
        # TCP port test (common ports)
        if nc -zv -w 3 $server_ip 443 2>/dev/null || \
           nc -zv -w 3 $server_ip 80 2>/dev/null || \
           nc -zv -w 3 $server_ip 22 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

while true; do
    source $CONFIG_FILE
    
    # Check current active server
    CURRENT_ACTIVE=$(cat /etc/traffic-balancer/active_server 2>/dev/null || echo "1")
    
    # Check all servers
    for ((i=1; i<=SERVER_COUNT; i++)); do
        SERVER_VAR="SERVER_$i"
        SERVER_IP=${!SERVER_VAR}
        
        if check_server $SERVER_IP $i; then
            if [ $CURRENT_ACTIVE -ne $i ]; then
                # Switch to this server
                echo $i > /etc/traffic-balancer/active_server
                /etc/traffic-balancer/switch_traffic.sh $i
            fi
            break
        fi
    done
    
    sleep 10
done
EOF

    chmod +x "$CONFIG_DIR/health_check.sh"
    print_success "Health check script created"
}

# Create traffic switch script
create_switch_script() {
    cat > "$CONFIG_DIR/switch_traffic.sh" << 'EOF'
#!/bin/bash

CONFIG_FILE="/etc/traffic-balancer/config.conf"
ACTIVE_SERVER=$1

source $CONFIG_FILE

# Clear existing iptables rules
iptables -t nat -F
iptables -t mangle -F
iptables -F

# Set default policies
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Get active server IP
ACTIVE_IP_VAR="SERVER_$ACTIVE_SERVER"
ACTIVE_IP=${!ACTIVE_IP_VAR}

# Mark packets for routing
iptables -t mangle -A PREROUTING -j CONNMARK --restore-mark
iptables -t mangle -A PREROUTING -m mark ! --mark 0 -j ACCEPT

# Route all traffic through active server
iptables -t nat -A POSTROUTING -o $(ip route show default | awk '{print $5}') -j MASQUERADE

# Create routing rule for marked packets
ip rule add fwmark 1 table 100 2>/dev/null

# Setup routes
ip route add default via $ACTIVE_IP dev $(ip route show default | awk '{print $5}') table 100 2>/dev/null

# Save active server
echo $ACTIVE_SERVER > /etc/traffic-balancer/active_server

echo "Traffic switched to server $ACTIVE_SERVER ($ACTIVE_IP)"
EOF

    chmod +x "$CONFIG_DIR/switch_traffic.sh"
    print_success "Traffic switch script created"
}

# Create systemd service
create_service() {
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Traffic Balancer with Failover
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/bin/bash $CONFIG_DIR/health_check.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    print_success "Systemd service created"
}

# Setup monitoring
setup_monitoring() {
    print_info "Setting up monitoring..."
    
    # Create monitoring script
    cat > "$CONFIG_DIR/monitor.sh" << 'EOF'
#!/bin/bash

while true; do
    ACTIVE_SERVER=$(cat /etc/traffic-balancer/active_server 2>/dev/null || echo "None")
    echo "$(date): Active Server: $ACTIVE_SERVER" >> /var/log/traffic-balancer.log
    
    # Check bandwidth usage
    if command -v ifstat &> /dev/null; then
        ifstat -t 1 1 >> /var/log/traffic-balancer-bandwidth.log 2>/dev/null
    fi
    
    sleep 60
done
EOF

    chmod +x "$CONFIG_DIR/monitor.sh"
    
    # Create monitoring service
    cat > "/etc/systemd/system/traffic-monitor.service" << EOF
[Unit]
Description=Traffic Balancer Monitor
After=network.target

[Service]
Type=simple
User=root
ExecStart=/bin/bash $CONFIG_DIR/monitor.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    print_success "Monitoring setup completed"
}

# Setup fail2ban protection
setup_security() {
    print_info "Setting up security measures..."
    
    # Configure fail2ban for SSH
    cat > "/etc/fail2ban/jail.local" << EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

    systemctl restart fail2ban
    
    # Basic firewall rules
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -j DROP
    
    print_success "Security measures applied"
}

# Install the balancer
install_balancer() {
    print_message "=== Installing Traffic Balancer ==="
    echo ""
    
    check_root
    install_dependencies
    setup_config_dir
    get_foreign_servers
    setup_routing
    create_health_check
    create_switch_script
    create_service
    setup_monitoring
    setup_security
    
    # Start services
    systemctl daemon-reload
    systemctl enable traffic-balancer.service
    systemctl start traffic-balancer.service
    systemctl enable traffic-monitor.service
    systemctl start traffic-monitor.service
    
    # Set initial active server
    echo "1" > "$CONFIG_DIR/active_server"
    
    print_success "=== Installation Complete ==="
    echo ""
    print_info "Active server: 1 (${SERVER_IPS[0]})"
    print_info "To check status: systemctl status traffic-balancer"
    print_info "To view logs: tail -f /var/log/traffic-balancer.log"
    print_info "To switch manually: /etc/traffic-balancer/switch_traffic.sh [server_number]"
}

# Uninstall the balancer
uninstall_balancer() {
    print_message "=== Uninstalling Traffic Balancer ==="
    echo ""
    
    # Stop services
    systemctl stop traffic-balancer.service
    systemctl stop traffic-monitor.service
    systemctl disable traffic-balancer.service
    systemctl disable traffic-monitor.service
    
    # Remove files
    rm -rf "$CONFIG_DIR"
    rm -f "$SERVICE_FILE"
    rm -f "/etc/systemd/system/traffic-monitor.service"
    
    # Clear iptables rules
    iptables -t nat -F
    iptables -t mangle -F
    iptables -F
    
    # Remove routing tables
    sed -i '/200 table/d' /etc/iproute2/rt_tables 2>/dev/null
    
    systemctl daemon-reload
    
    print_success "Uninstallation complete"
}

# Show status
show_status() {
    print_message "=== Traffic Balancer Status ==="
    echo ""
    
    if [ -f "$CONFIG_DIR/active_server" ]; then
        ACTIVE=$(cat "$CONFIG_DIR/active_server")
        source "$CONFIG_FILE" 2>/dev/null
        ACTIVE_IP_VAR="SERVER_$ACTIVE"
        ACTIVE_IP=${!ACTIVE_IP_VAR}
        print_info "Active Server: $ACTIVE ($ACTIVE_IP)"
    else
        print_info "Active Server: Not configured"
    fi
    
    echo ""
    systemctl status traffic-balancer.service --no-pager
    echo ""
    print_info "Recent logs:"
    tail -5 /var/log/traffic-balancer.log 2>/dev/null || echo "No logs available"
}

# Main menu
show_menu() {
    echo ""
    print_message "=== Traffic Balancer Management ==="
    echo ""
    echo "1) Install Traffic Balancer"
    echo "2) Uninstall Traffic Balancer"
    echo "3) Show Status"
    echo "4) Manual Switch Server"
    echo "5) Exit"
    echo ""
    read -p "Select an option [1-5]: " OPTION
    
    case $OPTION in
        1)
            install_balancer
            ;;
        2)
            uninstall_balancer
            ;;
        3)
            show_status
            ;;
        4)
            if [ -f "$CONFIG_FILE" ]; then
                source "$CONFIG_FILE"
                echo "Available servers:"
                for ((i=1; i<=SERVER_COUNT; i++)); do
                    SERVER_VAR="SERVER_$i"
                    echo "$i) ${!SERVER_VAR}"
                done
                read -p "Select server number to switch to: " SWITCH_TO
                if [[ "$SWITCH_TO" =~ ^[1-$SERVER_COUNT]$ ]]; then
                    $CONFIG_DIR/switch_traffic.sh $SWITCH_TO
                else
                    print_error "Invalid selection"
                fi
            else
                print_error "Not configured yet. Please install first."
            fi
            ;;
        5)
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
    # Check if menu should be shown
    if [ "$1" == "--menu" ] || [ $# -eq 0 ]; then
        while true; do
            show_menu
            echo ""
            read -p "Press Enter to continue..."
        done
    else
        # Command line arguments
        case $1 in
            install)
                install_balancer
                ;;
            uninstall)
                uninstall_balancer
                ;;
            status)
                show_status
                ;;
            switch)
                if [ -n "$2" ] && [ -f "$CONFIG_FILE" ]; then
                    source "$CONFIG_FILE"
                    if [[ "$2" =~ ^[1-$SERVER_COUNT]$ ]]; then
                        $CONFIG_DIR/switch_traffic.sh $2
                    else
                        print_error "Invalid server number"
                    fi
                else
                    print_error "Invalid command or not configured"
                fi
                ;;
            *)
                echo "Usage: $0 [--menu|install|uninstall|status|switch <server_num>]"
                ;;
        esac
    fi
}

# Run main function with arguments
main "$@"
