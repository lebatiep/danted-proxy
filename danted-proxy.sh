#!/bin/bash
set -e

echo "🚀 Bắt đầu cài đặt Dante SOCKS5 Proxy..."

# ==========================
# 1. Cập nhật hệ thống
# ==========================
echo "[1/10] Cập nhật hệ thống & cài đặt gói cần thiết..."
apt update -y && apt upgrade -y
apt install -y dante-server dnsutils curl cron nano ufw logrotate

# ==========================
# 2. Tạo swap 2GB
# ==========================
echo "[2/10] Tạo swap 2GB..."
SWAPFILE="/swapfile"
if [ ! -f $SWAPFILE ]; then
    fallocate -l 2G $SWAPFILE
    chmod 600 $SWAPFILE
    mkswap $SWAPFILE
    swapon $SWAPFILE
    echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
else
    echo "Swap đã tồn tại, bỏ qua."
fi

# ==========================
# 3. Xác định interface mạng
# ==========================
echo "[3/10] Xác định interface mạng..."
IFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
echo "Interface mạng: $IFACE"

# ==========================
# 4. Viết cấu hình Dante ban đầu
# ==========================
echo "[4/10] Viết cấu hình /etc/danted.conf..."
cat > /etc/danted.conf <<EOF
logoutput: /var/log/danted.log
internal: $IFACE port = 1080
external: $IFACE

socksmethod: none
user.privileged: proxy
user.notprivileged: nobody

# Chặn mặc định
block {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}
EOF

# ==========================
# 5. Tạo template & script cập nhật
# ==========================
echo "[5/10] Tạo template và script cập nhật..."

cp /etc/danted.conf /etc/danted.conf.template

cat > /usr/local/bin/update-danted.sh <<'EOL'
#!/bin/bash
DOMAINS=("nhahqv23jvtr.duckdns.org" "nhahqv6349fal342hcx23.duckdns.org")
TEMPLATE="/etc/danted.conf.template"
CONFIG="/etc/danted.conf"

cp "$TEMPLATE" "$CONFIG"

for DOMAIN in "${DOMAINS[@]}"; do
    IP=$(dig +short $DOMAIN @8.8.8.8 | tail -n 1)
    if [[ -n "$IP" ]]; then
        echo "Cập nhật $DOMAIN -> $IP"
        echo "client pass { from: $IP/32 to: 0.0.0.0/0 }" >> "$CONFIG"
        echo "socks pass { from: $IP/32 to: 0.0.0.0/0 }" >> "$CONFIG"
    else
        echo "⚠️ Không lấy được IP từ $DOMAIN"
    fi
done

systemctl restart danted
EOL

chmod +x /usr/local/bin/update-danted.sh

# ==========================
# 6. Cron job auto update
# ==========================
echo "[6/10] Thêm cron job auto update mỗi 5 phút..."
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/update-danted.sh") | crontab -

# ==========================
# 7. Systemd override để auto-restart
# ==========================
echo "[7/10] Tạo systemd override cho danted..."
mkdir -p /etc/systemd/system/danted.service.d
cat > /etc/systemd/system/danted.service.d/override.conf <<EOF
[Service]
Restart=always
RestartSec=3
EOF
systemctl daemon-reexec

# ==========================
# 8. Logrotate
# ==========================
echo "[8/10] Cấu hình logrotate..."
cat > /etc/logrotate.d/danted <<EOF
/var/log/danted.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 proxy adm
    postrotate
        systemctl reload danted >/dev/null 2>&1 || true
    endscript
}
EOF

# ==========================
# 9. Mở port bằng UFW
# ==========================
echo "[9/10] Mở port UFW (22 và 1080)..."
ufw allow 22/tcp
ufw allow 1080/tcp
ufw --force enable

# ==========================
# 10. Reload & enable danted
# ==========================
echo "[10/10] Hoàn tất! Khởi động dịch vụ..."
/usr/local/bin/update-danted.sh
systemctl enable danted
systemctl restart danted

echo "✅ Hoàn thành! Kiểm tra trạng thái:"
systemctl status danted --no-pager
