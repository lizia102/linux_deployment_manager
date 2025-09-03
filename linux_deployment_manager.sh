#!/bin/bash

# 配置文件路径
CONFIG_FILE="config.ini"

# 日志文件路径
LOG_FILE="/var/log/deployment_manager.log"

# 加载配置文件
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "配置文件 $CONFIG_FILE 不存在，将使用默认值"
fi

# 设置默认值
SERVER_NAME=${SERVER_NAME:-"your_server_name_or_ip"}
RHEL9_ISO=${RHEL9_ISO:-"/path/to/rhel9.iso"}
RHEL10_ISO=${RHEL10_ISO:-"/path/to/rhel10.iso"}
SLES15_ISO=${SLES15_ISO:-"/path/to/sles15.iso"}
DOMAIN_NAME=${DOMAIN_NAME:-"example.com"}
NETWORK=${NETWORK:-"192.168.1.0/24"}

# 日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# 执行命令并记录日志
execute_command() {
    "$@"
    if [ $? -ne 0 ]; then
        log_message "错误: 执行 $1 失败"
        echo "错误: 执行 $1 失败，请查看日志 $LOG_FILE"
        return 1
    else
        log_message "成功: 执行 $1"
        return 0
    fi
}

# 权限检查
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "此脚本需要 root 权限运行"
        exit 1
    fi
}

# 安装基本软件包
install_packages() {
    if [ -f /etc/redhat-release ]; then
        execute_command dnf update -y
        execute_command dnf install -y httpd dhcp-server bind tftp-server syslinux
    elif [ -f /etc/SuSE-release ] || [ -f /etc/SUSE-brand ]; then
        execute_command zypper refresh
        execute_command zypper install -y apache2 dhcp-server bind tftp syslinux
    else
        echo "不支持的操作系统"
        exit 1
    fi
    log_message "基本软件包已安装"
}

