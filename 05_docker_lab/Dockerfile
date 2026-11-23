# ABOUTME: One image for all four emulated Macs: nginx 1.27, dnsmasq, Python 3, and network tools.
# ABOUTME: Each container picks its role from the ROLE environment variable at start.
FROM nginx:1.27.3-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      dnsmasq-base python3 dnsutils iptables iproute2 curl procps openssl \
      netcat-openbsd iputils-ping ca-certificates tcpdump \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/nginx/conf.d/default.conf \
 && sed -i 's/^worker_processes .*/worker_processes 1;/' /etc/nginx/nginx.conf

COPY lab.sh /usr/local/bin/lab
COPY pf-anchor-to-iptables.sh /usr/local/bin/pf-anchor-to-iptables
COPY entrypoint.sh /usr/local/bin/lab-entrypoint
RUN chmod +x /usr/local/bin/lab /usr/local/bin/pf-anchor-to-iptables /usr/local/bin/lab-entrypoint

ENTRYPOINT ["/usr/local/bin/lab-entrypoint"]
