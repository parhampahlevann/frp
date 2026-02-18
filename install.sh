#!/bin/bash

# ==============================================
# Stable Traffic Balancer - No Disconnection
# Version: 5.0 - Stable Version
# ==============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CONFIG_DIR="/root/stable-balancer"
LOG_FILE="$CONFIG_DIR/balancer.log"
ACTIVE_FILE="$CONFIG_DIR/active.txt"
STATUS_FILE="$CONFIG_DIR/status.txt"

# Create config directory
mkdir -p "$CONFIG_DIR"

# Logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
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

# Check root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Get server information
get_servers() {
    echo
    print_info "Foreign Servers Configuration"
    echo "----------------------------------------"
    
    while true; do
        read -p "Number of foreign servers (1-2): " count
        if [[ "$count" =~ ^[1-2]$ ]]; then
            break
        else
            print_error "Please enter 1 or 2"
        fi
    done
    
    declare -a ips
    declare -a names
    
    for ((i=1; i<=count; i++)); do
        echo
        read -p "Enter name for Server $i (e.g., Germany, Finland): " name
        names[$i]="$name"
        
        while true; do
            read -p "Enter IP for Server $i: " ip
            if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                ips[$i]="$ip"
                break
            else
                print_error "Invalid IP format"
            fi
        done
    done
    
    # Save configuration
    cat > "$CONFIG_DIR/servers.conf" << EOF
# Server Configuration
# Created: $(date)
SERVER_COUNT=$count
EOF
    
    for ((i=1; i<=count; i++)); do
        echo "SERVER_${i}_NAME=\"${names[$i]}\"" >> "$CONFIG_DIR/servers.conf"
        echo "SERVER_${i}_IP=\"${ips[$i]}\"" >> "$CONFIG_DIR/servers.conf"
    done
    
    # Return values
    echo "$count"
    for ((i=1; i<=count; i++)); do
        echo "${names[$i]}"
        echo "${ips[$i]}"
    done
}

# Create stable failover script
create_stable_failover() {
    cat > "$CONFIG_DIR/stable-failover.sh" << 'EOF'
#!/bin/bash

CONFIG_DIR="/root/stable-balancer"
LOG_FILE="$CONFIG_DIR/balancer.log"
ACTIVE_FILE="$CONFIG_DIR/active.txt"
STATUS_FILE="$CONFIG_DIR/status.txt"

# Load configuration
source "$CONFIG_DIR/servers.conf" 2>/dev/null || {
    echo "No configuration found"
    exit 1
}

# Function to log with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to check server health (more reliable)
check_server() {
    local ip=$1
    local name=$2
    
    # Method 1: 3 pings with 2 second timeout (more reliable)
    ping -c 3 -W 2 "$ip" > /dev/null 2>&1
    local ping_result=$?
    
    if [ $ping_result -eq 0 ]; then
        # Method 2: Try to connect to common ports (optional, doesn't block)
        if command -v nc >/dev/null 2>&1; then
            nc -zv -w 2 "$ip" 22 >/dev/null 2>&1 || nc -zv -w 2 "$ip" 443 >/dev/null 2>&1
            return 0
        fi
        return 0
    fi
    
    return 1
}

# Initialize
if [ ! -f "$ACTIVE_FILE" ]; then
    echo "1" > "$ACTIVE_FILE"
    log_message "Initialized with server 1 as active"
fi

# Variables for stability
FAIL_COUNT=0
MAX_FAILS=3
CHECK_INTERVAL=15  # Check every 15 seconds
STABLE_COUNT=0

log_message "Stable failover started with $SERVER_COUNT servers"

while true; do
    CURRENT=$(cat "$ACTIVE_FILE" 2>/dev/null || echo "1")
    
    # Get current server info
    CURRENT_NAME_VAR="SERVER_${CURRENT}_NAME"
    CURRENT_IP_VAR="SERVER_${CURRENT}_IP"
    CURRENT_NAME=${!CURRENT_NAME_VAR}
    CURRENT_IP=${!CURRENT_IP_VAR}
    
    # Check current server
    if check_server "$CURRENT_IP" "$CURRENT_NAME"; then
        # Server is healthy
        FAIL_COUNT=0
        STABLE_COUNT=$((STABLE_COUNT + 1))
        
        # Update status file
        echo "ONLINE|$CURRENT|$CURRENT_NAME|$CURRENT_IP|$(date)" > "$STATUS_FILE"
        
        log_message "Server $CURRENT ($CURRENT_NAME) is healthy (stable for $STABLE_COUNT checks)"
    else
        # Server might be down, increase fail count
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log_message "Server $CURRENT check failed ($FAIL_COUNT/$MAX_FAILS)"
        
        if [ $FAIL_COUNT -ge $MAX_FAILS ]; then
            # Server is considered down, try to switch
            log_message "Server $CURRENT is considered DOWN after $FAIL_COUNT failures"
            
            SWITCHED=0
            for ((i=1; i<=SERVER_COUNT; i++)); do
                if [ "$i" != "$CURRENT" ]; then
                    TEST_NAME_VAR="SERVER_${i}_NAME"
                    TEST_IP_VAR="SERVER_${i}_IP"
                    TEST_NAME=${!TEST_NAME_VAR}
                    TEST_IP=${!TEST_IP_VAR}
                    
                    log_message "Testing alternative server $i ($TEST_NAME)"
                    
                    if check_server "$TEST_IP" "$TEST_NAME"; then
                        # Switch to this server
                        echo "$i" > "$ACTIVE_FILE"
                        log_message "SWITCHED to server $i ($TEST_NAME) - $TEST_IP"
                        
                        # Update main route only if switching
                        MAIN_IF=$(ip route show default | awk '{print $5}' | head -1)
                        if [ -n "$MAIN_IF" ]; then
                            # Remove old route with metric 100 if exists
                            ip route del default via "$CURRENT_IP" dev "$MAIN_IF" metric 100 2>/dev/null
                            # Add new route
                            ip route add default via "$TEST_IP" dev "$MAIN_IF" metric 100 2>/dev/null
                        fi
                        
                        SWITCHED=1
                        FAIL_COUNT=0
                        STABLE_COUNT=0
                        break
                    fi
                fi
            done
            
            if [ $SWITCHED -eq 0 ]; then
                log_message "No alternative servers available"
                # Keep trying current server
                FAIL_COUNT=$((MAX_FAILS - 1))
            fi
        fi
    fi
    
    # Dynamic check interval - check more frequently if unstable
    if [ $STABLE_COUNT -gt 10 ]; then
        CURRENT_INTERVAL=30  # Check every 30 seconds when stable
    else
        CURRENT_INTERVAL=$CHECK_INTERVAL
    fi
    
    sleep $CURRENT_INTERVAL
done
EOF

    chmod +x "$CONFIG_DIR/stable-failover.sh"
    print_success "Stable failover script created"
}

