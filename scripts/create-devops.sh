#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run through sudo' >&2; exit 1; }
id devops >/dev/null 2>&1 || useradd --create-home --shell /bin/bash devops
usermod -aG sudo devops
# Preserve the local installation password without printing its value or hash.
usermod --password "$(getent shadow student | cut -d: -f2)" devops
install -d -m 700 -o devops -g devops /home/devops/.ssh
install -m 600 -o devops -g devops /home/student/.ssh/authorized_keys /home/devops/.ssh/authorized_keys
id devops
stat -c '%a %U %n' /home/devops/.ssh /home/devops/.ssh/authorized_keys
