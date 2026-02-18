#!/bin/bash

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/DaggerConnect"
SYSTEMD_DIR="/etc/systemd/system"
LATEST_RELEASE_API="https://api.github.com/repos/itsFLoKi/DaggerConnect/releases/latest"

# Detect OS and architecture
OS_TYPE=""
ARCH_TYPE=""

detect_os_arch() {
    echo -e "${YELLOW}[*] Detecting system information...${NC}"
    
    # Detect OS
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_TYPE=$ID
    else
        OS_TYPE=$(uname -s)
    fi
    
    # Detect architecture
    ARCH_TYPE=$(uname -m)
    case $ARCH_TYPE in
        x86_64)  ARCH_TYPE="amd64" ;;
        aarch64) ARCH_TYPE="arm64" ;;
        armv7l)  ARCH_TYPE="armv7" ;;
        *)       ARCH_TYPE="amd64" ;;
    esac
    
    echo -e "  OS: ${GREEN}${OS_TYPE}${NC}"
    echo -e "  Arch: ${GREEN}${ARCH_TYPE}${NC}"
}

banner() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}       DaggerConnect Optimized v2.0${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  HTTP Mux Only - License Free${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

check_root() { 
    [[ $EUID -ne 0 ]] && { 
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    }
}

install_dependencies() {
    echo -e "${YELLOW}[*] Installing dependencies...${NC}"
    
    if command -v apt &>/dev/null; then
        # Ubuntu/Debian
        apt update -qq
        DEBIAN_FRONTEND=noninteractive apt install -y \
            wget curl tar openssl iproute2 net-tools systemd ufw \
            > /dev/null 2>&1
    elif command -v yum &>/dev/null; then
        # CentOS/RHEL
        yum install -y wget curl tar openssl iproute net-tools systemd > /dev/null 2>&1
    fi
    
    echo -e "${GREEN}[✓] Dependencies installed${NC}"
}

download_binary() {
    echo -e "${YELLOW}[*] Downloading DaggerConnect...${NC}"
    mkdir -p "$INSTALL_DIR"
    
    # Try to get latest version
    LATEST_VERSION=$(curl -s "$LATEST_RELEASE_API" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [[ -z "$LATEST_VERSION" ]] && LATEST_VERSION="v1.4.1"
    
    echo -e "    Version: ${GREEN}${LATEST_VERSION}${NC}"
    echo -e "    Architecture: ${GREEN}${ARCH_TYPE}${NC}"
    
    # Backup existing binary
    [[ -f "$INSTALL_DIR/DaggerConnect" ]] && cp "$INSTALL_DIR/DaggerConnect" "$INSTALL_DIR/DaggerConnect.bak"
    
    # Download URLs
    BINARY_URL="https://github.com/itsFLoKi/DaggerConnect/releases/download/${LATEST_VERSION}/DaggerConnect"
    
    if wget -q --show-progress "$BINARY_URL" -O "$INSTALL_DIR/DaggerConnect"; then
        chmod +x "$INSTALL_DIR/DaggerConnect"
        rm -f "$INSTALL_DIR/DaggerConnect.bak"
        echo -e "${GREEN}[✓] Download complete${NC}"
    else
        echo -e "${RED}[✗] Download failed${NC}"
        echo -e "${YELLOW}    Please download manually from:${NC}"
        echo -e "    https://github.com/itsFLoKi/DaggerConnect/releases"
        
        # Restore backup if exists
        [[ -f "$INSTALL_DIR/DaggerConnect.bak" ]] && mv "$INSTALL_DIR/DaggerConnect.bak" "$INSTALL_DIR/DaggerConnect"
        
        read -p "    Continue without binary? [y/N]: " cont
        if [[ ! "$cont" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

get_current_version() {
    if [[ -f "$INSTALL_DIR/DaggerConnect" ]] && [[ -x "$INSTALL_DIR/DaggerConnect" ]]; then
        "$INSTALL_DIR/DaggerConnect" -v 2>&1 | grep -oP 'v\d+\.\d+' || echo "unknown"
    else
        echo "not-installed"
    fi
}

generate_certificate() {
    local domain=${1:-www.google.com}
    mkdir -p "$CONFIG_DIR/certs"
    
    openssl req -x509 -newkey rsa:4096 \
        -keyout "$CONFIG_DIR/certs/key.pem" \
        -out "$CONFIG_DIR/certs/cert.pem" \
        -days 365 -nodes \
        -subj "/C=US/ST=CA/L=San Francisco/O=Corp/CN=${domain}" 2>/dev/null
    
    echo -e "${GREEN}[✓] SSL certificate generated for ${domain}${NC}"
}

create_systemd_service() {
    local mode=$1
    
    cat > "$SYSTEMD_DIR/DaggerConnect-${mode}.service" << EOF
[Unit]
Description=DaggerConnect ${mode} Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$CONFIG_DIR
ExecStart=$INSTALL_DIR/DaggerConnect -c $CONFIG_DIR/${mode}.yaml
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    echo -e "${GREEN}[✓] Service created: DaggerConnect-${mode}${NC}"
}

start_service() {
    local mode=$1
    
    echo -e "${YELLOW}[*] Starting DaggerConnect-${mode} service...${NC}"
    
    systemctl enable "DaggerConnect-${mode}" 2>/dev/null
    systemctl start "DaggerConnect-${mode}" 2>/dev/null
    
    # Wait for service to start
    sleep 3
    
    # Check if service is running
    if systemctl is-active "DaggerConnect-${mode}" >/dev/null 2>&1; then
        echo -e "${GREEN}[✓] Service DaggerConnect-${mode} is running${NC}"
        return 0
    else
        echo -e "${RED}[✗] Service failed to start${NC}"
        echo -e "${YELLOW}    Checking logs:${NC}"
        journalctl -u "DaggerConnect-${mode}" -n 10 --no-pager
        return 1
    fi
}

check_service_status() {
    local mode=$1
    
    if systemctl is-active "DaggerConnect-${mode}" >/dev/null 2>&1; then
        echo -e "  ${GREEN}●${NC} $mode is running"
        return 0
    else
        echo -e "  ${RED}○${NC} $mode is stopped"
        return 1
    fi
}

test_connection() {
    local server_ip=$1
    local port=${2:-2020}
    
    echo -e "${YELLOW}[*] Testing connection to ${server_ip}:${port}...${NC}"
    
    # Test TCP connection
    if timeout 5 nc -zv "$server_ip" "$port" 2>/dev/null; then
        echo -e "${GREEN}[✓] Port ${port} is reachable${NC}"
        return 0
    else
        # Try with different method
        if timeout 5 curl -s -o /dev/null "http://${server_ip}:${port}" 2>/dev/null; then
            echo -e "${GREEN}[✓] Port ${port} is reachable${NC}"
            return 0
        else
            echo -e "${RED}[✗] Cannot connect to ${server_ip}:${port}${NC}"
            echo -e "${YELLOW}    Check if server is running and firewall allows port ${port}${NC}"
            return 1
        fi
    fi
}

optimize_system() {
    echo -e "${CYAN}━━━ System Optimization ━━━${NC}"
    
    # Detect main interface
    MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    [[ -z "$MAIN_IFACE" ]] && MAIN_IFACE="eth0"
    echo -e "  Interface: ${GREEN}$MAIN_IFACE${NC}"

    # Increase system limits
    cat > /etc/security/limits.d/99-daggerconnect.conf << EOF
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF

    # TCP optimizations
    cat > /etc/sysctl.d/99-daggerconnect.conf << 'EOF'
# DaggerConnect Optimizations
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 8388608
net.core.wmem_default = 8388608
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 4096

# TCP settings
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1

# Keepalive
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# Timeouts
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
EOF

    sysctl -p /etc/sysctl.d/99-daggerconnect.conf > /dev/null 2>&1
    
    echo -e "${GREEN}[✓] System optimized${NC}"
}

# ============================================================================
# PSK SETUP
# ============================================================================

setup_psk() {
    echo ""
    echo -e "${CYAN}━━━ License-Free Setup (PSK Only) ━━━${NC}"
    
    while true; do
        read -sp "  Enter PSK (minimum 8 characters): " PSK_VALUE
        echo ""
        if [[ ${#PSK_VALUE} -ge 8 ]]; then
            break
        else
            echo -e "${RED}  PSK must be at least 8 characters${NC}"
        fi
    done
    
    # Save PSK to file
    echo "$PSK_VALUE" > "$CONFIG_DIR/psk.key"
    chmod 600 "$CONFIG_DIR/psk.key"
    
    echo -e "${GREEN}[✓] PSK configured successfully${NC}"
}

# ============================================================================
# PORT MAPPING COLLECTOR
# ============================================================================

collect_port_mappings() {
    MAPPINGS=""
    MAP_COUNT=0
    
    echo -e "  ${GREEN}Examples:${NC}"
    echo -e "  • Single: ${YELLOW}8080${NC}"
    echo -e "  • Range: ${YELLOW}1000-2000${NC}"
    echo -e "  • Custom: ${YELLOW}5000=8080${NC}"
    echo -e "  • Comma: ${YELLOW}80,443,8080${NC}"
    echo ""
    
    while true; do
        echo -e "${YELLOW}  Mapping #$((MAP_COUNT+1))${NC}"
        echo "    1) TCP  2) UDP  3) Both"
        read -p "    Protocol [1]: " proto_choice
        
        case $proto_choice in
            2) PROTO="udp" ;;
            3) PROTO="both" ;;
            *) PROTO="tcp" ;;
        esac
        
        read -p "    Port(s): " port_input
        [[ -z "$port_input" ]] && { echo -e "${RED}    Error: Port required${NC}"; continue; }
        
        port_input=$(echo "$port_input" | tr -d ' ')
        local bind_ip="0.0.0.0"
        local target_ip="127.0.0.1"
        
        _add_mapping() {
            local proto=$1
            local bind_port=$2
            local target_port=$3
            
            if [[ "$proto" == "both" ]]; then
                MAPPINGS+="  - type: tcp\n    bind: \"${bind_ip}:${bind_port}\"\n    target: \"${target_ip}:${target_port}\"\n"
                MAPPINGS+="  - type: udp\n    bind: \"${bind_ip}:${bind_port}\"\n    target: \"${target_ip}:${target_port}\"\n"
                MAP_COUNT=$((MAP_COUNT+2))
            else
                MAPPINGS+="  - type: ${proto}\n    bind: \"${bind_ip}:${bind_port}\"\n    target: \"${target_ip}:${target_port}\"\n"
                MAP_COUNT=$((MAP_COUNT+1))
            fi
        }
        
        # Comma separated ports
        if [[ "$port_input" == *","* ]]; then
            IFS=',' read -ra PORTS <<< "$port_input"
            for port in "${PORTS[@]}"; do
                port=$(echo "$port" | tr -d ' ')
                if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
                    _add_mapping "$PROTO" "$port" "$port"
                    echo -e "${GREEN}    ✓ Port $port mapped${NC}"
                fi
            done
        
        # Range
        elif [[ "$port_input" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start=${BASH_REMATCH[1]}
            end=${BASH_REMATCH[2]}
            
            if [ "$start" -lt "$end" ] && [ "$end" -le 65535 ]; then
                for ((p=start; p<=end; p++)); do
                    _add_mapping "$PROTO" $p $p
                done
                echo -e "${GREEN}    ✓ Range added ($((end-start+1)) ports)${NC}"
            else
                echo -e "${RED}    Error: Invalid range${NC}"
            fi
        
        # Custom mapping
        elif [[ "$port_input" =~ ^([0-9]+)=([0-9]+)$ ]]; then
            bind_port=${BASH_REMATCH[1]}
            target_port=${BASH_REMATCH[2]}
            
            if [ "$bind_port" -ge 1 ] && [ "$bind_port" -le 65535 ] && [ "$target_port" -ge 1 ] && [ "$target_port" -le 65535 ]; then
                _add_mapping "$PROTO" "$bind_port" "$target_port"
                echo -e "${GREEN}    ✓ ${bind_port} -> ${target_port}${NC}"
            else
                echo -e "${RED}    Error: Invalid port number${NC}"
            fi
        
        # Single port
        elif [[ "$port_input" =~ ^[0-9]+$ ]] && [ "$port_input" -ge 1 ] && [ "$port_input" -le 65535 ]; then
            _add_mapping "$PROTO" "$port_input" "$port_input"
            echo -e "${GREEN}    ✓ Port $port_input mapped${NC}"
        
        else
            echo -e "${RED}    Error: Invalid format${NC}"
            continue
        fi
        
        read -p "    Add more mappings? [y/N]: " add_more
        [[ ! "$add_more" =~ ^[Yy]$ ]] && break
    done
    
    # Add default mapping if none defined
    if [[ $MAP_COUNT -eq 0 ]]; then
        MAPPINGS="  - type: tcp\n    bind: \"0.0.0.0:8080\"\n    target: \"127.0.0.1:8080\"\n"
        MAP_COUNT=1
        echo -e "${YELLOW}  Default mapping added: 8080 -> 8080${NC}"
    fi
}

# ============================================================================
# PROFILE DEFAULTS
# ============================================================================

set_profile_defaults() {
    local profile=$1
    
    case $profile in
        aggressive)
            SMUX_KEEPALIVE=3
            SMUX_MAX_RECV=33554432
            SMUX_MAX_STREAM=33554432
            SMUX_FRAME_SIZE=65536
            KCP_INTERVAL=5
            KCP_SNDWND=4096
            KCP_RCVWND=4096
            MTU_VALUE=1400
            TCP_KEEPALIVE=20
            ;;
        latency)
            SMUX_KEEPALIVE=5
            SMUX_MAX_RECV=16777216
            SMUX_MAX_STREAM=16777216
            SMUX_FRAME_SIZE=32768
            KCP_INTERVAL=10
            KCP_SNDWND=2048
            KCP_RCVWND=2048
            MTU_VALUE=1350
            TCP_KEEPALIVE=30
            ;;
        *)
            SMUX_KEEPALIVE=4
            SMUX_MAX_RECV=25165824
            SMUX_MAX_STREAM=25165824
            SMUX_FRAME_SIZE=49152
            KCP_INTERVAL=8
            KCP_SNDWND=3072
            KCP_RCVWND=3072
            MTU_VALUE=1450
            TCP_KEEPALIVE=25
            ;;
    esac
    
    SMUX_VERSION=2
    KCP_NODELAY=1
    KCP_RESEND=2
    KCP_NC=1
    TCP_NODELAY=true
    TCP_READ_BUFFER=16777216
    TCP_WRITE_BUFFER=16777216
    MAX_CONNECTIONS=10000
    CONNECTION_TIMEOUT=60
    STREAM_TIMEOUT=300
    OBFUSCATION=true
    OBFUSCATION_MIN_PAD=32
    OBFUSCATION_MAX_PAD=1024
    FAKE_DOMAIN="www.google.com"
    FAKE_PATH="/search"
    USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    LB_STRATEGY="round_robin"
    LB_HEALTH_CHECK=15
    LB_FAILOVER_DELAY=1000
    LB_MAX_FAILURES=5
    LB_RECOVERY_TIME=60
}

# ============================================================================
# ADVANCED SETTINGS EDITOR
# ============================================================================

edit_advanced_settings() {
    echo ""
    echo -e "${CYAN}━━━ Advanced Settings ━━━${NC}"
    
    echo -e "${YELLOW}Network:${NC}"
    read -p "  MTU [$MTU_VALUE]: " new_mtu
    MTU_VALUE=${new_mtu:-$MTU_VALUE}
    
    echo -e "${YELLOW}SMUX (TCP Mux):${NC}"
    read -p "  Keepalive interval (seconds) [$SMUX_KEEPALIVE]: " new_ka
    SMUX_KEEPALIVE=${new_ka:-$SMUX_KEEPALIVE}
    
    echo -e "${YELLOW}KCP:${NC}"
    read -p "  Send window [$KCP_SNDWND]: " new_snd
    KCP_SNDWND=${new_snd:-$KCP_SNDWND}
    
    read -p "  Receive window [$KCP_RCVWND]: " new_rcv
    KCP_RCVWND=${new_rcv:-$KCP_RCVWND}
}

# ============================================================================
# TRANSPORT SELECTOR
# ============================================================================

select_transport() {
    TRANSPORT="httpmux"
    echo -e "  Transport: ${GREEN}httpmux${NC}"
}

# ============================================================================
# PROFILE SELECTOR
# ============================================================================

select_profile() {
    echo ""
    echo -e "${YELLOW}Select Profile:${NC}"
    echo "  1) Balanced (default) - Good for general use"
    echo "  2) Aggressive - Maximum throughput"
    echo "  3) Latency - Optimized for gaming/voip"
    
    read -p "  Choice [1]: " profile_choice
    
    case $profile_choice in
        2) PROFILE="aggressive" ;;
        3) PROFILE="latency" ;;
        *) PROFILE="balanced" ;;
    esac
    
    set_profile_defaults "$PROFILE"
    echo -e "${GREEN}  ✓ Profile: $PROFILE${NC}"
}

# ============================================================================
# WRITE SHARED CONFIGURATION
# ============================================================================

write_shared_config() {
    local config_file=$1
    
    cat >> "$config_file" << YAML

smux:
  keepalive: ${SMUX_KEEPALIVE}
  max_recv: ${SMUX_MAX_RECV}
  max_stream: ${SMUX_MAX_STREAM}
  frame_size: ${SMUX_FRAME_SIZE}
  version: ${SMUX_VERSION}

kcp:
  nodelay: ${KCP_NODELAY}
  interval: ${KCP_INTERVAL}
  resend: ${KCP_RESEND}
  nc: ${KCP_NC}
  sndwnd: ${KCP_SNDWND}
  rcvwnd: ${KCP_RCVWND}
  mtu: ${MTU_VALUE}

advanced:
  tcp_nodelay: ${TCP_NODELAY}
  tcp_keepalive: ${TCP_KEEPALIVE}
  tcp_read_buffer: ${TCP_READ_BUFFER}
  tcp_write_buffer: ${TCP_WRITE_BUFFER}
  max_connections: ${MAX_CONNECTIONS}
  connection_timeout: ${CONNECTION_TIMEOUT}
  stream_timeout: ${STREAM_TIMEOUT}

obfuscation:
  enabled: ${OBFUSCATION}
  min_padding: ${OBFUSCATION_MIN_PAD}
  max_padding: ${OBFUSCATION_MAX_PAD}

http_mimic:
  fake_domain: "${FAKE_DOMAIN}"
  fake_path: "${FAKE_PATH}"
  user_agent: "${USER_AGENT}"
YAML
}

# ============================================================================
# SERVER INSTALLATION
# ============================================================================

install_server() {
    banner
    mkdir -p "$CONFIG_DIR"
    
    echo -e "${CYAN}━━━ Server Installation (Iran) ━━━${NC}"
    echo -e "${YELLOW}This will configure the Iran side server${NC}\n"
    
    setup_psk
    
    echo ""
    echo "  Installation Mode:"
    echo "    1) Single Port (recommended)"
    echo "    2) Multiple Ports"
    
    read -p "  Choice [1]: " install_mode
    
    select_profile
    select_transport
    
    # Get tunnel port
    read -p "  Tunnel port [2020]: " tunnel_port
    tunnel_port=${tunnel_port:-2020}
    
    # SSL option
    CERT_GENERATED=false
    local cert_file=""
    local key_file=""
    
    read -p "  Use SSL? (y/N): " use_ssl
    if [[ "$use_ssl" =~ ^[Yy]$ ]]; then
        read -p "  Certificate domain [$FAKE_DOMAIN]: " cert_domain
        cert_domain=${cert_domain:-$FAKE_DOMAIN}
        generate_certificate "$cert_domain"
        CERT_GENERATED=true
        cert_file="$CONFIG_DIR/certs/cert.pem"
        key_file="$CONFIG_DIR/certs/key.pem"
        TRANSPORT="httpsmux"
    fi
    
    # Port mappings
    echo ""
    echo -e "${CYAN}━━━ Port Mappings ━━━${NC}"
    collect_port_mappings
    
    # Create listener block
    LISTENERS_BLOCK="  - addr: \"0.0.0.0:${tunnel_port}\"\n    transport: \"${TRANSPORT}\"\n"
    
    if [[ -n "$cert_file" ]]; then
        LISTENERS_BLOCK+="    cert_file: \"${cert_file}\"\n    key_file: \"${key_file}\"\n"
    fi
    
    LISTENERS_BLOCK+="    maps:\n"
    
    while IFS= read -r line; do
        [[ -n "$line" ]] && LISTENERS_BLOCK+="    ${line}\n"
    done <<< "$(echo -e "$MAPPINGS")"
    
    # Write server config
    if [[ -f "$CONFIG_DIR/psk.key" ]]; then
        PSK_VALUE=$(cat "$CONFIG_DIR/psk.key")
    fi
    
    cat > "$CONFIG_DIR/server.yaml" << YAML
mode: server
psk: "${PSK_VALUE}"
profile: "${PROFILE}"
verbose: false
max_sessions: 0
heartbeat: 15

listeners:
YAML

    echo -e "$LISTENERS_BLOCK" >> "$CONFIG_DIR/server.yaml"
    write_shared_config "$CONFIG_DIR/server.yaml"
    
    echo -e "${GREEN}[✓] Server configuration saved${NC}"
    
    # Create and start service
    create_systemd_service "server"
    
    # Configure firewall
    if command -v ufw &>/dev/null; then
        echo -e "${YELLOW}[*] Configuring firewall...${NC}"
        ufw allow "$tunnel_port/tcp" > /dev/null 2>&1
        ufw --force enable > /dev/null 2>&1
        echo -e "${GREEN}[✓] Port $tunnel_port opened in firewall${NC}"
    fi
    
    # Start service
    echo ""
    start_service "server"
    
    # Show server info
    echo ""
    echo -e "${GREEN}━━━ Server Installation Complete ━━━${NC}"
    echo -e "  Server IP: ${GREEN}$(curl -s ifconfig.me || echo "Unknown")${NC}"
    echo -e "  Tunnel Port: ${GREEN}${tunnel_port}${NC}"
    echo -e "  Transport: ${GREEN}${TRANSPORT}${NC}"
    echo -e "  PSK: ${GREEN}${PSK_VALUE}${NC}"
    echo -e "  Profile: ${GREEN}${PROFILE}${NC}"
    echo ""
    echo -e "  ${YELLOW}Use this information to configure clients${NC}"
    echo ""
    
    read -p "Press Enter to continue..."
    main_menu
}

# ============================================================================
# CLIENT INSTALLATION - FIXED FOR AUTO CONNECTION
# ============================================================================

install_client() {
    banner
    mkdir -p "$CONFIG_DIR"
    
    echo -e "${CYAN}━━━ Client Installation (Kharej) ━━━${NC}"
    echo -e "${YELLOW}This will configure the client and connect to server${NC}\n"
    
    setup_psk
    select_profile
    
    # Collect server information
    PATHS_BLOCK="paths:"
    SERVER_COUNT=0
    SERVER_IPS=()
    SERVER_PORTS=()
    
    while true; do
        echo ""
        echo -e "${YELLOW}  Server #$((SERVER_COUNT+1)) Configuration${NC}"
        
        select_transport
        
        read -p "  Server IP address: " server_ip
        [[ -z "$server_ip" ]] && { echo -e "${RED}    Error: IP required${NC}"; continue; }
        
        read -p "  Server port [2020]: " server_port
        server_port=${server_port:-2020}
        
        # Test connection before adding
        echo ""
        test_connection "$server_ip" "$server_port"
        
        read -p "  Add this server anyway? [Y/n]: " add_anyway
        if [[ "$add_anyway" =~ ^[Nn]$ ]]; then
            continue
        fi
        
        read -p "  Connection pool size [3]: " pool_size
        pool_size=${pool_size:-3}
        
        read -p "  Weight for load balancing [1]: " server_weight
        server_weight=${server_weight:-1}
        
        # Store for later use
        SERVER_IPS+=("$server_ip")
        SERVER_PORTS+=("$server_port")
        
        PATHS_BLOCK+="
  - transport: \"${TRANSPORT}\"
    addr: \"${server_ip}:${server_port}\"
    connection_pool: ${pool_size}
    retry_interval: 2
    dial_timeout: 15
    weight: ${server_weight}
    priority: 0"
        
        SERVER_COUNT=$((SERVER_COUNT+1))
        echo -e "${GREEN}  ✓ Added server: ${server_ip}:${server_port}${NC}"
        
        read -p "  Add another server? [y/N]: " add_server
        [[ ! "$add_server" =~ ^[Yy]$ ]] && break
    done

    # Load balancer for multiple servers
    if [[ $SERVER_COUNT -gt 1 ]]; then
        echo ""
        echo -e "${YELLOW}  Load Balancer Strategy:${NC}"
        echo "    1) Round Robin (default)"
        echo "    2) Least Loaded"
        echo "    3) Failover"
        
        read -p "    Choice [1]: " lb_choice
        
        case $lb_choice in
            2) LB_STRATEGY="least_loaded" ;;
            3) LB_STRATEGY="failover" ;;
            *) LB_STRATEGY="round_robin" ;;
        esac
    fi

    # Advanced settings
    read -p "  Edit advanced settings? [y/N]: " edit_adv
    [[ $edit_adv =~ ^[Yy]$ ]] && edit_advanced_settings

    # Write client config
    if [[ -f "$CONFIG_DIR/psk.key" ]]; then
        PSK_VALUE=$(cat "$CONFIG_DIR/psk.key")
    fi
    
    cat > "$CONFIG_DIR/client.yaml" << YAML
