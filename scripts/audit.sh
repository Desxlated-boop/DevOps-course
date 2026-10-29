#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
PASS=0
FAIL=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  [OK]   %s\n' "$desc"
        ((PASS++))
    else
        printf "  [FAIL] %s (expected: '%s', actual: '%s')\n" "$desc" "$expected" "$actual"
        ((FAIL++))
    fi
}
if ! sudo -v; then
    echo '[FAIL] sudo authentication failed' >&2
    exit 1
fi
if ! SSH_CONFIG=$(sudo sshd -T 2>&1); then
    printf '[FAIL] Cannot read effective SSH configuration: %s\n' "$SSH_CONFIG" >&2
    exit 1
fi
if ! UFW_STATUS=$(sudo ufw status verbose 2>&1); then
    printf '[FAIL] Cannot read UFW configuration: %s\n' "$UFW_STATUS" >&2
    exit 1
fi
echo "Configuration audit: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo '[1] SSH service'
check 'Root login is disabled' 'no' "$(awk '$1=="permitrootlogin"{print $2}' <<<"$SSH_CONFIG")"
check 'Password authentication is disabled' 'no' "$(awk '$1=="passwordauthentication"{print $2}' <<<"$SSH_CONFIG")"
PORTS=$(awk '$1=="port"{print $2}' <<<"$SSH_CONFIG")
PORT_OK=yes
[[ -n "$PORTS" ]] || PORT_OK=no
while IFS= read -r port; do
    [[ "$port" =~ ^[0-9]+$ ]] && ((10#$port > 0 && 10#$port <= 65535 && 10#$port != 22)) || PORT_OK=no
done <<<"$PORTS"
check 'All SSH listening ports differ from 22' 'yes' "$PORT_OK"
check 'MaxAuthTries equals 3' '3' "$(awk '$1=="maxauthtries"{print $2}' <<<"$SSH_CONFIG")"
echo '[2] Firewall'
check 'Firewall is active' 'active' "$(awk '/^Status:/{print $2}' <<<"$UFW_STATUS")"
check 'Default incoming policy is deny' 'deny' "$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<<"$UFW_STATUS")"
echo '[3] User accounts'
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
echo '[4] Web server'
check 'Nginx is active' 'active' "$(systemctl is-active nginx || true)"
check 'Nginx configuration is valid' 'yes' "$(if sudo nginx -t >/dev/null 2>&1; then echo yes; else echo no; fi)"
check 'Certificate valid for at least 30 days' 'yes' "$(if openssl x509 -in /etc/ssl/certs/devops.crt -checkend "${CERT_MIN_SECONDS:-2592000}" -noout >/dev/null 2>&1; then echo yes; else echo no; fi)"
check 'Site has no world-writable entries and key mode is 600' 'yes' "$(if [[ -d /var/www/devops-site ]] && [[ -z $(find /var/www/devops-site -perm -o+w -print -quit) ]] && [[ $(sudo stat -c '%a' /etc/ssl/private/devops.key) == 600 ]]; then echo yes; else echo no; fi)"
echo '[5] Containers'
check 'Docker is active' 'active' "$(systemctl is-active docker || true)"
check 'Database is healthy' 'healthy' "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || true)"
check 'Application and database ports are not exposed externally' 'yes' "$(if ss -H -tln | awk '{print $4}' | grep -Eq '(^|:)(5000|5432)$' && ss -H -tln | awk '{print $4}' | grep -E '(^|:)(5000|5432)$' | grep -Ev '^127[.]0[.]0[.]1:5000$' >/dev/null; then echo no; else echo yes; fi)"
check 'Application environment file mode is 600' '600' "$(stat -c '%a' "$HOME/app/.env" 2>/dev/null || true)"
printf 'Passed: %s, failed: %s\n'  "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
