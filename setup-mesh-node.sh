#!/bin/bash

# Exit on any error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Starting mesh node setup...${NC}"

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}Please run as root${NC}"
        exit 1
    fi
}

# Function to install dependencies
install_dependencies() {
    echo "Installing required packages..."
    apt update
    apt install -y \
        docker.io \
        docker-compose \
        batctl \
        bridge-utils \
        hostapd \
        dnsmasq \
        iptables \
        wireless-tools \
        iw

    # Enable required kernel modules
    modprobe batman-adv
    echo 'batman-adv' >> /etc/modules
}

# Create project directory structure
setup_directories() {
    echo "Creating directory structure..."
    mkdir -p /opt/mesh-network/{config,scripts}
    cd /opt/mesh-network
}

# Configure system settings
configure_system() {
    echo "Configuring system settings..."
    # Add sysctl configurations
    cat >> /etc/sysctl.conf << 'EOF'
net.core.wmem_max = 12582912
net.core.rmem_max = 12582912
net.ipv4.tcp_rmem = 10240 87380 12582912
net.ipv4.tcp_wmem = 10240 87380 12582912
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_no_metrics_save = 1
net.core.optmem_max = 25165824
net.ipv4.tcp_mtu_probing = 1
net.ipv4.ip_forward = 1
EOF
    sysctl -p
}

# Create configuration files
create_configs() {
    echo "Creating configuration files..."
    local CURRENT_DIR=$(pwd)
    
    # Create config directory if it doesn't exist
    mkdir -p /opt/mesh-network/config
    mkdir -p /opt/mesh-network/scripts

    # Copy and set permissions for existing configuration files
    if [ -f "${CURRENT_DIR}/hostapd.conf" ]; then
        cp "${CURRENT_DIR}/hostapd.conf" /opt/mesh-network/config/
        chmod 600 /opt/mesh-network/config/hostapd.conf
    else
        echo -e "${RED}hostapd.conf not found in current directory${NC}"
        exit 1
    fi

    if [ -f "${CURRENT_DIR}/dnsmasq.conf" ]; then
        cp "${CURRENT_DIR}/dnsmasq.conf" /opt/mesh-network/config/
        chmod 644 /opt/mesh-network/config/dnsmasq.conf
    else
        echo -e "${RED}dnsmasq.conf not found in current directory${NC}"
        exit 1
    fi

    if [ -f "${CURRENT_DIR}/start-batman-adv.sh" ]; then
        cp "${CURRENT_DIR}/start-batman-adv.sh" /opt/mesh-network/scripts/
        chmod 755 /opt/mesh-network/scripts/start-batman-adv.sh
    else
        echo -e "${RED}start-batman-adv.sh not found in current directory${NC}"
        exit 1
    fi

    if [ -f "${CURRENT_DIR}/setup-nat.sh" ]; then
        cp "${CURRENT_DIR}/setup-nat.sh" /opt/mesh-network/scripts/
        chmod 755 /opt/mesh-network/scripts/setup-nat.sh
    else
        echo -e "${RED}setup-nat.sh not found in current directory${NC}"
        exit 1
    fi

    # Create network interface configurations
    cat > /opt/mesh-network/config/wlan0 << 'EOF'
auto wlan0
iface wlan0 inet manual
    mtu 2304
    txqueuelen 10000
    wireless-power off
EOF
    chmod 644 /opt/mesh-network/config/wlan0

    cat > /opt/mesh-network/config/eth0 << 'EOF'
auto eth0
iface eth0 inet dhcp
    mtu 2304
EOF
    chmod 644 /opt/mesh-network/config/eth0

    cat > /opt/mesh-network/config/bat0 << 'EOF'
auto bat0
iface bat0 inet auto
    pre-up /usr/sbin/batctl if add wlan0
    pre-up /usr/sbin/batctl if add eth0
    pre-up ip link set mtu 2304 dev eth0
EOF
    chmod 644 /opt/mesh-network/config/bat0

    # Create docker-compose.yml in the mesh network directory
    cat > /opt/mesh-network/docker-compose.yml << 'EOF'
version: '3'
services:
  batman:
    build: .
    network_mode: "host"
    privileged: true
    restart: unless-stopped
    volumes:
      - ./config:/etc/network/interfaces.d
      - ./config/hostapd.conf:/etc/hostapd/hostapd.conf
      - ./config/dnsmasq.conf:/etc/dnsmasq.conf
      - /etc/sysctl.conf:/etc/sysctl.conf
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
EOF
    chmod 644 /opt/mesh-network/docker-compose.yml

    # Copy Dockerfile
    if [ -f "${CURRENT_DIR}/Dockerfile" ]; then
        cp "${CURRENT_DIR}/Dockerfile" /opt/mesh-network/
        chmod 644 /opt/mesh-network/Dockerfile
    else
        echo -e "${RED}Dockerfile not found in current directory${NC}"
        exit 1
    fi

    # Set proper ownership for all files
    chown -R root:root /opt/mesh-network

    echo -e "${GREEN}Configuration files created and permissions set${NC}"
}

# Setup systemd service
create_systemd_service() {
    echo "Creating systemd service..."
    cat > /etc/systemd/system/mesh-network.service << 'EOF'
[Unit]
Description=Mesh Network Service
After=docker.service network.target
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=/opt/mesh-network
ExecStartPre=/opt/mesh-network/scripts/setup-nat.sh
ExecStart=/usr/bin/docker-compose up
ExecStop=/usr/bin/docker-compose down
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable mesh-network
}

# Main setup function
main() {
    check_root
    install_dependencies
    setup_directories
    configure_system
    create_configs
    create_systemd_service
    
    echo -e "${GREEN}Setup complete!${NC}"
    echo -e "To start the mesh network, run: ${GREEN}systemctl start mesh-network${NC}"
    echo -e "To check status, run: ${GREEN}systemctl status mesh-network${NC}"
    echo -e "To view logs, run: ${GREEN}journalctl -u mesh-network -f${NC}"
}

# Run main setup
main