# Create improved monitor
create_improved_monitor() {
    cat > "$CONFIG_DIR/monitor.sh" << 'EOF'
#!/bin/bash

CONFIG_DIR="/root/stable-balancer"
source "$CONFIG_DIR/servers.conf" 2>/dev/null

while true; do
    clear
    echo "══════════════════════════════════════════════"
    echo "  Stable Balancer Monitor - $(date)"
    echo "══════════════════════════════════════════════"
    
    # Show active server
    if [ -f "$ACTIVE_FILE" ]; then
        ACTIVE=$(cat "$ACTIVE_FILE" 2>/dev/null)
        ACTIVE_NAME_VAR="SERVER_${ACTIVE}_NAME"
        ACTIVE_IP_VAR="SERVER_${ACTIVE}_IP"
        ACTIVE_NAME=${!ACTIVE_NAME_VAR}
        ACTIVE_IP=${!ACTIVE_IP_VAR}
        
        echo -e "${GREEN}▶ Active Server: $ACTIVE - $ACTIVE_NAME ($ACTIVE_IP)${NC}"
    else
        echo -e "${YELLOW}▶ No active server${NC}"
    fi
    echo
    
    # Show all servers with detailed status
    echo "Server Status:"
    echo "----------------------------------------"
    
    for ((i=1; i<=SERVER_COUNT; i++)); do
        NAME_VAR="SERVER_${i}_NAME"
        IP_VAR="SERVER_${i}_IP"
        NAME=${!NAME_VAR}
        IP=${!IP_VAR}
        
        # Detailed ping statistics
        PING_RESULT=$(ping -c 2 -W 1 "$IP" 2>/dev/null)
        PING_TIME=$(echo "$PING_RESULT" | tail -1 | awk -F'/' '{print $5}' | cut -d'.' -f1)
        PACKET_LOSS=$(echo "$PING_RESULT" | grep -oP '\d+(?=% packet loss)')
        
        if [ -n "$PACKET_LOSS" ] && [ "$PACKET_LOSS" -lt 100 ]; then
            if [ "$i" -eq "$ACTIVE" ]; then
                echo -e "${GREEN}✓ Server $i: $NAME - ONLINE (Active)${NC}"
            else
                echo -e "${GREEN}✓ Server $i: $NAME - ONLINE${NC}"
            fi
            echo "     IP: $IP | Ping: ${PING_TIME}ms | Loss: ${PACKET_LOSS}%"
        else
            if [ "$i" -eq "$ACTIVE" ]; then
                echo -e "${RED}✗ Server $i: $NAME - OFFLINE (Active - WARNING!)${NC}"
            else
                echo -e "${RED}✗ Server $i: $NAME - OFFLINE${NC}"
            fi
            echo "     IP: $IP | No response"
        fi
    done
    
    # Show last 5 log entries
    echo
    echo "Recent Events:"
    echo "----------------------------------------"
    if [ -f "$LOG_FILE" ]; then
        tail -5 "$LOG_FILE"
    else
        echo "No events logged yet"
    fi
    
    echo
    echo "Press Ctrl+C to exit"
    sleep 5
done
EOF

    chmod +x "$CONFIG_DIR/monitor.sh"
    print_success "Improved monitor created"
}

