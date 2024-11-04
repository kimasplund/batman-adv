FROM ubuntu

# Install required packages
RUN apt update -y && apt install -y \
    batctl \
    net-tools \
    iproute2 \
    iputils-ping \
    wireless-tools

# Configure batman-adv
RUN echo 'batman-adv' | tee --append /etc/modules
RUN echo 'denyinterfaces wlan0' | tee --append /etc/dhcpcd.conf
RUN echo 'denyinterfaces eth0' | tee --append /etc/dhcpcd.conf

# Add network configuration files
ADD bat0 /etc/network/interfaces.d/bat0
ADD wlan0 /etc/network/interfaces.d/wlan0
ADD eth0 /etc/network/interfaces.d/eth0
ADD start-batman-adv.sh /start-batman-adv.sh

# Make script executable
RUN chmod +x /start-batman-adv.sh

CMD ["bash", "/start-batman-adv.sh"]
