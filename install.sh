#!/bin/bash

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/DaggerConnect"
SYSTEMD_DIR="/etc/systemd/system"
LATEST_RELEASE_API="https://api.github.com/repos/itsFLoKi/DaggerConnect/releases/latest"

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
        apt update -qq && apt install -y wget curl tar openssl iproute2 dnsutils net-tools > /dev/null 2>&1
    elif command -v yum &>/dev/null; then
        yum install -y wget curl tar openssl iproute bind-utils net-tools > /dev/null 2>&1
    fi
    echo -e "${GREEN}[✓] Dependencies installed${NC}"
}

download_binary() {
    echo -e "${YELLOW}[*] Downloading DaggerConnect...${NC}"
    mkdir -p "$INSTALL_DIR"
    
    LATEST_VERSION=$(curl -s "$LATEST_RELEASE_API" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [[ -z "$LATEST_VERSION" ]] && LATEST_VERSION="v1.4.1"
    
    BINARY_URL="https://github.com/itsFLoKi/DaggerConnect/releases/download/${LATEST_VERSION}/DaggerConnect"
    echo -e "    Version: ${GREEN}${LATEST_VERSION}${NC}"
    
    [[ -f "$INSTALL_DIR/DaggerConnect" ]] && cp "$INSTALL_DIR/DaggerConnect" "$INSTALL_DIR/DaggerConnect.bak"
    
    if wget -q --show-progress "$BINARY_URL" -O "$INSTALL_DIR/DaggerConnect"; then
        chmod +x "$INSTALL_DIR/DaggerConnect"
        rm -f "$INSTALL_DIR/DaggerConnect.bak"
        echo -e "${GREEN}[✓] Download complete${NC}"
    else
        echo -e "${RED}[✗] Download failed${NC}"
        [[ -f "$INSTALL_DIR/DaggerConnect.bak" ]] && mv "$INSTALL_DIR/DaggerConnect.bak" "$INSTALL_DIR/DaggerConnect"
        exit 1
    fi
}

get_current_version() {
    if [[ -f "$INSTALL_DIR/DaggerConnect" ]]; then
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

optimize_system() {
    echo -e "${CYAN}━━━ System Optimization ━━━${NC}"
    
    # Detect main interface
    MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    [[ -z "$MAIN_IFACE" ]] && MAIN_IFACE="eth0"
    echo -e "  Interface: ${GREEN}$MAIN_IFACE${NC}"

    # TCP optimizations for stable multiplexing
    sysctl -w net.core.rmem_max=33554432 > /dev/null 2>&1
    sysctl -w net.core.wmem_max=33554432 > /dev/null 2>&1
    sysctl -w net.core.rmem_default=8388608 > /dev/null 2>&1
    sysctl -w net.core.wmem_default=8388608 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_rmem="4096 87380 33554432" > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_wmem="4096 65536 33554432" > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null 2>&1
    sysctl -w net.core.default_qdisc=fq > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_notsent_lowat=16384 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_mtu_probing=1 > /dev/null 2>&1
    
    # Keepalive optimization
    sysctl -w net.ipv4.tcp_keepalive_time=60 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_intvl=10 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_probes=6 > /dev/null 2>&1

    # Save settings
    cat > /etc/sysctl.d/99-daggerconnect.conf << 'EOF'
# DaggerConnect Optimizations
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.core.rmem_default=8388608
net.core.wmem_default=8388608
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 65536 33554432
net.ipv4.tcp_congestion_control=bbr
net.core.default_qdisc=fq
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.tcp_keepalive_probes=6
EOF

    sysctl -p /etc/sysctl.d/99-daggerconnect.conf > /dev/null 2>&1
    
    echo -e "${GREEN}[✓] System optimized for stable connections${NC}"
}

# ============================================================================
# LICENSE-FREE SETUP (PSK Only)
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
# PORT MAPPING COLLECTOR (with comma support)
# ============================================================================

collect_port_mappings() {
    MAPPINGS=""
    MAP_COUNT=0
    
    echo -e "  ${GREEN}Examples:${NC}"
    echo -e "  • Single: ${YELLOW}8080${NC}"
    echo -e "  • Range: ${YELLOW}1000-2000${NC}"
    echo -e "  • Custom: ${YELLOW}5000=8080${NC}"
    echo -e "  • Comma: ${YELLOW}80,443,8080${NC}"
    echo -e "  • Range Map: ${YELLOW}1000-1010=2000-2010${NC}"
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
        
        # Range with mapping (e.g., 1000-1010=2000-2010)
        elif [[ "$port_input" =~ ^([0-9]+)-([0-9]+)=([0-9]+)-([0-9]+)$ ]]; then
            start1=${BASH_REMATCH[1]}
            end1=${BASH_REMATCH[2]}
            start2=${BASH_REMATCH[3]}
            end2=${BASH_REMATCH[4]}
            
            if [ $((end1-start1)) -eq $((end2-start2)) ]; then
                for ((i=0; i<=end1-start1; i++)); do
                    _add_mapping "$PROTO" $((start1+i)) $((start2+i))
                done
                echo -e "${GREEN}    ✓ Range map added ($((end1-start1+1)) ports)${NC}"
            else
                echo -e "${RED}    Error: Range sizes don't match${NC}"
            fi
        
        # Simple range (e.g., 1000-2000)
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
        
        # Custom mapping (e.g., 5000=8080)
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
            # Aggressive profile - maximum throughput
            SMUX_KEEPALIVE=3
            SMUX_MAX_RECV=33554432
            SMUX_MAX_STREAM=33554432
            SMUX_FRAME_SIZE=65536
            KCP_INTERVAL=5
            KCP_SNDWND=4096
            KCP_RCVWND=4096
            MTU_VALUE=1400
            DNS_SERVERS="8.8.8.8,1.1.1.1"
            TCP_KEEPALIVE=20
            ;;
        latency)
            # Latency profile - optimized for gaming/voip
            SMUX_KEEPALIVE=5
            SMUX_MAX_RECV=16777216
            SMUX_MAX_STREAM=16777216
            SMUX_FRAME_SIZE=32768
            KCP_INTERVAL=10
            KCP_SNDWND=2048
            KCP_RCVWND=2048
            MTU_VALUE=1350
            DNS_SERVERS="8.8.8.8,1.1.1.1"
            TCP_KEEPALIVE=30
            ;;
        *)
            # Balanced profile - default
            SMUX_KEEPALIVE=4
            SMUX_MAX_RECV=25165824
            SMUX_MAX_STREAM=25165824
            SMUX_FRAME_SIZE=49152
            KCP_INTERVAL=8
            KCP_SNDWND=3072
            KCP_RCVWND=3072
            MTU_VALUE=1450
            DNS_SERVERS="8.8.8.8,1.1.1.1"
            TCP_KEEPALIVE=25
            ;;
    esac
    
    # Common settings
    SMUX_VERSION=2
    KCP_NODELAY=1
    KCP_RESEND=2
    KCP_NC=1
    
    # Advanced TCP settings
    TCP_NODELAY=true
    TCP_READ_BUFFER=16777216
    TCP_WRITE_BUFFER=16777216
    MAX_CONNECTIONS=10000
    CONNECTION_TIMEOUT=60
    STREAM_TIMEOUT=300
    
    # Obfuscation
    OBFUSCATION=true
    OBFUSCATION_MIN_PAD=32
    OBFUSCATION_MAX_PAD=1024
    
    # HTTP mimic
    FAKE_DOMAIN="www.google.com"
    FAKE_PATH="/search"
    USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    
    # Load balancer (for client)
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
    
    read -p "  DNS Servers (comma separated) [$DNS_SERVERS]: " new_dns
    DNS_SERVERS=${new_dns:-$DNS_SERVERS}
    
    echo -e "${YELLOW}SMUX (TCP Mux):${NC}"
    read -p "  Keepalive interval (seconds) [$SMUX_KEEPALIVE]: " new_ka
    SMUX_KEEPALIVE=${new_ka:-$SMUX_KEEPALIVE}
    
    read -p "  Frame size [$SMUX_FRAME_SIZE]: " new_frame
    SMUX_FRAME_SIZE=${new_frame:-$SMUX_FRAME_SIZE}
    
    echo -e "${YELLOW}KCP:${NC}"
    read -p "  Send window [$KCP_SNDWND]: " new_snd
    KCP_SNDWND=${new_snd:-$KCP_SNDWND}
    
    read -p "  Receive window [$KCP_RCVWND]: " new_rcv
    KCP_RCVWND=${new_rcv:-$KCP_RCVWND}
    
    echo -e "${YELLOW}Obfuscation:${NC}"
    read -p "  Enable obfuscation? (true/false) [$OBFUSCATION]: " new_obf
    OBFUSCATION=${new_obf:-$OBFUSCATION}
    
    echo -e "${YELLOW}HTTP Mimic:${NC}"
    read -p "  Fake domain [$FAKE_DOMAIN]: " new_domain
    FAKE_DOMAIN=${new_domain:-$FAKE_DOMAIN}
}