mode: client
psk: "${PSK_VALUE}"
profile: "${PROFILE}"
verbose: false
heartbeat: 15

${PATHS_BLOCK}

load_balancer:
  strategy: "${LB_STRATEGY}"
  health_check_sec: ${LB_HEALTH_CHECK}
  failover_delay_ms: ${LB_FAILOVER_DELAY}
  max_failures: ${LB_MAX_FAILURES}
  recovery_time_sec: ${LB_RECOVERY_TIME}
  sticky_session: false
YAML

    write_shared_config "$CONFIG_DIR/client.yaml"
    
    echo -e "${GREEN}[✓] Client configuration saved${NC}"
    
    # Create and start service
    create_systemd_service "client"
    
    # Stop any existing client service
    systemctl stop DaggerConnect-client 2>/dev/null
    
    # Start service
    echo ""
    echo -e "${YELLOW}[*] Starting client service...${NC}"
    
    if start_service "client"; then
        echo -e "${GREEN}[✓] Client service started successfully${NC}"
        
        # Wait a bit for connection to establish
        sleep 3
        
        # Check connection status
        echo ""
        echo -e "${CYAN}━━━ Connection Status ━━━${NC}"
        
        # Check service logs for connection status
        if journalctl -u DaggerConnect-client -n 20 --no-pager | grep -i "connected\|established\|success"; then
            echo -e "${GREEN}[✓] Client connected to server successfully${NC}"
        else
            echo -e "${YELLOW}[!] Checking connection status...${NC}"
            
            # Try to test each server
            for i in "${!SERVER_IPS[@]}"; do
                ip="${SERVER_IPS[$i]}"
                port="${SERVER_PORTS[$i]}"
                
                echo -e "  Testing ${ip}:${port}..."
                
                # Check if connection is established
                if ss -tnp 2>/dev/null | grep -q "$ip:$port"; then
                    echo -e "  ${GREEN}✓ Connected to ${ip}:${port}${NC}"
                else
                    echo -e "  ${YELLOW}⚠ Not connected to ${ip}:${port}${NC}"
                fi
            done
        fi
        
        # Show recent logs
        echo ""
        echo -e "${YELLOW}Recent logs:${NC}"
        journalctl -u DaggerConnect-client -n 5 --no-pager
    else
        echo -e "${RED}[✗] Failed to start client service${NC}"
    fi
    
    # Show client info
    echo ""
    echo -e "${GREEN}━━━ Client Installation Complete ━━━${NC}"
    echo -e "  Servers configured: ${GREEN}${SERVER_COUNT}${NC}"
    echo -e "  Load Balancer: ${GREEN}${LB_STRATEGY}${NC}"
    echo -e "  Profile: ${GREEN}${PROFILE}${NC}"
    echo -e "  Config: ${CYAN}$CONFIG_DIR/client.yaml${NC}"
    echo ""
    echo -e "  ${YELLOW}Use these commands to manage:${NC}"
    echo -e "    ${CYAN}systemctl status DaggerConnect-client${NC}"
    echo -e "    ${CYAN}journalctl -u DaggerConnect-client -f${NC}"
    echo ""
    
    read -p "Press Enter to continue..."
    main_menu
}

