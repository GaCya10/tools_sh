#!/bin/bash

CMD=$1
DOMAIN=$2
PASSWORD=$3

CONFIG_FILE=/usr/local/etc/trojan/config.json

_sep() {
    echo "======== $1==========="
}

_sep "prepare"
$CMD update -y
$CMD install openssl


_sep "install bbr"
result=$(lsmod | grep bbr)
if [ "$result" = "" ]; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    result=$(lsmod | grep bbr)
    if [[ "$result" = "" ]]; then
        if [[ "$CMD" = "apt" ]]; then
            $CMD install -y  --install-recommends linux-generic-hwe-16.04
            grub-set-default 0
            echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
        fi
    fi    
 fi
    
_sep "install Nginx"
if [ $CMD = "yum" ]; then
    $CMD install -y epel-release
    if [ $? != "0" ]; then
        echo '[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true' > /etc/yum.repos.d/nginx.repo
    fi
fi
$CMD install -y nginx
if [ $? != "0" ]; then
    _sep " install nginx failed."
    exit 1
fi
systemctl enable nginx

_sep "get cert"
systemctl stop nginx
$CMD install -y socat openssl
if [ $CMD = "yum" ]; then
    $CMD install -y cronie
    systemctl start crond
    systemctl enable crond
else
    $CMD install -y cron
    systemctl start cron
    systemctl enable cron
fi

curl -sL https://get.acme.sh |sh
source ~/.bashrc
~/.acme.sh/acme.sh --register-account -m "jiacya@gmail.com"
~/.acme.sh/acme.sh --upgrade --auto-upgrade
~/.acme.sh/acme.sh --force --issue -d $DOMAIN --keylength ec-256 --pre-hook "systemctl stop nginx" --post-hook "systemctl restart nginx"  --standalone
if [ ! -f ~/.acme.sh/${DOMAIN}_ecc/ca.cer ]; then
    _sep " get cert failed"
    exit 1
fi
mkdir -p /usr/local/etc/trojan/
CERT_FILE="/usr/local/etc/trojan/${DOMAIN}.pem"
KEY_FILE="/usr/local/etc/trojan/${DOMAIN}.key"
~/.acme.sh/acme.sh  --install-cert -d $DOMAIN --ecc \
    --key-file       $KEY_FILE  \
    --fullchain-file $CERT_FILE \
    --reloadcmd     "service nginx force-reload"
[[ -f $CERT_FILE && -f $KEY_FILE ]] || {
    _sep " get cert2 failed"
    exit 1
}

_sep "config nginx"
mkdir -p /usr/share/nginx/html
if [ ! -f /etc/nginx/nginx.conf.bak ]; then
     mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
fi
res=$(id nginx 2>/dev/null)
if [[ "$?" != "0" ]]; then
    user="www-data"
else
    user="nginx"
fi
cat > /etc/nginx/nginx.conf<<-EOF
user $user;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;
    gzip                on;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    # See http://nginx.org/en/docs/ngx_core_module.html#include
    # for more information.
    include /etc/nginx/conf.d/*.conf;
}
EOF

NGINX_CONFIG="/etc/nginx/conf.d/"
mkdir -p $NGING_CONFIG
c=${NGINX_CONFIG}${DOMAIN}.conf
touch $c
cat > $c <<-EOF
server {
    listen 80;
    listen [::]:80;
    listen 81 http2;
    server_name ${DOMAIN};
    root /usr/share/nginx/html;
    location / {
        proxy_ssl_server_name on;
        proxy_pass "https://www.spotify.com";
        proxy_set_header Accept-Encoding '';
        sub_filter "www.spotify.com" "$DOMAIN";
        sub_filter_once off;
    }
    location = /robots.txt {}
}
EOF

systemctl -restart nginx

_sep "install trojan"
NAME=trojan
VERSION=$(curl -fsSL https://api.github.com/repos/trojan-gfw/trojan/releases/latest | grep tag_name | sed -E 's/.*"v(.*)".*/\1/')
TARBALL="$NAME-$VERSION-linux-amd64.tar.xz"
DOWNLOADURL="https://github.com/trojan-gfw/$NAME/releases/download/v$VERSION/$TARBALL"
TMPDIR="$(mktemp -d)"
INSTALLPREFIX=/usr/local
SYSTEMDPREFIX=/etc/systemd/system

