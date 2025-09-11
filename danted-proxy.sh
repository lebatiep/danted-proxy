#!/bin/bash
# Script tự động cài Dante SOCKS5 + swap 2G + auto-restart

set -e

echo "Cài đặt dante-server, ufw..."
apt update && apt install -y dante-server ufw

echo "Xác định interface mạng ..."
IFACE=$(ip route | awk '/default/ {print $5; exit}')

echo "Viết cấu hình /etc/danted.conf..."
cat > /etc/danted.conf <<EOF
logoutput: syslog

internal: 0.0.0.0 port = 1080
external: ${IFACE}

socksmethod: none
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
    command: connect
}
EOF

echo "Cấu hình tự động restart danted khi bị kill..."
mkdir -p /etc/systemd/system/danted.service.d
cat > /etc/systemd/system/danted.service.d/override.conf <<EOF
[Service]
Restart=always
RestartSec=5
EOF

echo "Khởi động lại, bật tự động và mở port..."
systemctl daemon-reexec
systemctl enable danted
systemctl restart danted
ufw allow 1080/tcp

echo "Tạo swap 2GB..."
swapoff -a || true
rm -f /swapfile || true
dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

systemctl restart danted

echo "Hoàn thành! Kiểm tra trạng thái danted:"
systemctl status danted --no-pager