# ============================================================================
# SERVICE MANAGEMENT
# ============================================================================

manage_services() {
    echo -e "${CYAN}━━━ Service Management ━━━${NC}"
    
    # Check current status
    echo "Current Status:"
    check_service_status "server"
    check_service_status "client"
    echo ""
    
    echo "  1) Start Server"
    echo "  2) Stop Server"
    echo "  3) Restart Server"
    echo "  4) Start Client"
    echo "  5) Stop Client"
    echo "  6) Restart Client"
    echo "  7) Restart All"
    echo "  0) Back"
    
    read -p "  Choice: " mgmt_choice
    
    case $mgmt_choice in
        1) systemctl start DaggerConnect-server; echo -e "${GREEN}[✓] Server started${NC}" ;;
        2) systemctl stop DaggerConnect-server; echo -e "${YELLOW}[✓] Server stopped${NC}" ;;
        3) systemctl restart DaggerConnect-server; echo -e "${GREEN}[✓] Server restarted${NC}" ;;
        4) systemctl start DaggerConnect-client; echo -e "${GREEN}[✓] Client started${NC}" ;;
        5) systemctl stop DaggerConnect-client; echo -e "${YELLOW}[✓] Client stopped${NC}" ;;
        6) systemctl restart DaggerConnect-client; echo -e "${GREEN}[✓] Client restarted${NC}" ;;
        7) 
            systemctl restart DaggerConnect-server DaggerConnect-client
            echo -e "${GREEN}[✓] All services restarted${NC}"
            ;;
        0) main_menu ;;
        *) main_menu ;;
    esac
    
    sleep 2
    manage_services
}