# Create route management script
create_route_manager() {
    cat > "$CONFIG_DIR/route-manager.sh" << 'EOF'
#!/bin/bash

CONFIG_DIR="/root/stable-balancer"
source "$CONFIG_DIR/servers.conf" 2>/dev/null

case "$1" in
    add)
        SERVER_NUM="$2"
        if [ -n "$SERVER_NUM" ]; then
            IP_VAR="SERVER_${SERVER_NUM}_IP"
            IP=${!IP_VAR}
            MAIN_IF=$(ip route show default | awk '{print $5}' | head -1)
            
            if [ -n "$MAIN_IF" ]; then
                # Remove any existing metric 100 routes
                ip route show | grep "metric 100" | while read route; do
                    ip route del $route 2>/dev/null
                done
                # Add new route
                ip route add default via "$IP" dev "$MAIN_IF" metric 100 2>/dev/null
                echo "Route added for server $SERVER_NUM ($IP)"
            fi
        fi
        ;;
    remove)
        # Remove all metric 100 routes
        ip route show | grep "metric 100" | while read route; do
            ip route del $route 2>/dev/null
        done
        echo "All custom routes removed"
        ;;
    show)
        ip route show | grep "metric 100" || echo "No custom routes"
        ;;
    *)
        echo "Usage: $0 {add <server_num>|remove|show}"
        ;;
esac
EOF

    chmod +x "$CONFIG_DIR/route-manager.sh"
    print_success "Route manager created"
}

# Create startup script
create_startup() {
    cat > "$CONFIG_DIR/start.sh" << 'EOF'
#!/bin/bash

CONFIG_DIR="/root/stable-balancer"
PID_FILE="$CONFIG_DIR/balancer.pid"

# Kill existing process
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 $OLD_PID 2>/dev/null; then
        echo "Stopping old balancer (PID: $OLD_PID)"
        kill $OLD_PID
        sleep 2
    fi
fi

# Remove old routes
"$CONFIG_DIR/route-manager.sh" remove

# Start new balancer
nohup bash "$CONFIG_DIR/stable-failover.sh" >/dev/null 2>&1 &
NEW_PID=$!
echo $NEW_PID > "$PID_FILE"

echo "Balancer started with PID: $NEW_PID"

# Wait a bit and add initial route
sleep 3
if [ -f "$CONFIG_DIR/active.txt" ]; then
    ACTIVE=$(cat "$CONFIG_DIR/active.txt")
    "$CONFIG_DIR/route-manager.sh" add $ACTIVE
fi

echo "Startup complete"
EOF

    chmod +x "$CONFIG_DIR/start.sh"
    print_success "Startup script created"
}

# Main installation
stable_install() {
    echo
    print_info "Starting Stable Installation"
    echo "========================================"
    
    check_root
    
    # Get server information
    result=$(get_servers)
    count=$(echo "$result" | head -1)
    
    # Create all scripts
    create_stable_failover
    create_improved_monitor
    create_route_manager
    create_startup
    
    # Start the balancer
    bash "$CONFIG_DIR/start.sh"
    
    echo
    print_success "════════════════════════════════════════"
    print_success "Installation Completed Successfully!"
    print_success "════════════════════════════════════════"
    echo
    echo "Configuration:"
    source "$CONFIG_DIR/servers.conf"
    for ((i=1; i<=SERVER_COUNT; i++)); do
        NAME_VAR="SERVER_${i}_NAME"
        IP_VAR="SERVER_${i}_IP"
        echo "  Server $i: ${!NAME_VAR} (${!IP_VAR})"
    done
    echo
    echo "Commands:"
    echo "  Start balancer: $CONFIG_DIR/start.sh"
    echo "  Monitor: $CONFIG_DIR/monitor.sh"
    echo "  View log: tail -f $CONFIG_DIR/balancer.log"
    echo "  Route manager: $CONFIG_DIR/route-manager.sh"
    echo "  Uninstall: $CONFIG_DIR/uninstall.sh"
    echo
    print_info "Balancer is running with PID: $(cat $CONFIG_DIR/balancer.pid 2>/dev/null)"
}

