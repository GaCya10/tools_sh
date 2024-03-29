#!/bin/bash

RED="\033[31m"    # Error message
GREEN="\033[32m"  # Success message
YELLOW="\033[33m" # Warning message
BLUE="\033[36m"   # Info message
PLAIN="\033[0m"

CONFIG_FILE=/usr/local/etc/trojan/config.json
IP=$(curl -sL -4 ip.sb)

__INFO() {
    echo -e "------------- ${GREEN}$1${PLAIN} ------------"
}

__ERR() {
    echo -e "------------- ${RED}$1${PLAIN} ------------"
}

status() {
    if [[ ! -f /usr/local/bin/trojan ]]; then
        echo 0
        return
    fi

    if [[ ! -f $CONFIG_FILE ]]; then
        echo 1
        return
    fi
    port=$(grep local_port $CONFIG_FILE|cut -d: -f2| tr -d \",' ')
    res=$(ss -ntlp| grep ${port} | grep trojan)
    if [[ -z "$res" ]]; then
        echo 2
    else
        echo 3
    fi
}

check() {
    __INFO "start checking system"
    OS=$(hostnamectl | grep System | awk '{print $3}')
    if ! which yum 2>/dev/null; then
        if ! which apt 2>/dev/null; then
            echo "It's not a unix-like system"
            exit 1
        fi
        CMD=apt
        cmd_install="apt install -y "
        cmd_update="apt update -y; apt upgrade -y"
        eval $cmd_update
    else
        CMD=yum
        cmd_install="yum install -y "
        cmd_update="yum update -y"
        $cmd_update
        $cmd_install epel-release
    fi

    if [ "$OS" = "Amazon" ]; then
        $cmd_install util-linux-user amazon-linux-extras install epel -y
    fi
    __INFO "finish checking system"
}

getData() {
    echo ""
    while true
    do
        read -p " Please input domain:" DOMAIN
        if [ -z "${DOMAIN}" ]; then
            echo " Error, please input again"
        else
            break
        fi
    done
    DOMAIN=${DOMAIN,,}
    __INFO "Input Domain: $DOMAIN"

    echo ""
    read -p "Input Password:" PASSWORD
    __INFO " Password: $PASSWORD"

    echo ""
    read -p "Input Email for cert:" EMAIL
    if [ "$EMAIL" = "" ]; then
        EMAIL="gacya10@gmail.com"
    fi
    __INFO " EMAIL: $EMAIL"
}

installBBR() {
    result=$(lsmod | grep bbr)
    if [ "$result" = "" ]; then
        echo "net.core.default_qdisc=fq" >>/etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.conf
        sysctl -p
        result=$(lsmod | grep bbr)
        if [[ "$result" = "" ]]; then
            if [[ "$CMD" = "apt" ]]; then
                $CMD install -y --install-recommends linux-generic-hwe-16.04
                grub-set-default 0
                echo "tcp_bbr" >>/etc/modules-load.d/modules.conf
            fi
        fi
    fi
}

installNginx() {
    if [ $CMD = "yum" ]; then
        $CMD install -y epel-release
        if [ $? != "0" ]; then
            echo '[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true' >/etc/yum.repos.d/nginx.repo
        fi
    fi
    $CMD install -y nginx
    if [ $? != "0" ]; then
        __ERR " install nginx failed."
        exit 1
    fi
    systemctl enable nginx
}

getCert() {
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

    curl -sL https://get.acme.sh | sh
    source ~/.bashrc
    ~/.acme.sh/acme.sh --register-account -m "${EMAIL}"
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    ~/.acme.sh/acme.sh --force --issue -d "$DOMAIN" --keylength ec-256 --pre-hook "systemctl stop nginx" --post-hook "systemctl restart nginx" --standalone
    if [ ! -f ~/.acme.sh/"${DOMAIN}"_ecc/ca.cer ]; then
        __ERR " get cert failed"
        exit 1
    fi
    mkdir -p /usr/local/etc/trojan/
    CERT_FILE="/usr/local/etc/trojan/${DOMAIN}.pem"
    KEY_FILE="/usr/local/etc/trojan/${DOMAIN}.key"
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc \
        --key-file "$KEY_FILE" \
        --fullchain-file "$CERT_FILE" \
        --reloadcmd "service nginx force-reload"
    [[ -f $CERT_FILE && -f $KEY_FILE ]] || {
        __ERR " get cert2 failed"
        exit 1
    }
    __INFO "finish getting cert"
}

configNginx() {
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
    cat >/etc/nginx/nginx.conf <<-EOF
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

    mkdir -p /usr/share/nginx/html/
    cd /usr/share/nginx/html || exit
    git clone https://github.com/GaCya10/VVVenus.git
    mv VVVenus/css .
    mv VVVenus/first.html .
    mv VVVenus/images .
    mv VVVenus/js .
    rm -rf VVVenus

    NGINX_CONFIG="/etc/nginx/conf.d/"
    mkdir -p ${NGINX_CONFIG}
    c=${NGINX_CONFIG}${DOMAIN}.conf
    touch "$c"
    cat >"$c"<<-EOF
server {
    listen 80;
    listen [::]:80;
    listen 81 http2;
    server_name ${DOMAIN};
    root /usr/share/nginx/html;
    location / {
        index first.html;
    }
    location = /robots.txt {}
}
EOF

    systemctl restart nginx
    __INFO "finish updating nginx config"
}

configUserNginx() {
    
    mkdir -p /usr/share/nginx/html/
    cd /usr/share/nginx/html || exit
    git clone https://github.com/GaCya10/VVVenus.git
    mv VVVenus/css .
    mv VVVenus/first.html .
    mv VVVenus/images .
    mv VVVenus/js .
    rm -rf VVVenus

    DOMAIN=$(grep sni $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
    NGINX_CONFIG="/etc/nginx/conf.d/"
    c=${NGINX_CONFIG}${DOMAIN}.conf
    touch "$c"
    cat >"$c"<<-EOF
server {
    listen 80;
    listen [::]:80;
    listen 81 http2;
    server_name ${DOMAIN};
    root /usr/share/nginx/html;
    location / {
        index first.html;
    }
    location = /robots.txt {}
}
EOF
    nginx -s reload
    __INFO "finish updating nginx config"
}


installTrojan() {
    __INFO "install trojan"
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
            cat >"$SYSTEMDPATH" <<EOF
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
    echo "DONE"

    systemctl enable trojan
    __INFO "finish installing trojan"
}

configTrojan() {
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    touch $CONFIG_FILE
    cat >$CONFIG_FILE <<-EOF
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

    systemctl restart trojan

    __INFO "finish updating trojan config"
}

showInfo() {
    res=$(netstat -nltp | grep trojan)
    [[ -z "$res" ]] && status="${RED}Stopped${PLAIN}" || status="${GREEN}Running${PLAIN}"
    
    domain=$(grep sni $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
    if [[ "$domain" = "" ]]; then
        domain=$(grep -m1 cert $CONFIG_FILE | cut -d/ -f5)
    fi
    port=$(grep local_port $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
    line1=$(grep -n 'password' $CONFIG_FILE  | head -n1 | cut -d: -f1)
    line11=$(expr $line1 + 1)
    password=$(sed -n "${line11}p" $CONFIG_FILE | tr -d \",' ')
    
    res=$(netstat -nltp | grep ${port} | grep nginx)
    [[ -z "$res" ]] && ngstatus="${RED}Stopped${PLAIN}" || ngstatus="${GREEN}Running${PLAIN}"
    
    echo ============================================
    echo -e " ${BLUE}trojan status: ${PLAIN}${status}"
    echo ""
    echo -e " ${BLUE}trojan config file: ${PLAIN}${RED}$CONFIG_FILE${PLAIN}"
    echo -e " ${BLUE}trojan config info: ${PLAIN}               "
    echo -e "   ${BLUE}IP/address: ${PLAIN} ${RED}$IP${PLAIN}"
    echo -e "   ${BLUE}Domain/SNI/peer: ${PLAIN}  ${RED}${domain}${PLAIN}"
    echo -e "   ${BLUE}Port: ${PLAIN}${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}Password: ${PLAIN}${RED}$password${PLAIN}"
    echo  
    echo ============================================
}

showLog() {
    res=$(status)
    if [[ $res -lt 2 ]]; then
        echo -e "${RED}Please install Trojan first!${PLAIN}"
        return
    fi

    journalctl -xen -u trojan --no-pager
}

installAll() {
    check
    getData
    installBBR
    installNginx
    getCert
    configNginx
    installTrojan
    configTrojan
    showInfo
}

updateDomain() {
    check
    getData
    configNginx
    getCert
    configTrojan
    showInfo
}

update() {
    check
    installTrojan
}

html() {
    configUserNginx
}

menu() {
    clear
    echo "#############################################################"
    echo -e "#                    ${RED}trojan${PLAIN}                                 #"
    echo -e "# ${GREEN}Anthor${PLAIN}: gacya10@gmail.com                                 #"
    echo "#############################################################"
    echo ""
    echo -e "  ${GREEN}0.${PLAIN}  Install"
    echo -e "  ${GREEN}1.${PLAIN}  Show Info"
    echo -e "  ${GREEN}2.${PLAIN}  Update Domain"
    echo -e "  ${GREEN}3.${RED}  Uninstall Trojan${PLAIN}"
    echo -e "  ${GREEN}4.${PLAIN}  Update Static HTML"
    echo -e "  ${GREEN}5.${PLAIN}  Show Log"
    read -p "please select[0-5]: " option
    case $option in
    0)
        installAll
        ;;
    1)
        showInfo
        ;;
    2)
        updateDomain
        ;;
    3)
        update
        ;;
    4)
        html
        ;;
    5)
        showLog
        ;;
    *)
        echo "others"
        exit 1
        ;;
    esac
}

main() {
    menu

}

main "$@"