# ============================================================================
# VIEW CONNECTION STATUS
# ============================================================================

view_connection_status() {
    echo -e "${CYAN}━━━ Connection Status ━━━${NC}"
    
    # Check if client is running
    if systemctl is-active DaggerConnect-client >/dev/null 2>&1; then
        echo -e "${GREEN}[✓] Client is running${NC}"
        
        # Show active connections
        echo ""
        echo -e "${YELLOW}Active connections:${NC}"
        
        # Check for established connections to server ports
        if command -v ss &>/dev/null; then
            ss -tnp 2>/dev/null | grep -E "2020|ESTAB" | while read line; do
                echo "  $line"
            done
        else
            netstat -tnp 2>/dev/null | grep -E "2020|ESTABLISHED" | while read line; do
                echo "  $line"
            done
        fi
        
        # Show recent logs
        echo ""
        echo -e "${YELLOW}Recent logs:${NC}"
        journalctl -u DaggerConnect-client -n 10 --no-pager | grep -i "connected\|established\|failed\|error"
        
    else
        echo -e "${RED}[✗] Client is not running${NC}"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
    main_menu
}

# ============================================================================
# CHANGE MTU
# ============================================================================

change_mtu() {
    echo ""
    echo -e "${CYAN}━━━ Change MTU ━━━${NC}"
    
    if [[ -f "$CONFIG_DIR/server.yaml" ]]; then
        current_mtu=$(grep -oP 'mtu: \K\d+' "$CONFIG_DIR/server.yaml" 2>/dev/null)
        echo -e "  Server config: ${GREEN}$current_mtu${NC}"
    fi
    
    if [[ -f "$CONFIG_DIR/client.yaml" ]]; then
        current_mtu=$(grep -oP 'mtu: \K\d+' "$CONFIG_DIR/client.yaml" 2>/dev/null)
        echo -e "  Client config: ${GREEN}$current_mtu${NC}"
    fi
    
    echo ""
    read -p "  Enter new MTU value [1450]: " new_mtu
    new_mtu=${new_mtu:-1450}
    
    if [[ "$new_mtu" =~ ^[0-9]+$ ]] && [ "$new_mtu" -ge 576 ] && [ "$new_mtu" -le 1500 ]; then
        sed -i "s/mtu: [0-9]*/mtu: $new_mtu/" $CONFIG_DIR/*.yaml 2>/dev/null
        systemctl restart DaggerConnect-server DaggerConnect-client 2>/dev/null
        echo -e "${GREEN}[✓] MTU changed to $new_mtu and services restarted${NC}"
    else
        echo -e "${RED}Error: Invalid MTU value (must be 576-1500)${NC}"
    fi
    
    echo ""
    read -p "Press Enter..."
    main_menu
}

# ============================================================================
# UNINSTALL
# ============================================================================

uninstall() {
    banner
    echo -e "${RED}━━━ Uninstall DaggerConnect ━━━${NC}"
    echo -e "${YELLOW}Warning: This will remove all configurations${NC}"
    
    read -p "  Are you sure? [y/N]: " confirm_uninstall
    if [[ ! $confirm_uninstall =~ ^[Yy]$ ]]; then
        main_menu
        return
    fi
    
    # Stop and disable services
    systemctl stop DaggerConnect-server DaggerConnect-client 2>/dev/null
    systemctl disable DaggerConnect-server DaggerConnect-client 2>/dev/null
    
    # Remove service files
    rm -f "$SYSTEMD_DIR/DaggerConnect-server.service"
    rm -f "$SYSTEMD_DIR/DaggerConnect-client.service"
    
    # Remove binary
    rm -f "$INSTALL_DIR/DaggerConnect"
    
    # Remove configuration
    rm -rf "$CONFIG_DIR"
    
    # Remove sysctl config
    rm -f /etc/sysctl.d/99-daggerconnect.conf
    sysctl -p > /dev/null 2>&1
    
    systemctl daemon-reload
    
    echo -e "${GREEN}[✓] DaggerConnect uninstalled successfully${NC}"
    exit 0
}

# ============================================================================
# MAIN MENU
# ============================================================================

main_menu() {
    banner
    
    local current_version=$(get_current_version)
    if [[ "$current_version" != "not-installed" ]]; then
        echo -e "  Installed version: ${GREEN}$current_version${NC}"
        echo -e "  Server: $(check_service_status server 2>/dev/null && echo "${GREEN}● Running${NC}" || echo "${RED}○ Stopped${NC}")"
        echo -e "  Client: $(check_service_status client 2>/dev/null && echo "${GREEN}● Running${NC}" || echo "${RED}○ Stopped${NC}")"
        echo ""
    fi
    
    echo -e "${CYAN}━━━ Main Menu ━━━${NC}"
    echo ""
    echo "  1) Install Server (Iran side)"
    echo "  2) Install Client (Kharej side) - Auto connects to server"
    echo "  3) Manage Services (Start/Stop/Restart)"
    echo "  4) View Connection Status"
    echo "  5) Change MTU"
    echo "  6) Update Core"
    echo "  7) System Optimizer"
    echo "  8) Uninstall"
    echo ""
    echo "  0) Exit"
    echo ""
    
    read -p "  Choice: " menu_choice
    
    case $menu_choice in
        1) install_server ;;
        2) install_client ;;
        3) manage_services ;;
        4) view_connection_status ;;
        5) change_mtu ;;
        6) update_core ;;
        7) optimize_system; read -p "Press Enter..."; main_menu ;;
        8) uninstall ;;
        0) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) main_menu ;;
    esac
}

# ============================================================================
# UPDATE CORE
# ============================================================================

update_core() {
    banner
    echo -e "${CYAN}━━━ Update Core ━━━${NC}"
    
    local current_version=$(get_current_version)
    
    if [[ "$current_version" == "not-installed" ]]; then
        echo -e "${RED}Error: DaggerConnect not installed${NC}"
        read -p "Press Enter..."
        main_menu
        return
    fi
    
    echo -e "  Current version: ${YELLOW}$current_version${NC}"
    read -p "  Continue with update? [y/N]: " confirm_update
    
    if [[ ! $confirm_update =~ ^[Yy]$ ]]; then
        main_menu
        return
    fi
    
    # Stop services
    systemctl stop DaggerConnect-server DaggerConnect-client 2>/dev/null
    
    # Download new binary
    download_binary
    
    # Start services
    systemctl start DaggerConnect-server DaggerConnect-client 2>/dev/null
    
    local new_version=$(get_current_version)
    echo -e "  Updated to: ${GREEN}$new_version${NC}"
    
    echo ""
    read -p "Press Enter..."
    main_menu
}

# ============================================================================
# SCRIPT START
# ============================================================================

# Check root privileges
check_root

# Detect OS and architecture
detect_os_arch

# Show banner
banner

# Install dependencies
install_dependencies

# Download binary if not present
if [[ ! -f "$INSTALL_DIR/DaggerConnect" ]]; then
    echo -e "${YELLOW}DaggerConnect binary not found. Installing...${NC}"
    download_binary
    echo ""
fi

# Start main menu
main_menu
