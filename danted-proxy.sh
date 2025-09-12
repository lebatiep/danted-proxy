#!/bin/bash
set -e

echo "[1/9] Cập nhật hệ thống & cài đặt gói cần thiết..."
apt update -y && apt upgrade -y
apt install -y dante-server ufw net-tools logrotate

echo "[2/9] Tạo swap 2GB..."
if ! swapon --show | grep -q "swapfile"; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
fi

echo "[3/9] Xác định interface mạng..."
IFACE=$(ip route | grep '^default' | awk '{print $5}')
echo "Interface được phát hiện: $IFACE"

echo "[4/9] Viết cấu hình /etc/danted.conf..."
cat > /etc/danted.conf <<EOF
logoutput: /var/log/danted.log
internal: $IFACE port = 1080
external: $IFACE

method: username none
user.privileged: proxy
user.notprivileged: nobody

clientmethod: none
socksmethod: none

client pass {
    from: 42.114.234.66/32 to: 0.0.0.0/0
    log: connect disconnect error
}

client pass {
    from: 183.80.56.6/32 to: 0.0.0.0/0
    log: connect disconnect error
}

client block {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect error
}

pass {
    from: 42.114.234.66/32 to: 0.0.0.0/0
    protocol: tcp udp
}

pass {
    from: 183.80.56.6/32 to: 0.0.0.0/0
    protocol: tcp udp
}

block {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}
EOF

echo "[5/9] Tạo systemd service override để auto-restart..."
mkdir -p /etc/systemd/system/danted.service.d
cat > /etc/systemd/system/danted.service.d/override.conf <<EOF
[Service]
Restart=always
RestartSec=3
EOF

echo "[6/9] Cấu hình logrotate cho syslog & danted.log..."
cat > /etc/logrotate.d/danted <<EOF
/var/log/danted.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 640 root adm
    postrotate
        systemctl reload danted > /dev/null 2>&1 || true
    endscript
}
EOF

cat > /etc/logrotate.d/syslog-clean <<EOF
/var/log/syslog {
    daily
    rotate 5
    compress
    missingok
    notifempty
    size 200M
    create 640 syslog adm
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate || true
    endscript
}
EOF

echo "[7/9] Mở port bằng UFW..."
ufw allow 1080/tcp
ufw allow 1080/udp
ufw --force enable

echo "[8/9] Reload & enable danted..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable danted
systemctl restart danted

echo "[9/9] Hoàn thành! Kiểm tra trạng thái danted:"
systemctl status danted --no-pager -l