# Create uninstall
create_uninstall() {
    cat > "$CONFIG_DIR/uninstall.sh" << 'EOF'
#!/bin/bash

CONFIG_DIR="/root/stable-balancer"

echo "Uninstalling Stable Balancer..."

# Stop balancer
if [ -f "$CONFIG_DIR/balancer.pid" ]; then
    PID=$(cat "$CONFIG_DIR/balancer.pid")
    kill $PID 2>/dev/null
    kill -9 $PID 2>/dev/null
fi

# Kill any remaining processes
pkill -f "stable-failover.sh" 2>/dev/null

# Remove routes
"$CONFIG_DIR/route-manager.sh" remove 2>/dev/null

# Ask about removing configuration
read -p "Remove all configuration files? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$CONFIG_DIR"
    echo "Configuration removed"
else
    echo "Configuration kept in $CONFIG_DIR"
fi

echo "Uninstall complete"
EOF

    chmod +x "$CONFIG_DIR/uninstall.sh"
}

# Show status
show_status() {
    echo
    print_info "Current Status"
    echo "========================================"
    
    if [ -f "$CONFIG_DIR/balancer.pid" ]; then
        PID=$(cat "$CONFIG_DIR/balancer.pid")
        if kill -0 $PID 2>/dev/null; then
            echo -e "${GREEN}✓ Balancer is running (PID: $PID)${NC}"
        else
            echo -e "${RED}✗ Balancer is not running${NC}"
        fi
    fi
    
    if [ -f "$CONFIG_DIR/servers.conf" ]; then
        source "$CONFIG_DIR/servers.conf"
        echo
        echo "Servers:"
        for ((i=1; i<=SERVER_COUNT; i++)); do
            NAME_VAR="SERVER_${i}_NAME"
            IP_VAR="SERVER_${i}_IP"
            echo "  $i. ${!NAME_VAR} - ${!IP_VAR}"
        done
    fi
    
    if [ -f "$ACTIVE_FILE" ]; then
        ACTIVE=$(cat "$ACTIVE_FILE")
        NAME_VAR="SERVER_${ACTIVE}_NAME"
        IP_VAR="SERVER_${ACTIVE}_IP"
        echo
        echo -e "${GREEN}Active: Server $ACTIVE (${!NAME_VAR})${NC}"
    fi
    
    echo
    echo "Routes:"
    "$CONFIG_DIR/route-manager.sh" show 2>/dev/null || echo "  No custom routes"
}

# Menu
show_menu() {
    clear
    echo "════════════════════════════════════════"
    echo "  Stable Balancer v5.0"
    echo "════════════════════════════════════════"
    echo
    echo "1) Install"
    echo "2) Start"
    echo "3) Stop"
    echo "4) Status"
    echo "5) Monitor"
    echo "6) View Log"
    echo "7) Uninstall"
    echo "8) Exit"
    echo
    read -p "Select option [1-8]: " opt
    
    case $opt in
        1) stable_install ;;
        2) [ -f "$CONFIG_DIR/start.sh" ] && bash "$CONFIG_DIR/start.sh" || print_error "Not installed" ;;
        3) pkill -f "stable-failover.sh" && echo "Stopped" ;;
        4) show_status ;;
        5) [ -f "$CONFIG_DIR/monitor.sh" ] && bash "$CONFIG_DIR/monitor.sh" || print_error "Not installed" ;;
        6) [ -f "$LOG_FILE" ] && tail -f "$LOG_FILE" || echo "No log file" ;;
        7) [ -f "$CONFIG_DIR/uninstall.sh" ] && bash "$CONFIG_DIR/uninstall.sh" || print_error "Not installed" ;;
        8) exit 0 ;;
        *) print_error "Invalid option" ;;
    esac
}

# Main
case "$1" in
    install) stable_install ;;
    start) [ -f "$CONFIG_DIR/start.sh" ] && bash "$CONFIG_DIR/start.sh" ;;
    stop) pkill -f "stable-failover.sh" ;;
    status) show_status ;;
    monitor) [ -f "$CONFIG_DIR/monitor.sh" ] && bash "$CONFIG_DIR/monitor.sh" ;;
    uninstall) [ -f "$CONFIG_DIR/uninstall.sh" ] && bash "$CONFIG_DIR/uninstall.sh" ;;
    menu|"") while true; do show_menu; read -p "Press Enter..."; done ;;
    *) echo "Usage: $0 {install|start|stop|status|monitor|uninstall|menu}" ;;
esac
