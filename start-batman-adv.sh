#!/bin/bash

# Load batman-adv module
modprobe batman-adv

# Add these lines after loading batman-adv module
batctl hardif wlan0 gw_mode bandwidth 100000/100000
batctl hardif wlan0 ap_isolation 0
batctl hardif wlan0 hop_penalty 15
batctl hardif wlan0 distributed_arp_table 1
batctl hardif wlan0 fragmentation 1
batctl network coding 1
batctl orig_interval 1000
batctl multicast_mode 1

# Stop any existing services that might interfere
systemctl stop wpa_supplicant

# Start hostapd
systemctl start hostapd

# Configure batman-adv interfaces
batctl if add wlan0
batctl if add eth0

# Set up interfaces
ip link set up dev wlan0
ip link set up dev eth0
ip link set up dev bat0

# Configure IP for bat0 (using different subnet than your existing network)
ip addr add 192.168.100.1/24 dev bat0

# Start DHCP server
systemctl start dnsmasq

# Enable gateway mode
batctl gw_mode server
# Function to check if interface has gateway
check_gateway() {
    local interface=$1
    ip route | grep default | grep $interface > /dev/null
    return $?
}

# Function to update routing
update_routing() {
    # Clear existing default routes in bat0
    ip route del default dev bat0 2>/dev/null || true
    
    # Get current default gateway
    local default_gw=$(ip route | grep default | awk '{print $3}')
    if [ ! -z "$default_gw" ]; then
        # Ensure NAT is configured for the mesh network
        iptables -t nat -F POSTROUTING
        iptables -t nat -A POSTROUTING -s 192.168.100.0/24 ! -d 192.168.100.0/24 -j MASQUERADE
    fi
}

# Monitor gateway availability and update batman-adv accordingly
while true; do
    if check_gateway eth0; then
        batctl gw_mode server
        logger "Batman-adv: Using eth0 as gateway"
        update_routing
    elif check_gateway wlan0; then
        batctl gw_mode server
        logger "Batman-adv: Using wlan0 as gateway"
        update_routing
    else
        batctl gw_mode client
        logger "Batman-adv: Operating in client mode"
    fi
    sleep 10
done &

# Keep script running
exec bash

