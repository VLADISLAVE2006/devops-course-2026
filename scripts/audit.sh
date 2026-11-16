#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
PASS=0; FAIL=0
STAGE="${1:-6}"
case "$STAGE" in 5|6|7|8) ;; *) echo 'Usage: audit.sh [5|6|7|8]' >&2; exit 1;; esac
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK] $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (expected '$expected', got '$actual')"; ((FAIL++))
    fi
}
echo "Audit: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo '[1] SSH'
SSH_CONFIG="$(sudo /usr/sbin/sshd -T)"
check 'Root login disabled' no "$(awk '$1=="permitrootlogin" {print $2}' <<< "$SSH_CONFIG")"
check 'Password login disabled' no "$(awk '$1=="passwordauthentication" {print $2}' <<< "$SSH_CONFIG")"
check 'SSH port is 2222' 2222 "$(awk '$1=="port" {print $2}' <<< "$SSH_CONFIG")"
check 'MaxAuthTries' 3 "$(awk '$1=="maxauthtries" {print $2}' <<< "$SSH_CONFIG")"
echo '[2] Firewall'
UFW="$(sudo ufw status verbose)"
check 'UFW active' active "$(awk '/^Status:/ {print $2}' <<< "$UFW")"
check 'Incoming default deny' deny "$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<< "$UFW")"
echo '[3] Accounts'
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
if (( STAGE >= 6 )); then
    echo '[4] Web server'
    check 'nginx active' active "$(systemctl is-active nginx)"
    sudo nginx -t >/dev/null 2>&1; check 'nginx syntax' 0 "$?"
    openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend "${CERT_CHECK_SECONDS:-2592000}" >/dev/null 2>&1
    check 'Certificate valid for at least 30 days' 0 "$?"
    WRITABLE="$(find /var/www/devops-site -perm -o+w -print 2>&1)"; FIND_RC=$?
    check 'Resource permissions can be checked' 0 "$FIND_RC"
    check 'No world-writable resource paths' '' "$WRITABLE"
    check 'TLS key permissions' 600 "$(sudo stat -c '%a' /etc/ssl/private/devops.key)"
fi
if (( STAGE >= 7 )); then
    echo '[5] Containers'
    check 'Docker active' active "$(systemctl is-active docker)"
    DB_ID="$(docker compose --project-directory "$HOME/app" ps -q db)"
    check 'PostgreSQL healthy' healthy "$(docker inspect -f '{{.State.Health.Status}}' "$DB_ID" 2>/dev/null)"
    check 'App publication' '127.0.0.1:5000' "$(docker compose --project-directory "$HOME/app" port app 5000 2>/dev/null)"
    DB_PORT="$(docker compose --project-directory "$HOME/app" port db 5432 2>/dev/null || true)"
    case "$DB_PORT" in ''|':0') DB_PORT=none;; esac
    check 'PostgreSQL port not published' none "$DB_PORT"
    UNSAFE="$(ss -H -ltn | awk '$4 ~ /:(5000|5432)$/ && $4 !~ /^127\.0\.0\.1:/ {print $4}')"
    check 'No external listeners on 5000/5432' '' "$UNSAFE"
    check 'App environment permissions' 600 "$(stat -c '%a' "$HOME/app/.env")"
fi
if (( STAGE >= 8 )); then
    echo '[6] KR2'
    REDIS_ID="$(docker compose --project-directory "$HOME/kr2" ps -q redis)"
    check 'Redis healthy' healthy "$(docker inspect -f '{{.State.Health.Status}}' "$REDIS_ID" 2>/dev/null)"
    check 'KR2 loopback publication' '127.0.0.1:8002' "$(docker compose --project-directory "$HOME/kr2" port app 8002 2>/dev/null)"
    check 'KR2 environment permissions' 600 "$(stat -c '%a' "$HOME/kr2/.env")"
    openssl x509 -in /etc/ssl/certs/kr2.crt -noout -checkend 2592000 >/dev/null 2>&1
    check 'KR2 certificate valid for 30 days' 0 "$?"
    test -L /etc/nginx/sites-enabled/kr2 && test -e /etc/nginx/sites-enabled/kr2
    check 'KR2 site enabled' 0 "$?"
fi
echo "Passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]]
