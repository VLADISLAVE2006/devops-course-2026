#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run through sudo' >&2; exit 1; }
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx rsync
install -d -m 755 -o devops -g devops /var/www/devops-site
rsync -av --delete --chown=devops:devops --chmod=D755,F644 "$ROOT/site/" /var/www/devops-site/
if [[ ! -f /etc/ssl/private/devops.key && ! -f /etc/ssl/certs/devops.crt ]]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
        -subj '/CN=devops.local' -addext 'subjectAltName=DNS:devops.local'
fi
test -f /etc/ssl/private/devops.key
test -f /etc/ssl/certs/devops.crt
chown root:root /etc/ssl/private/devops.key /etc/ssl/certs/devops.crt
chmod 600 /etc/ssl/private/devops.key
chmod 644 /etc/ssl/certs/devops.crt
install -m 644 "$ROOT/config/devops-site" /etc/nginx/sites-available/devops-site
ln -sfn /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/devops-site
if [[ -L /etc/nginx/sites-enabled/default ]]; then unlink /etc/nginx/sites-enabled/default; fi
nginx -t
systemctl enable nginx
systemctl reload nginx
