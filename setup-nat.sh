#!/bin/bash

# Flush existing rules
iptables -F
iptables -t nat -F
iptables -X
iptables -t nat -X

# Default policies
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Enable NAT for mesh network
iptables -t nat -A POSTROUTING -s 192.168.100.0/24 ! -d 192.168.100.0/24 -j MASQUERADE

# Allow forwarding between interfaces
iptables -A FORWARD -i eth0 -o bat0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i bat0 -o eth0 -j ACCEPT

# Save iptables rules
iptables-save > /etc/iptables.rules 