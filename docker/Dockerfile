FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install systemd and dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        systemd systemd-sysv \
        systemd-resolved \
        sudo \
        dbus \
        curl \
        iproute2 \
        iputils-ping \
        docker.io \
        ca-certificates \
        gnupg \
        lsb-release \
        unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Enable systemd
STOPSIGNAL SIGRTMIN+3
VOLUME ["/sys/fs/cgroup"]

# Link resolv.conf to systemd-resolved
RUN ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Set up a user (optional, can use root)
RUN useradd -ms /bin/bash ciuser && \
    echo "ciuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install Windsor CLI
RUN curl -L -o windsor_0.5.6_linux_amd64.tar.gz https://github.com/windsorcli/cli/releases/download/v0.5.6/windsor_0.5.6_linux_amd64.tar.gz && \
sudo tar -xzf windsor_0.5.6_linux_amd64.tar.gz -C /usr/local/bin && \
sudo chmod +x /usr/local/bin/windsor

# Start systemd by default
CMD ["/sbin/init"]
