#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run through sudo' >&2; exit 1; }
/usr/sbin/sshd -T | grep -qx 'port 2222'
ufw default deny incoming
ufw default allow outgoing
ufw limit 2222/tcp comment 'SSH rate-limited'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable
ufw logging medium
ufw status verbose
hostnamectl set-hostname devops-vm
sed -i 's/^127\.0\.1\.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f
