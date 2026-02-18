#!/bin/bash

# ==============================================
# Ultra Simple & Safe Traffic Balancer
# Version: 4.0 - Minimum Risk Version
# ==============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CONFIG_DIR="/root/simple-balancer"
LOG_FILE="/root/simple-balancer/install.log"

# Create log directory
mkdir -p "$CONFIG_DIR"

# Simple logging
log() {
    echo "$(date): $1" >> "$LOG_FILE"
    echo -e "$1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log "[INFO] $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log "[SUCCESS] $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log "[ERROR] $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log "[WARNING] $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Simple system check
simple_check() {
    print_info "Performing basic system check..."
    
    # Check if it's Ubuntu/Debian
    if [ ! -f "/etc/debian_version" ]; then
        print_error "This script only works on Ubuntu/Debian"
        exit 1
    fi
    
    # Check internet connectivity
    if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        print_warning "No internet connection detected"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    print_success "Basic check passed"
}

# Get server IPs (simple version)
get_server_ips() {
    local ips=()
    
    echo
    print_info "Foreign Servers Configuration"
    echo "----------------------------------------"
    
    while true; do
        read -p "How many foreign servers? (1-2): " count
        if [[ "$count" =~ ^[1-2]$ ]]; then
            break
        else
            print_error "Please enter 1 or 2"
        fi
    done
    
    for ((i=1; i<=count; i++)); do
        while true; do
            read -p "Enter IP for Server $i: " ip
            # Simple IP validation
            if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                ips+=("$ip")
                break
            else
                print_error "Invalid IP format"
            fi
        done
    done
    
    # Save IPs to file
    echo "SERVER_COUNT=$count" > "$CONFIG_DIR/servers.conf"
    for ((i=0; i<count; i++)); do
        echo "SERVER_$((i+1))=${ips[$i]}" >> "$CONFIG_DIR/servers.conf"
    done
    
    echo "$count"
    for ip in "${ips[@]}"; do
        echo "$ip"
    done
}

# Install minimal packages
install_minimal() {
    print_info "Installing ONLY essential packages..."
    
    # Update package list (safe mode)
    apt-get update -qq 2>/dev/null
    
    # Install ONLY iproute2 (already installed on most systems)
    if ! command -v ip >/dev/null 2>&1; then
        apt-get install -y -qq iproute2 2>/dev/null
    fi
    
    # Install ping if not available
    if ! command -v ping >/dev/null 2>&1; then
        apt-get install -y -qq iputils-ping 2>/dev/null
    fi
    
    print_success "Package installation completed"
}

# Create simple failover script
create_failover() {
    local count=$1
    shift
    local ips=("$@")
    
    cat > "$CONFIG_DIR/failover.sh" << 'EOF'
#!/bin/bash

CONFIG_DIR="/root/simple-balancer"
ACTIVE_FILE="$CONFIG_DIR/active.txt"
LOG_FILE="$CONFIG_DIR/failover.log"

# Load server configuration
source "$CONFIG_DIR/servers.conf" 2>/dev/null || {
    echo "No configuration found"
    exit 1
}

# Function to check if server is alive
check_server() {
    local ip=$1
    # Simple ping test (1 packet, 1 second timeout)
    ping -c 1 -W 1 "$ip" >/dev/null 2>&1
    return $?
}

# Initialize
if [ ! -f "$ACTIVE_FILE" ]; then
    echo "1" > "$ACTIVE_FILE"
fi

# Main loop
while true; do
    CURRENT=$(cat "$ACTIVE_FILE" 2>/dev/null || echo "1")
    
    # Check current server first
    CURRENT_IP_VAR="SERVER_$CURRENT"
    CURRENT_IP=${!CURRENT_IP_VAR}
    
    if check_server "$CURRENT_IP"; then
        # Current server is working, do nothing
        :
    else
        # Current server failed, try others
        for ((i=1; i<=SERVER_COUNT; i++)); do
            if [ "$i" != "$CURRENT" ]; then
                TEST_IP_VAR="SERVER_$i"
                TEST_IP=${!TEST_IP_VAR}
                
                if check_server "$TEST_IP"; then
                    # Switch to this server
                    echo "$(date): Switching to server $i ($TEST_IP)" >> "$LOG_FILE"
                    echo "$i" > "$ACTIVE_FILE"
                    
                    # Simple route change (add with higher metric, don't remove existing)
                    MAIN_IF=$(ip route show default | awk '{print $5}' | head -1)
                    if [ -n "$MAIN_IF" ]; then
                        # Add new route with metric 100 (lower priority than default)
                        ip route add default via "$TEST_IP" dev "$MAIN_IF" metric 100 2>/dev/null
                    fi
                    break
                fi
            fi
        done
    fi
    
    sleep 10
done
EOF

    chmod +x "$CONFIG_DIR/failover.sh"
    print_success "Failover script created"
}

# Create simple monitor
create_monitor() {
    cat > "$CONFIG_DIR/monitor.sh" << 'EOF'
#!/bin/bash

CONFIG_DIR="/root/simple-balancer"
source "$CONFIG_DIR/servers.conf" 2>/dev/null

while true; do
    clear
    echo "════════════════════════════════════"
    echo "  Simple Balancer Monitor"
    echo "  $(date)"
    echo "════════════════════════════════════"
    
    ACTIVE=$(cat "$CONFIG_DIR/active.txt" 2>/dev/null || echo "None")
    echo "Active Server: $ACTIVE"
    echo
    
    for ((i=1; i<=SERVER_COUNT; i++)); do
        SERVER_VAR="SERVER_$i"
        SERVER_IP=${!SERVER_VAR}
        
        if ping -c 1 -W 1 "$SERVER_IP" >/dev/null 2>&1; then
            echo "Server $i: ✅ UP ($SERVER_IP)"
        else
            echo "Server $i: ❌ DOWN ($SERVER_IP)"
        fi
    done
    
    echo
    echo "Press Ctrl+C to exit"
    sleep 3
done
EOF

    chmod +x "$CONFIG_DIR/monitor.sh"
    print_success "Monitor script created"
}

# Create uninstall script
create_uninstall() {
    cat > "$CONFIG_DIR/uninstall.sh" << 'EOF'
#!/bin/bash

echo "Uninstalling Simple Balancer..."

# Kill any running processes
pkill -f "failover.sh" 2>/dev/null
pkill -f "monitor.sh" 2>/dev/null

# Remove any added routes (only those with metric 100)
ip route show | grep "metric 100" | while read route; do
    ip route del $route 2>/dev/null
done

# Remove configuration directory
rm -rf /root/simple-balancer

echo "Uninstall complete"
EOF

    chmod +x "$CONFIG_DIR/uninstall.sh"
    print_success "Uninstall script created"
}

# Start the balancer
start_balancer() {
    # Kill any existing instance
    pkill -f "failover.sh" 2>/dev/null
    
    # Start in background
    nohup bash "$CONFIG_DIR/failover.sh" >/dev/null 2>&1 &
    
    # Save PID
    echo $! > "$CONFIG_DIR/balancer.pid"
    
    print_success "Balancer started in background"
}

# Main install function
simple_install() {
    echo
    print_info "Starting Simple Installation"
    echo "========================================"
    
    # Step 1: Check root
    check_root
    
    # Step 2: Basic system check
    simple_check
    
    # Step 3: Get server IPs
    result=$(get_server_ips)
    count=$(echo "$result" | head -1)
    ips=($(echo "$result" | tail -n +2))
    
    # Step 4: Install minimal packages
    install_minimal
    
    # Step 5: Create scripts
    create_failover "$count" "${ips[@]}"
    create_monitor
    create_uninstall
    
    # Step 6: Start balancer
    start_balancer
    
    echo
    print_success "════════════════════════════════════════"
    print_success "Installation Completed!"
    print_success "════════════════════════════════════════"
    echo
    echo "Configuration:"
    for ((i=0; i<count; i++)); do
        echo "  Server $((i+1)): ${ips[$i]}"
    done
    echo
    echo "Commands:"
    echo "  Monitor: $CONFIG_DIR/monitor.sh"
    echo "  Uninstall: $CONFIG_DIR/uninstall.sh"
    echo "  Logs: tail -f $CONFIG_DIR/failover.log"
    echo
    print_warning "The balancer is running in background"
}

# Simple uninstall
simple_uninstall() {
    echo
    print_warning "Uninstalling..."
    
    if [ -f "$CONFIG_DIR/uninstall.sh" ]; then
        bash "$CONFIG_DIR/uninstall.sh"
        print_success "Uninstall completed"
    else
        print_error "Uninstall script not found"
    fi
}

# Show status
show_simple_status() {
    echo
    print_info "Current Status"
    echo "========================================"
    
    if [ -f "$CONFIG_DIR/balancer.pid" ]; then
        PID=$(cat "$CONFIG_DIR/balancer.pid" 2>/dev/null)
        if kill -0 $PID 2>/dev/null; then
            echo -e "${GREEN}✓ Balancer is running (PID: $PID)${NC}"
        else
            echo -e "${RED}✗ Balancer is not running${NC}"
        fi
    else
        echo -e "${YELLOW}? Balancer status unknown${NC}"
    fi
    
    if [ -f "$CONFIG_DIR/active.txt" ]; then
        ACTIVE=$(cat "$CONFIG_DIR/active.txt")
        echo "Active server: $ACTIVE"
    fi
    
    if [ -f "$CONFIG_DIR/servers.conf" ]; then
        source "$CONFIG_DIR/servers.conf"
        echo
        echo "Server Status:"
        for ((i=1; i<=SERVER_COUNT; i++)); do
            SERVER_VAR="SERVER_$i"
            SERVER_IP=${!SERVER_VAR}
            if ping -c 1 -W 1 "$SERVER_IP" >/dev/null 2>&1; then
                echo "  Server $i: ${GREEN}Online${NC} ($SERVER_IP)"
            else
                echo "  Server $i: ${RED}Offline${NC} ($SERVER_IP)"
            fi
        done
    fi
}

# Simple menu
show_menu() {
    clear
    echo "════════════════════════════════════════"
    echo "  Simple Safe Balancer v4.0"
    echo "════════════════════════════════════════"
    echo
    echo "1) Install"
    echo "2) Uninstall"
    echo "3) Status"
    echo "4) Monitor"
    echo "5) Exit"
    echo
    read -p "Select option [1-5]: " opt
    
    case $opt in
        1) simple_install ;;
        2) simple_uninstall ;;
        3) show_simple_status ;;
        4) [ -f "$CONFIG_DIR/monitor.sh" ] && bash "$CONFIG_DIR/monitor.sh" || print_error "Not installed" ;;
        5) exit 0 ;;
        *) print_error "Invalid option" ;;
    esac
}

# Main
main() {
    if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
        echo "Usage: $0 [install|uninstall|status|monitor|menu]"
        exit 0
    fi
    
    case $1 in
        install) simple_install ;;
        uninstall) simple_uninstall ;;
        status) show_simple_status ;;
        monitor) [ -f "$CONFIG_DIR/monitor.sh" ] && bash "$CONFIG_DIR/monitor.sh" || print_error "Not installed" ;;
        menu|"") while true; do show_menu; read -p "Press Enter..."; done ;;
        *) echo "Unknown command. Use: $0 --help" ;;
    esac
}

main "$@"
