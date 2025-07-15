#!/bin/bash
# Script tự động cài Dante SOCKS5 + user vip2k/111 + swap 2G

set -e

echo "Cài đặt dante-server, ufw..."
apt update && apt install -y dante-server ufw

echo "Tạo user proxy vip2k..."
useradd -M -s /usr/sbin/nologin vip2k || true
echo "vip2k:111" | chpasswd

echo "Xác định interface mạng ..."
IFACE=$(ip route | awk '/default/ {print $5; exit}')

echo "Viết cấu hình /etc/danted.conf..."
cat > /etc/danted.conf <<EOF
logoutput: /var/log/danted.log
internal: \$IFACE port = 1080
external: \$IFACE
method: username
user.notprivileged: nobody
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect
    method: username
}
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect
    method: username
}
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

echo "Hoàn thành! Kiểm tra trạng thái danted:"
systemctl status danted --no-pager