BINARYPATH="$INSTALLPREFIX/bin/$NAME"
CONFIGPATH="$INSTALLPREFIX/etc/$NAME/config.json"
SYSTEMDPATH="$SYSTEMDPREFIX/$NAME.service"

echo Entering temp directory $TMPDIR...
cd "$TMPDIR"

echo Downloading $NAME $VERSION...
curl -LO --progress-bar "$DOWNLOADURL" || wget -q --show-progress "$DOWNLOADURL"

echo Unpacking $NAME $VERSION...
tar xf "$TARBALL"
cd "$NAME"

echo Installing $NAME $VERSION to $BINARYPATH...
install -Dm755 "$NAME" "$BINARYPATH"

echo Installing $NAME server config to $CONFIGPATH...
if ! [[ -f "$CONFIGPATH" ]] || prompt "The server config already exists in $CONFIGPATH, overwrite?"; then
    install -Dm644 examples/server.json-example "$CONFIGPATH"
else
    echo Skipping installing $NAME server config...
fi

if [[ -d "$SYSTEMDPREFIX" ]]; then
    echo Installing $NAME systemd service to $SYSTEMDPATH...
    if ! [[ -f "$SYSTEMDPATH" ]] || prompt "The systemd service already exists in $SYSTEMDPATH, overwrite?"; then
        cat > "$SYSTEMDPATH" << EOF
[Unit]
Description=$NAME
Documentation=https://trojan-gfw.github.io/$NAME/config https://trojan-gfw.github.io/$NAME/
After=network.target network-online.target nss-lookup.target mysql.service mariadb.service mysqld.service

[Service]
Type=simple
StandardError=journal
ExecStart="$BINARYPATH" "$CONFIGPATH"
ExecReload=/bin/kill -HUP \$MAINPID
LimitNOFILE=51200
Restart=on-failure
RestartSec=1s

[Install]
WantedBy=multi-user.target
EOF

        echo Reloading systemd daemon...
        systemctl daemon-reload
    else
        echo Skipping installing $NAME systemd service...
    fi
fi

echo Deleting temp directory $TMPDIR...
rm -rf "$TMPDIR"

ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime


touch $CONFIG_FILE
cat >$CONFIG_FILE<<-EOF
{
    "run_type": "server",
    "local_addr": "::",
    "local_port": 443,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "$PASSWORD"
    ],
    "log_level": 1,
    "ssl": {
        "cert": "/usr/local/etc/trojan/${DOMAIN}.pem",
        "key": "/usr/local/etc/trojan/${DOMAIN}.key",
        "key_password": "",
	    "sni": "$DOMAIN",
        "cipher": "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384",
        "cipher_tls13": "TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384",
        "prefer_server_cipher": true,
        "alpn": [
            "http/1.1", "h2"
        ],
        "alpn_port_override": {
            "h2": 81
        },
        "reuse_session": true,
        "session_ticket": false,
        "session_timeout": 600,
        "plain_http_response": "",
        "curves": "",
        "dhparam": ""
    },
    "tcp": {
        "prefer_ipv4": false,
        "no_delay": true,
        "keep_alive": true,
        "reuse_port": false,
        "fast_open": false,
        "fast_open_qlen": 20
    },
    "mysql": {
        "enabled": false,
        "server_addr": "127.0.0.1",
        "server_port": 3306,
        "database": "trojan",
        "username": "trojan",
        "password": "",
        "key": "",
        "cert": "",
        "ca": ""
    }
}
EOF

systemctl enable trojan
systemctl restart trojan

_sep "Finish! Done!"
