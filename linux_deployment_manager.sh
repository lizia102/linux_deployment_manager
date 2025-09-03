#!/bin/bash

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以root权限运行此脚本"
  exit 1
fi

# 设置变量
SERVER_NAME="your_server_name.com"  # 请替换为您的服务器域名
SERVER_IP="your_server_ip"  # 请替换为您的服务器IP地址
NETWORK="192.168.1.0"  # 请替换为您的网络地址
NETMASK="255.255.255.0"  # 请替换为您的子网掩码
RANGE_START="192.168.1.100"  # DHCP地址池起始
RANGE_END="192.168.1.200"  # DHCP地址池结束
ROUTER="192.168.1.1"  # 请替换为您的路由器IP

# 函数：安装基本软件包
install_packages() {
    # 对于RHEL/CentOS系统
    if [ -f /etc/redhat-release ]; then
        dnf install -y httpd mod_ssl tftp-server syslinux grub2-efi-x64 shim-x64 openssl bind bind-utils dhcp-server
    # 对于SUSE系统
    elif [ -f /etc/SuSE-release ] || [ -f /etc/SUSE-brand ]; then
        zypper install -y apache2 tftp grub2-x86_64-efi shim openssl bind dhcp-server syslinux
    else
        echo "不支持的操作系统"
        exit 1
    fi
}