# ============================================================================
# TRANSPORT SELECTOR (HTTP Mux only)
# ============================================================================

select_transport() {
    TRANSPORT="httpmux"
    echo -e "  Transport: ${GREEN}httpmux${NC} (only available option)"
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
    
    # Update DNS if specified
    if [[ -n "$DNS_SERVERS" ]]; then
        > /etc/resolv.conf
        IFS=',' read -ra DNS_LIST <<< "$DNS_SERVERS"
        for dns in "${DNS_LIST[@]}"; do
            echo "nameserver $dns" >> /etc/resolv.conf
        done
    fi
    
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
  chunked_encoding: false
  session_cookie: true
YAML
}

# ============================================================================
# COLLECT LISTENERS (Server)
# ============================================================================

collect_listeners() {
    LISTENERS_BLOCK=""
    LISTENER_COUNT=0
    CERT_GENERATED=false

    while true; do
        echo ""
        echo -e "${CYAN}━━━ Listener #$((LISTENER_COUNT+1)) ━━━${NC}"

        select_transport
        
        # Default port 2020
        local default_port=2020
        [[ $LISTENER_COUNT -gt 0 ]] && default_port=$((2020 + LISTENER_COUNT))
        
        read -p "  Listen port [${default_port}]: " listen_port
        listen_port=${listen_port:-$default_port}

        local cert_file=""
        local key_file=""
        
        read -p "  Use SSL? (y/N): " use_ssl
        if [[ "$use_ssl" =~ ^[Yy]$ ]]; then
            read -p "  Certificate domain [$FAKE_DOMAIN]: " cert_domain
            cert_domain=${cert_domain:-$FAKE_DOMAIN}
            
            if [[ "$CERT_GENERATED" != "true" ]]; then
                generate_certificate "$cert_domain"
                CERT_GENERATED=true
            fi
            
            cert_file="$CONFIG_DIR/certs/cert.pem"
            key_file="$CONFIG_DIR/certs/key.pem"
            TRANSPORT="httpsmux"
        fi

        echo ""
        echo -e "${YELLOW}  Configure port mappings for :${listen_port} [${TRANSPORT}]:${NC}"
        collect_port_mappings

        LISTENERS_BLOCK+="  - addr: \"0.0.0.0:${listen_port}\"\n"
        LISTENERS_BLOCK+="    transport: \"${TRANSPORT}\"\n"
        
        if [[ -n "$cert_file" ]]; then
            LISTENERS_BLOCK+="    cert_file: \"${cert_file}\"\n"
            LISTENERS_BLOCK+="    key_file: \"${key_file}\"\n"
        fi
        
        LISTENERS_BLOCK+="    maps:\n"
        
        while IFS= read -r line; do
            [[ -n "$line" ]] && LISTENERS_BLOCK+="    ${line}\n"
        done <<< "$(echo -e "$MAPPINGS")"

        LISTENER_COUNT=$((LISTENER_COUNT+1))
        echo -e "${GREEN}  ✓ Listener #${LISTENER_COUNT}: Port ${listen_port} [${TRANSPORT}] with ${MAP_COUNT} mappings${NC}"

        read -p "  Add another listener? [y/N]: " add_listener
        [[ ! "$add_listener" =~ ^[Yy]$ ]] && break
    done
}