# 配置 RHEL 服务器
configure_rhel_servers() {
    local version=$1
    local http_root="/var/www/html/rhel$version"
    local https_root="/var/www/html/rhel$version-secure"
    local tftp_root="/var/lib/tftpboot"
    local iso_path

    if [ "$version" == "9" ]; then
        iso_path="$RHEL9_ISO"
    elif [ "$version" == "10" ]; then
        iso_path="$RHEL10_ISO"
    else
        echo "不支持的 RHEL 版本"
        return 1
    fi

    # 检查 ISO 文件是否存在
    if [ ! -f "$iso_path" ]; then
        echo "ISO 文件不存在: $iso_path"
        return 1
    fi

    # 挂载 ISO
    if ! mountpoint -q $http_root; then
        mkdir -p $http_root
        execute_command mount -o loop $iso_path $http_root
    fi

    # 配置 HTTPS 服务器
    mkdir -p $https_root
    cp -R $http_root/* $https_root/

    # 生成自签名 SSL 证书（如果不存在）
    if [ ! -f /etc/pki/tls/private/server.key ] || [ ! -f /etc/pki/tls/certs/server.crt ]; then
        mkdir -p /etc/pki/tls/private /etc/pki/tls/certs
        execute_command openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
          -keyout /etc/pki/tls/private/server.key \
          -out /etc/pki/tls/certs/server.crt \
          -subj "/CN=$SERVER_NAME"
    fi

    # 配置 TFTP 服务器（用于 PXE）
    mkdir -p $tftp_root/{EFI/BOOT,boot}
    cp $http_root/EFI/BOOT/BOOTX64.EFI $tftp_root/EFI/BOOT/
    cp $http_root/images/pxeboot/{vmlinuz,initrd.img} $tftp_root/boot/

    # 创建或追加 GRUB 配置
    cat << EOF >> $tftp_root/EFI/BOOT/grub.cfg

menuentry 'Install Red Hat Enterprise Linux $version (HTTP PXE)' --class fedora --class gnu-linux --class gnu --class os {
    linuxefi /boot/vmlinuz inst.stage2=http://${SERVER_NAME}${http_root} inst.repo=http://${SERVER_NAME}${http_root}
    initrdefi /boot/initrd.img
}

menuentry 'Install Red Hat Enterprise Linux $version (HTTPS PXE)' --class fedora --class gnu-linux --class gnu --class os {
    linuxefi /boot/vmlinuz inst.stage2=https://${SERVER_NAME}${https_root} inst.repo=https://${SERVER_NAME}${https_root}
    initrdefi /boot/initrd.img
}
EOF

    # 配置 HTTP Boot
    mkdir -p $http_root/EFI/BOOT
    cp $tftp_root/EFI/BOOT/{BOOTX64.EFI,grub.cfg} $http_root/EFI/BOOT/

    # 配置 HTTPS Boot
    mkdir -p $https_root/EFI/BOOT
    cp $tftp_root/EFI/BOOT/{BOOTX64.EFI,grub.cfg} $https_root/EFI/BOOT/

    log_message "RHEL $version 服务器配置完成"
}

# 配置 SLES 服务器
configure_sles_servers() {
    local version=$1
    local http_root="/var/www/html/sles$version"
    local https_root="/var/www/html/sles$version-secure"
    local tftp_root="/var/lib/tftpboot"
    local iso_path="$SLES15_ISO"

    # 检查 ISO 文件是否存在
    if [ ! -f "$iso_path" ]; then
        echo "ISO 文件不存在: $iso_path"
        return 1
    fi

    # 挂载 ISO
    if ! mountpoint -q $http_root; then
        mkdir -p $http_root
        execute_command mount -o loop $iso_path $http_root
    fi

    # 配置 HTTPS 服务器
    mkdir -p $https_root
    cp -R $http_root/* $https_root/

    # 配置 TFTP 服务器（用于 PXE）
    mkdir -p $tftp_root/{EFI/BOOT,boot}
    cp $http_root/EFI/BOOT/BOOTX64.EFI $tftp_root/EFI/BOOT/
    cp $http_root/boot/x86_64/{linux,initrd} $tftp_root/boot/

    # 创建或追加 GRUB 配置
    cat << EOF >> $tftp_root/EFI/BOOT/grub.cfg

menuentry 'Install SUSE Linux Enterprise Server $version (HTTP PXE)' --class suse --class gnu-linux --class gnu --class os {
    linuxefi /boot/linux install=http://${SERVER_NAME}${http_root}
    initrdefi /boot/initrd
}

menuentry 'Install SUSE Linux Enterprise Server $version (HTTPS PXE)' --class suse --class gnu-linux --class gnu --class os {
    linuxefi /boot/linux install=https://${SERVER_NAME}${https_root}
    initrdefi /boot/initrd
}
EOF

    # 配置 HTTP Boot
    mkdir -p $http_root/EFI/BOOT
    cp $tftp_root/EFI/BOOT/{BOOTX64.EFI,grub.cfg} $http_root/EFI/BOOT/

    # 配置 HTTPS Boot
    mkdir -p $https_root/EFI/BOOT
    cp $tftp_root/EFI/BOOT/{BOOTX64.EFI,grub.cfg} $https_root/EFI/BOOT/

    log_message "SLES $version 服务器配置完成"
}

# 配置 Apache
configure_apache() {
    local config_file
    local ssl_cert
    local ssl_key

    if [ -f /etc/redhat-release ]; then
        config_file="/etc/httpd/conf.d/boot.conf"
        ssl_cert="/etc/pki/tls/certs/server.crt"
        ssl_key="/etc/pki/tls/private/server.key"
    elif [ -f /etc/SuSE-release ] || [ -f /etc/SUSE-brand ]; then
        config_file="/etc/apache2/vhosts.d/boot.conf"
        ssl_cert="/etc/apache2/ssl.crt/server.crt"
        ssl_key="/etc/apache2/ssl.key/server.key"
    else
        echo "不支持的操作系统"
        return 1
    fi

    # 备份现有配置
    [ -f $config_file ] && cp $config_file ${config_file}.bak

    # 创建或覆盖 Apache 配置
    cat << EOF > $config_file
<VirtualHost *:80>
    ServerName $SERVER_NAME
    DocumentRoot /var/www/html
</VirtualHost>

<VirtualHost *:443>
    ServerName $SERVER_NAME
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile $ssl_cert
    SSLCertificateKeyFile $ssl_key
</VirtualHost>
EOF

    # 重启 Apache 服务
    if [ -f /etc/redhat-release ]; then
        sed -i 's/^#LoadModule ssl_module/LoadModule ssl_module/' /etc/httpd/conf.modules.d/00-ssl.conf
        execute_command systemctl restart httpd
    elif [ -f /etc/SuSE-release ] || [ -f /etc/SUSE-brand ]; then
        execute_command a2enmod ssl
        execute_command systemctl restart apache2
    fi

    log_message "Apache 配置完成"
}

# 配置 DNS
configure_dns() {
    local config_file="/etc/named.conf"
    local zone_file="/var/named/forward.zone"

    # 备份现有配置
    [ -f $config_file ] && cp $config_file ${config_file}.bak
    [ -f $zone_file ] && cp $zone_file ${zone_file}.bak

    # 配置 named.conf
    cat << EOF > $config_file
options {
    listen-on port 53 { any; };
    directory "/var/named";
    allow-query { any; };
    forwarders { 8.8.8.8; 8.8.4.4; };
};

zone "$DOMAIN_NAME" IN {
    type master;
    file "forward.zone";
};
EOF

    # 配置 zone 文件
    cat << EOF > $zone_file
\$TTL 86400
@   IN  SOA     ns1.$DOMAIN_NAME. admin.$DOMAIN_NAME. (
        $(date +%Y%m%d01)  ;Serial
        3600        ;Refresh
        1800        ;Retry
        604800      ;Expire
        86400       ;Minimum TTL
)
    IN  NS      ns1.$DOMAIN_NAME.
    IN  A       $SERVER_NAME

ns1 IN  A       $SERVER_NAME
EOF

    # 重启 named 服务
    execute_command systemctl restart named

    log_message "DNS 服务器配置完成"
}

# 配置 DHCP
configure_dhcp() {
    local config_file="/etc/dhcp/dhcpd.conf"

    # 备份现有配置
    [ -f $config_file ] && cp $config_file ${config_file}.bak

    # 从 NETWORK 变量中提取网段和掩码
    local subnet=$(echo $NETWORK | cut -d'/' -f1)
    local prefix=$(echo $NETWORK | cut -d'/' -f2)
    local netmask=$(ipcalc -m $NETWORK | cut -d'=' -f2)

    # 配置 DHCP 服务器
    cat << EOF > $config_file
option domain-name "$DOMAIN_NAME";
option domain-name-servers $SERVER_NAME;

default-lease-time 600;
max-lease-time 7200;

subnet $subnet netmask $netmask {
    range $subnet.100 $subnet.200;
    option routers $subnet.1;
    option broadcast-address $subnet.255;
    next-server $SERVER_NAME;
    filename "EFI/BOOT/BOOTX64.EFI";
}
EOF

    # 重启 DHCP 服务
    execute_command systemctl restart dhcpd

    log_message "DHCP 服务器配置完成"
}

# 配置防火墙
configure_firewall() {
    if command -v firewall-cmd &> /dev/null; then
        execute_command firewall-cmd --permanent --add-service=http
        execute_command firewall-cmd --permanent --add-service=https
        execute_command firewall-cmd --permanent --add-service=dns
        execute_command firewall-cmd --permanent --add-service=dhcp
        execute_command firewall-cmd --permanent --add-service=tftp
        execute_command firewall-cmd --reload
    elif command -v ufw &> /dev/null; then
        execute_command ufw allow http
        execute_command ufw allow https
        execute_command ufw allow dns
        execute_command ufw allow 67/udp
        execute_command ufw allow 69/udp
        execute_command ufw reload
    else
        echo "未检测到支持的防火墙，请手动配置防火墙规则。"
    fi

    log_message "防火墙配置完成"
}

# 配置 TFTP 服务
configure_tftp() {
    if [ -f /etc/redhat-release ]; then
        execute_command systemctl enable tftp.socket
        execute_command systemctl start tftp.socket
    elif [ -f /etc/SuSE-release ] || [ -f /etc/SUSE-brand ]; then
        execute_command systemctl enable tftp.service
        execute_command systemctl start tftp.service
    fi
    log_message "TFTP 服务配置完成"
}

# 显示帮助信息
show_help() {
    echo "Linux 部署管理系统帮助"
    echo "----------------------"
    echo "1. 安装基本软件包: 安装 HTTP、DHCP、DNS、TFTP 等服务"
    echo "2. 部署 RHEL 9: 配置 RHEL 9 的 PXE 启动环境"
    echo "3. 部署 RHEL 10: 配置 RHEL 10 的 PXE 启动环境"
    echo "4. 部署 SLES 15: 配置 SLES 15 的 PXE 启动环境"
    echo "5. 配置 Apache: 设置 HTTP/HTTPS 虚拟主机"
    echo "6. 配置 DNS 服务器: 设置域名解析"
    echo "7. 配置 DHCP 服务器: 配置 IP 地址分配"
    echo "8. 配置防火墙: 开放必要的端口"
    echo "9. 配置 TFTP 服务: 设置 TFTP 服务"
    echo "10. 退出"
    echo ""
    echo "注意: 使用此脚本前，请确保已准备好相应的 ISO 文件"
}

# 主菜单
main_menu() {
    while true; do
        echo "=== Linux 部署管理系统 ==="
        echo "1. 安装基本软件包"
        echo "2. 部署 RHEL 9"
        echo "3. 部署 RHEL 10"
        echo "4. 部署 SLES 15"
        echo "5. 配置 Apache"
        echo "6. 配置 DNS 服务器"
        echo "7. 配置 DHCP 服务器"
        echo "8. 配置防火墙"
        echo "9. 配置 TFTP 服务"
        echo "10. 显示帮助信息"
        echo "11. 退出"
        read -p "请选择操作 (1-11): " choice

        case $choice in
            1) install_packages ;;
            2) configure_rhel_servers 9 ;;
            3) configure_rhel_servers 10 ;;
            4) configure_sles_servers 15 ;;
            5) configure_apache ;;
            6) configure_dns ;;
            7) configure_dhcp ;;
            8) configure_firewall ;;
            9) configure_tftp ;;
            10) show_help ;;
            11) exit 0 ;;
            *) echo "无效选择，请重试。" ;;
        esac

        echo "操作完成，按回车键继续..."
        read
    done
}

# 脚本入口
check_root
main_menu
