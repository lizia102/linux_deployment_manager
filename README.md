# Linux 部署管理脚本 README

## 概述

`linux_deployment_manager.sh` 是一个用于自动化自动化部署和配置 Linux 服务器的 Bash 脚本，支持 RHEL/CentOS 和 SUSE 系统。该脚本可以帮助管理员快速设置 HTTP/HTTPS 引导、PXE 引导、DNS、DHCP 服务以及防火墙配置，便于大规模部署 Linux 操作系统。

## 功能特点

- 自动安装所需基础软件包
- 支持 RHEL 9/10 和 SLES 15 的部署配置
- 配置 Apache 服务器（HTTP/HTTPS）
- 配置 DNS 服务器
- 配置 DHCP 服务器（支持 PXE 引导）
- 自动配置防火墙规则
- 提供交互式菜单，操作简单直观

## 前置要求

1. 必须以 root 权限运行
2. 支持的操作系统：
   - RHEL/CentOS 系统（使用 dnf 包管理器）
   - SUSE 系统（使用 zypper 包管理器）
3. 确保系统已连接网络
4. 准备好对应版本的 Linux 安装 ISO 文件，并修改脚本中的 ISO 路径

## 使用方法

1. 下载脚本并赋予执行权限：
   ```bash
   chmod +x linux_deployment_manager.sh
   ```

2. 编辑脚本，修改开头的变量配置：
   ```bash
   SERVER_NAME="your_server_name.com"  # 替换为您的服务器域名
   SERVER_IP="your_server_ip"          # 替换为您的服务器IP地址
   NETWORK="192.168.1.0"               # 替换为您的网络地址
   NETMASK="255.255.255.0"             # 替换为您的子网掩码
   RANGE_START="192.168.1.100"         # DHCP地址池起始
   RANGE_END="192.168.1.200"           # DHCP地址池结束
   ROUTER="192.168.1.1"                # 替换为您的路由器IP
   ```

3. 修改 ISO 文件路径（在 `configure_rhel_servers` 和 `configure_sles_servers` 函数中）：
   ```bash
   local iso_path="/path/to/rhel$version.iso"  # RHEL系统
   local iso_path="/path/to/sles$version.iso"  # SLES系统
   ```

4. 运行脚本：
   ```bash
   ./linux_deployment_manager.sh
   ```

5. 根据菜单提示选择需要执行的操作：
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
   9. 退出
   ```

## 主要功能说明

1. **安装基本软件包**：根据不同操作系统自动安装所需软件（Apache、TFTP、DNS、DHCP等）

2. **部署 RHEL/SLES**：
   - 配置 HTTP/HTTPS 引导
   - 配置 PXE 引导
   - 准备引导文件和 GRUB 配置
   - 复制内核和初始化镜像

3. **配置 Apache**：
   - 设置虚拟主机（HTTP 80端口和HTTPS 443端口）
   - 配置SSL证书（SLES系统会自动生成自签名证书）

4. **配置 DNS 服务器**：
   - 设置域名解析
   - 配置区域文件

5. **配置 DHCP 服务器**：
   - 设置IP地址池
   - 配置PXE引导选项
   - 支持UEFI引导

6. **配置防火墙**：
   - 开放HTTP、HTTPS、TFTP、DNS和DHCP服务端口
   - 自动适配不同系统的防火墙工具

## 注意事项

1. 确保ISO文件路径正确且文件存在
2. 网络配置（IP地址、子网掩码等）需根据实际环境修改
3. 首次运行建议按顺序执行：安装软件包 → 部署系统 → 配置各项服务
4. 脚本执行过程中可能需要联网下载软件包
5. 自签名SSL证书仅用于测试环境，生产环境建议使用正式证书

## 故障排除

- 如遇权限问题，请确保以root用户运行
- 若服务启动失败，可查看系统日志（`/var/log/messages` 或 `/var/log/syslog`）
- 网络服务异常时，检查防火墙配置是否正确
- PXE引导问题请检查DHCP和TFTP服务是否正常运行
