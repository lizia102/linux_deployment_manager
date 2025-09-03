# Linux 部署管理工具

这是一个用于自动化配置 Linux 网络安装环境的脚本工具，支持通过 PXE、HTTP 和 HTTPS 方式部署 RHEL 9、RHEL 10 和 SLES 15 操作系统。

## 功能介绍

该工具可以自动配置以下服务，构建完整的网络安装环境：
- HTTP/HTTPS 服务器（Apache）
- DHCP 服务器（自动分配 IP 地址）
- DNS 服务器（域名解析）
- TFTP 服务器（PXE 启动支持）
- 防火墙规则配置

## 支持的操作系统

- RHEL 9 / CentOS 9
- RHEL 10 / CentOS 10
- SLES 15

## 前置要求

1. 以 root 权限运行脚本
2. 准备好对应版本的操作系统 ISO 文件
3. 确保服务器有固定 IP 地址
4. 建议关闭 SELinux 或配置适当的规则

## 安装与使用

1. 下载脚本到服务器：
   ```bash
   wget https://example.com/linux_deployment_manager.sh
   chmod +x linux_deployment_manager.sh
   ```

2. （可选）创建配置文件 `config.ini` 自定义参数：
   ```ini
   SERVER_NAME="192.168.1.100"
   RHEL9_ISO="/iso/rhel-9.0-x86_64-dvd.iso"
   RHEL10_ISO="/iso/rhel-10.0-x86_64-dvd.iso"
   SLES15_ISO="/iso/SLES-15-SP4-x86_64-GM-DVD.iso"
   DOMAIN_NAME="local.lan"
   NETWORK="192.168.1.0/24"
   ```

3. 运行脚本：
   ```bash
   ./linux_deployment_manager.sh
   ```

4. 根据菜单选择需要执行的操作：
   ```
   === Linux 部署管理系统 ===
   1. 安装基本软件包
   2. 部署 RHEL 9
   3. 部署 RHEL 10
   4. 部署 SLES 15
   5. 配置 Apache
   6. 配置 DNS 服务器
   7. 配置 DHCP 服务器
   8. 配置防火墙
   9. 配置 TFTP 服务
   10. 显示帮助信息
   11. 退出
   ```

## 推荐操作流程

1. 安装基本软件包（选项 1）
2. 配置 Apache（选项 5）
3. 配置 DNS 服务器（选项 6）
4. 配置 DHCP 服务器（选项 7）
5. 配置防火墙（选项 8）
6. 配置 TFTP 服务（选项 9）
7. 部署所需的操作系统（选项 2/3/4）

## 日志信息

所有操作记录会保存到 `/var/log/deployment_manager.log`，可用于排查配置过程中的问题。

## 注意事项

- 确保 ISO 文件路径正确且具有可读权限
- 配置过程中会自动备份原有配置文件（添加 `.bak` 后缀）
- HTTPS 服务使用自签名证书，如需使用正式证书，请手动替换 `/etc/pki/tls/certs/server.crt` 和 `/etc/pki/tls/private/server.key`
- 网络配置（`NETWORK` 参数）应与服务器实际网络环境匹配

## 卸载

如需移除配置，可手动删除相关服务配置文件并卸载软件包：

```bash
# RHEL/CentOS 系统
dnf remove -y httpd dhcp-server bind tftp-server syslinux

# SLES 系统
zypper remove -y apache2 dhcp-server bind tftp syslinux
```