# 函数：配置RHEL服务器
configure_rhel_servers() {
    local version=$1
    local http_root="/var/www/html/rhel$version"
    local https_root="/var/www/html/rhel$version-secure"
    local tftp_root="/var/lib/tftpboot"
    local iso_path="/path/to/rhel$version.iso"  # 请确保ISO文件存在

    # 配置HTTP服务器
    mkdir -p $http_root
    mount -o loop $iso_path $http_root

    # 为HTTP Boot配置GRUB
    mkdir -p $http_root/boot/grub2
    cp /boot/efi/EFI/redhat/grubx64.efi $http_root/boot/grub2/
    cp /boot/grub2/fonts/unicode.pf2 $http_root/boot/grub2/

    # 创建GRUB配置文件
    cat << EOF > $http_root/boot/grub2/grub.cfg
set timeout=60

menuentry 'Install Red Hat Enterprise Linux $version (HTTP)' --class fedora --class gnu-linux --class gnu --class os {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=http://${SERVER_NAME}${http_root} inst.repo=http://${SERVER_NAME}${http_root}
    initrdefi /images/pxeboot/initrd.img
}

menuentry 'Install Red Hat Enterprise Linux $version (HTTPS)' --class fedora --class gnu-linux --class gnu --class os {
    linuxefi /images/pxeboot/vmlinuz inst.stage2=https://${SERVER_NAME}${https_root} inst.repo=https://${SERVER_NAME}${https_root}
    initrdefi /images/pxeboot/initrd.img
}
EOF

    # 配置HTTPS服务器
    mkdir -p $https_root
    cp -R $http_root/* $https_root/

    # 配置TFTP服务器（用于PXE）
    mkdir -p $tftp_root/{boot,EFI/BOOT}
    cp /boot/efi/EFI/redhat/shimx64.efi $tftp_root/EFI/BOOT/BOOTX64.EFI
    cp /boot/efi/EFI/redhat/grubx64.efi $tftp_root/EFI/BOOT/grubx64.efi

    # 创建PXE的GRUB配置文件
    cat << EOF > $tftp_root/EFI/BOOT/grub.cfg
set timeout=60

menuentry 'Install Red Hat Enterprise Linux $version (HTTP PXE)' --class fedora --class gnu-linux --class gnu --class os {
    linuxefi /boot/vmlinuz inst.stage2=http://${SERVER_NAME}${http_root} inst.repo=http://${SERVER_NAME}${http_root}
    initrdefi /boot/initrd.img
}

menuentry 'Install Red Hat Enterprise Linux $version (HTTPS PXE)' --class fedora --class gnu-linux --class gnu --class os {
    linuxefi /boot/vmlinuz inst.stage2=https://${SERVER_NAME}${https_root} inst.repo=https://${SERVER_NAME}${https_root}
    initrdefi /boot/initrd.img
}
EOF

    # 复制内核和initrd到TFTP目录
    cp $http_root/images/pxeboot/{vmlinuz,initrd.img} $tftp_root/boot/
}

# 函数：配置SLES服务器
configure_sles_servers() {
    local version=$1
    local http_root="/srv/www/htdocs/sles$version"
    local https_root="/srv/www/htdocs/sles$version-secure"
    local tftp_root="/srv/tftpboot"
    local iso_path="/path/to/sles$version.iso"  # 请确保ISO文件存在

    # 配置HTTP服务器
    mkdir -p $http_root
    mount -o loop $iso_path $http_root

    # 配置HTTPS服务器
    mkdir -p $https_root
    cp -R $http_root/* $https_root/

    # 配置TFTP服务器（用于PXE）
    mkdir -p $tftp_root/{EFI/BOOT,boot/x86_64/loader}
    cp /usr/share/grub2/x86_64-efi/grub.efi $tftp_root/EFI/BOOT/bootx64.efi
    cp $http_root/boot/x86_64/loader/linux $tftp_root/boot/x86_64/loader/
    cp $http_root/boot/x86_64/loader/initrd $tftp_root/boot/x86_64/loader/

    # 创建PXE的GRUB配置文件
    cat << EOF > $tftp_root/EFI/BOOT/grub.cfg
set timeout=10
menuentry 'Install SUSE Linux Enterprise Server $version (HTTP)' {
    linuxefi /boot/x86_64/loader/linux install=http://${SERVER_NAME}${http_root}
    initrdefi /boot/x86_64/loader/initrd
}
menuentry 'Install SUSE Linux Enterprise Server $version (HTTPS)' {
    linuxefi /boot/x86_64/loader/linux install=https://${SERVER_NAME}${https_root}
    initrdefi /boot/x86_64/loader/initrd
}
EOF

    # 配置HTTP Boot
    mkdir -p $http_root/EFI/BOOT
    cp $tftp_root/EFI/BOOT/{bootx64.efi,grub.cfg} $http_root/EFI/BOOT/

    # 配置HTTPS Boot
    mkdir -p $https_root/EFI/BOOT
    cp $tftp_root/EFI/BOOT/{bootx64.efi,grub.cfg} $https_root/EFI/BOOT/

    # 生成自签名SSL证书（如果不存在）
    if [ ! -f /etc/apache2/ssl.key/server.key ] || [ ! -f /etc/apache2/ssl.crt/server.crt ]; then
        mkdir -p /etc/apache2/ssl.key /etc/apache2/ssl.crt
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
          -keyout /etc/apache2/ssl.key/server.key \
          -out /etc/apache2/ssl.crt/server.crt \
          -subj "/CN=$SERVER_NAME"
    fi
}

# 函数：配置Apache
configure_apache() {
    if [ -f /etc/redhat-release ]; then
        # 对于RHEL/CentOS系统
        cat << EOF > /etc/httpd/conf.d/boot.conf
<VirtualHost *:80>
    ServerName $SERVER_NAME
    DocumentRoot /var/www/html
</VirtualHost>

<VirtualHost *:443>
    ServerName $SERVER_NAME
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile /etc/pki/tls/certs/server.crt
    SSLCertificateKeyFile /etc/pki/tls/private/server.key
</VirtualHost>
EOF
        systemctl restart httpd
    elif [ -f /etc/SuSE-release ] || [ -f /etc/SUSE-brand ]; then
        # 对于SUSE系统
        cat << EOF > /etc/apache2/vhosts.d/boot.conf
<VirtualHost *:80>
    ServerName $SERVER_NAME
    DocumentRoot /srv/www/htdocs
</VirtualHost>

<VirtualHost *:443>
    ServerName $SERVER_NAME
    DocumentRoot /srv/www/htdocs
    SSLEngine on
    SSLCertificateFile /etc/apache2/ssl.crt/server.crt
    SSLCertificateKeyFile /etc/apache2/ssl.key/server.key
</VirtualHost>
EOF
        a2enmod ssl
        systemctl restart apache2
    fi
}


# 函数：配置DNS服务器
configure_dns() {
    cat << EOF > /etc/named.conf
options {
    listen-on port 53 { 127.0.0.1; ${SERVER_IP}; };
    directory       "/var/named";
    dump-file       "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    allow-query     { localhost; ${NETWORK}/${NETMASK}; };
    recursion yes;
    dnssec-enable yes;
    dnssec-validation yes;
};

zone "${SERVER_NAME}" IN {
    type master;
    file "named.${SERVER_NAME}";
    allow-update { none; };
};
EOF

    cat << EOF > /var/named/named.${SERVER_NAME}
\$TTL 86400
@   IN  SOA     ${SERVER_NAME}. root.${SERVER_NAME}. (
        2023011800  ;Serial
        3600        ;Refresh
        1800        ;Retry
        604800      ;Expire
        86400       ;Minimum TTL
)
        IN  NS      ${SERVER_NAME}.
        IN  A       ${SERVER_IP}
EOF

    chown root:named /etc/named.conf /var/named/named.${SERVER_NAME}
    chmod 640 /etc/named.conf /var/named/named.${SERVER_NAME}

    systemctl restart named
}

# 函数：配置DHCP服务器
configure_dhcp() {
    cat << EOF > /etc/dhcp/dhcpd.conf
option space pxelinux;
option pxelinux.magic code 208 = string;
option pxelinux.configfile code 209 = text;
option pxelinux.pathprefix code 210 = text;
option pxelinux.reboottime code 211 = unsigned integer 32;

subnet ${NETWORK} netmask ${NETMASK} {
  range ${RANGE_START} ${RANGE_END};
  option routers ${ROUTER};
  option domain-name-servers ${SERVER_IP};
  option domain-name "${SERVER_NAME}";
  
  class "pxeclients" {
    match if substring (option vendor-class-identifier, 0, 9) = "PXEClient";
    next-server ${SERVER_IP};
    
    if option arch = 00:07 {
      filename "EFI/BOOT/bootx64.efi";
    } else {
      filename "pxelinux.0";
    }
  }
}
EOF

    systemctl restart dhcpd
}

# 函数：配置防火墙
configure_firewall() {
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --permanent --add-service=tftp
        firewall-cmd --permanent --add-service=dns
        firewall-cmd --permanent --add-service=dhcp
        firewall-cmd --reload
    elif command -v SuSEfirewall2 &> /dev/null; then
        SuSEfirewall2 open EXT TCP http
        SuSEfirewall2 open EXT TCP https
        SuSEfirewall2 open EXT UDP tftp
        SuSEfirewall2 open EXT TCP dns
        SuSEfirewall2 open EXT UDP dns
        SuSEfirewall2 open EXT UDP dhcp
        SuSEfirewall2 start
    else
        echo "未找到支持的防火墙管理工具"
    fi
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
        echo "9. 退出"
        read -p "请选择操作 (1-9): " choice

        case $choice in
            1) install_packages ;;
            2) configure_rhel_servers 9 ;;
            3) configure_rhel_servers 10 ;;
            4) configure_sles_servers 15 ;;
            5) configure_apache ;;
            6) configure_dns ;;
            7) configure_dhcp ;;
            8) configure_firewall ;;
            9) exit 0 ;;
            *) echo "无效选择，请重试。" ;;
        esac

        echo "操作完成，按回车键继续..."
        read
    done
}


# 运行主菜单
main_menu