# ============================================================================
# WRITE SERVER CONFIGURATION
# ============================================================================

write_server_config() {
    local config_file="$CONFIG_DIR/server.yaml"
    
    # Read PSK from file
    if [[ -f "$CONFIG_DIR/psk.key" ]]; then
        PSK_VALUE=$(cat "$CONFIG_DIR/psk.key")
    fi
    
    cat > "$config_file" << YAML
mode: server
psk: "${PSK_VALUE}"
profile: "${PROFILE}"
verbose: false
max_sessions: 0
heartbeat: 15

listeners:
YAML

    echo -e "$LISTENERS_BLOCK" >> "$config_file"
    write_shared_config "$config_file"
    
    echo -e "${GREEN}[✓] Server configuration saved: $config_file${NC}"
}

# ============================================================================
# COLLECT CLIENT PATHS (Multi-server support)
# ============================================================================

collect_client_paths() {
    PATHS_BLOCK="paths:"
    PATH_COUNT=0
    
    while true; do
        echo ""
        echo -e "${YELLOW}  Server #$((PATH_COUNT+1)) Configuration${NC}"
        
        select_transport
        
        read -p "  Server address (IP or domain): " server_addr
        [[ -z "$server_addr" ]] && { echo -e "${RED}    Error: Address required${NC}"; continue; }
        
        # Add default port 2020 if not specified
        if [[ ! "$server_addr" =~ :[0-9]+$ ]]; then
            server_addr="${server_addr}:2020"
            echo -e "    Using default port: ${GREEN}2020${NC}"
        fi
        
        read -p "  Connection pool size [3]: " pool_size
        pool_size=${pool_size:-3}
        
        read -p "  Retry interval (seconds) [2]: " retry_interval
        retry_interval=${retry_interval:-2}
        
        read -p "  Dial timeout (seconds) [15]: " dial_timeout
        dial_timeout=${dial_timeout:-15}
        
        read -p "  Weight for load balancing [1]: " server_weight
        server_weight=${server_weight:-1}
        
        PATHS_BLOCK+="
  - transport: \"${TRANSPORT}\"
    addr: \"${server_addr}\"
    connection_pool: ${pool_size}
    retry_interval: ${retry_interval}
    dial_timeout: ${dial_timeout}
    weight: ${server_weight}
    priority: 0"
        
        PATH_COUNT=$((PATH_COUNT+1))
        echo -e "${GREEN}  ✓ Added server: ${server_addr}${NC}"
        
        read -p "  Add another server? [y/N]: " add_server
        [[ ! "$add_server" =~ ^[Yy]$ ]] && break
    done
}

