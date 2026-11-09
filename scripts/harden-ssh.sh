#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run through sudo' >&2; exit 1; }
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test -s /home/devops/.ssh/authorized_keys
test -f /etc/ssh/sshd_config.backup || cp -p /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
install -m 644 "$ROOT/config/99-hardening.conf" /etc/ssh/sshd_config.d/99-hardening.conf
# OpenSSH uses the first value it reads, so earlier cloud-init settings must
# not override the hardening file. Keep the original files as backups.
while IFS= read -r -d '' file; do
    [[ "${file##*/}" == 99-hardening.conf ]] && continue
    cp -n "$file" "$file.before-hardening" || true
    sed -i -E '/^[[:space:]]*(PasswordAuthentication|KbdInteractiveAuthentication)[[:space:]]/s/^/# disabled by lab hardening: /' "$file"
done < <(find /etc/ssh/sshd_config.d -maxdepth 1 -name '*.conf' -print0)
/usr/sbin/sshd -t
/usr/sbin/sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers) '
systemctl disable --now ssh.socket
systemctl enable ssh.service
systemctl restart ssh.service
ss -tlnp | grep sshd
