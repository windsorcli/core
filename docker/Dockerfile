FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install basic dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        unzip \
        ca-certificates \
        docker.io \
        iputils-ping \
        gnupg \
        lsb-release && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Windsor CLI
RUN curl -L -o windsor_0.5.6_linux_amd64.tar.gz https://github.com/windsorcli/cli/releases/download/v0.5.6/windsor_0.5.6_linux_amd64.tar.gz && \
tar -xzf windsor_0.5.6_linux_amd64.tar.gz -C /usr/local/bin && \
chmod +x /usr/local/bin/windsor

# Set Windsor to use manual DNS by default
ENV WINDSOR_DNS_MODE=manual
ENV WINDSOR_DNS_IP=127.0.0.11

# Optional: create non-root user (for CodeBuild compatibility)
RUN useradd -ms /bin/bash ciuser
USER ciuser
WORKDIR /home/ciuser

CMD ["/bin/bash"]