# ============================================================================
# WRITE CLIENT CONFIGURATION
# ============================================================================

write_client_config() {
    local config_file="$CONFIG_DIR/client.yaml"
    
    # Read PSK from file
    if [[ -f "$CONFIG_DIR/psk.key" ]]; then
        PSK_VALUE=$(cat "$CONFIG_DIR/psk.key")
    fi
    
    cat > "$config_file" << YAML
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

    write_shared_config "$config_file"
    
    echo -e "${GREEN}[✓] Client configuration saved: $config_file${NC}"
}

# ============================================================================
# INSTALL SERVER
# ============================================================================

install_server() {
    banner
    mkdir -p "$CONFIG_DIR"
    
    echo -e "${CYAN}━━━ Server Installation (Iran) ━━━${NC}"
    echo -e "${YELLOW}This will configure the Iran side server${NC}\n"
    
    setup_psk
    
    echo ""
    echo "  Installation Mode:"
    echo "    1) Single Listener (recommended)"
    echo "    2) Multi-Listener (multiple ports)"
    echo "    3) Manual Configuration"
    
    read -p "  Choice [1]: " install_mode
    
    select_profile
    
    case $install_mode in
        2|3)
            collect_listeners
            ;;
        *)
            select_transport
            
            read -p "  Tunnel port [2020]: " tunnel_port
            tunnel_port=${tunnel_port:-2020}
            
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
            
            echo ""
            echo -e "${CYAN}━━━ Port Mappings ━━━${NC}"
            collect_port_mappings
            
            LISTENERS_BLOCK="  - addr: \"0.0.0.0:${tunnel_port}\"\n    transport: \"${TRANSPORT}\"\n"
            
            if [[ -n "$cert_file" ]]; then
                LISTENERS_BLOCK+="    cert_file: \"${cert_file}\"\n    key_file: \"${key_file}\"\n"
            fi
            
            LISTENERS_BLOCK+="    maps:\n"
            
            while IFS= read -r line; do
                [[ -n "$line" ]] && LISTENERS_BLOCK+="    ${line}\n"
            done <<< "$(echo -e "$MAPPINGS")"
            
            LISTENER_COUNT=1
            ;;
    esac

    if [[ "$install_mode" == "3" ]]; then
        read -p "  Edit advanced settings? [y/N]: " edit_adv
        [[ $edit_adv =~ ^[Yy]$ ]] && edit_advanced_settings
    fi

    write_server_config
    create_systemd_service "server"

    echo ""
    read -p "  Optimize system? [Y/n]: " optimize_choice
    [[ ! $optimize_choice =~ ^[Nn]$ ]] && optimize_system

    systemctl enable DaggerConnect-server 2>/dev/null
    systemctl start DaggerConnect-server

    echo ""
    echo -e "${GREEN}━━━ Server Installation Complete ━━━${NC}"
    echo -e "  Listeners: ${GREEN}${LISTENER_COUNT}${NC}"
    echo -e "  Profile: ${GREEN}${PROFILE}${NC}"
    echo -e "  PSK: ${GREEN}${PSK_VALUE}${NC}"
    echo -e "  Config: ${CYAN}$CONFIG_DIR/server.yaml${NC}"
    echo -e "  Logs: ${CYAN}journalctl -u DaggerConnect-server -f${NC}"
    echo ""
    
    read -p "Press Enter to continue..."
    main_menu
}

# ============================================================================
# INSTALL CLIENT
# ============================================================================

install_client() {
    banner
    mkdir -p "$CONFIG_DIR"
    
    echo -e "${CYAN}━━━ Client Installation (Kharej) ━━━${NC}"
    echo -e "${YELLOW}This will configure the Kharej side client${NC}"
    echo -e "${YELLOW}Can connect to multiple Iran servers${NC}\n"
    
    setup_psk

    select_profile
    collect_client_paths

    if [[ $PATH_COUNT -gt 1 ]]; then
        echo ""
        echo -e "${YELLOW}  Load Balancer Strategy:${NC}"
        echo "    1) Round Robin (default)"
        echo "    2) Least Loaded"
        echo "    3) Failover"
        echo "    4) Weighted Random"
        
        read -p "    Choice [1]: " lb_choice
        
        case $lb_choice in
            2) LB_STRATEGY="least_loaded" ;;
            3) LB_STRATEGY="failover" ;;
            4) LB_STRATEGY="weighted_random" ;;
            *) LB_STRATEGY="round_robin" ;;
        esac
    fi

    read -p "  Edit advanced settings? [y/N]: " edit_adv
    [[ $edit_adv =~ ^[Yy]$ ]] && edit_advanced_settings

    write_client_config
    create_systemd_service "client"

    echo ""
    read -p "  Optimize system? [Y/n]: " optimize_choice
    [[ ! $optimize_choice =~ ^[Nn]$ ]] && optimize_system

    systemctl enable DaggerConnect-client 2>/dev/null
    systemctl start DaggerConnect-client

    echo ""
    echo -e "${GREEN}━━━ Client Installation Complete ━━━${NC}"
    echo -e "  Servers: ${GREEN}${PATH_COUNT}${NC}"
    echo -e "  Load Balancer: ${GREEN}${LB_STRATEGY}${NC}"
    echo -e "  Profile: ${GREEN}${PROFILE}${NC}"
    echo -e "  PSK: ${GREEN}${PSK_VALUE}${NC}"
    echo -e "  Config: ${CYAN}$CONFIG_DIR/client.yaml${NC}"
    echo -e "  Logs: ${CYAN}journalctl -u DaggerConnect-client -f${NC}"
    echo ""
    
    read -p "Press Enter to continue..."
    main_menu
}

# ============================================================================
# UPDATE BINARY
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
    
    systemctl stop DaggerConnect-server 2>/dev/null
    systemctl stop DaggerConnect-client 2>/dev/null
    
    download_binary
    
    local new_version=$(get_current_version)
    echo -e "  Updated to: ${GREEN}$new_version${NC}"
    
    systemctl start DaggerConnect-server 2>/dev/null
    systemctl start DaggerConnect-client 2>/dev/null
    
    echo ""
    read -p "Press Enter..."
    main_menu
}

# ============================================================================
# CHANGE MTU
# ============================================================================

change_mtu() {
    echo ""
    echo -e "${CYAN}━━━ Change MTU ━━━${NC}"
    echo -e "Current MTU values in configs:"
    
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
        echo -e "${GREEN}[✓] MTU changed to $new_mtu${NC}"
    else
        echo -e "${RED}Error: Invalid MTU value (must be 576-1500)${NC}"
    fi
    
    echo ""
    read -p "Press Enter..."
    main_menu
}

# ============================================================================
# CHANGE DNS
# ============================================================================

change_dns() {
    echo ""
    echo -e "${CYAN}━━━ Change DNS ━━━${NC}"
    echo -e "Current DNS servers:"
    
    if [[ -f /etc/resolv.conf ]]; then
        grep "^nameserver" /etc/resolv.conf | while read line; do
            echo -e "  ${GREEN}$line${NC}"
        done
    fi
    
    echo ""
    read -p "  Enter DNS servers (comma separated) [8.8.8.8,1.1.1.1]: " new_dns
    new_dns=${new_dns:-"8.8.8.8,1.1.1.1"}
    
    # Update resolv.conf
    > /etc/resolv.conf
    IFS=',' read -ra DNS_LIST <<< "$new_dns"
    for dns in "${DNS_LIST[@]}"; do
        dns=$(echo "$dns" | tr -d ' ')
        echo "nameserver $dns" >> /etc/resolv.conf
    done
    
    echo -e "${GREEN}[✓] DNS updated${NC}"
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
    
    # Stop services
    systemctl stop DaggerConnect-server 2>/dev/null
    systemctl stop DaggerConnect-client 2>/dev/null
    
    # Disable services
    systemctl disable DaggerConnect-server 2>/dev/null
    systemctl disable DaggerConnect-client 2>/dev/null
    
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
        echo ""
    fi
    
    echo -e "${CYAN}━━━ Main Menu (HTTP Mux Only) ━━━${NC}"
    echo ""
    echo "  1) Install Server (Iran side)"
    echo "  2) Install Client (Kharej side - Multi-server)"
    echo "  3) Update Core"
    echo "  4) System Optimizer"
    echo "  5) Change MTU"
    echo "  6) Change DNS"
    echo "  7) Uninstall"
    echo ""
    echo "  0) Exit"
    echo ""
    
    read -p "  Choice: " menu_choice
    
    case $menu_choice in
        1) install_server ;;
        2) install_client ;;
        3) update_core ;;
        4) optimize_system; read -p "Press Enter..."; main_menu ;;
        5) change_mtu ;;
        6) change_dns ;;
        7) uninstall ;;
        0) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) main_menu ;;
    esac
}

# ============================================================================
# SCRIPT START
# ============================================================================

# Check root privileges
check_root

# Show banner
banner

# Install dependencies if needed
install_dependencies

# Download binary if not present
if [[ ! -f "$INSTALL_DIR/DaggerConnect" ]]; then
    echo -e "${YELLOW}DaggerConnect binary not found. Installing...${NC}"
    download_binary
    echo ""
fi

# Start main menu
main_menu
