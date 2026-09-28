#!/usr/bin/env bash

set -euo pipefail
umask 077

fail() { echo "ERROR: $*" >&2; exit 1; }

: "${TARGET_HOST:?Set TARGET_HOST to the target hostname or IP}"
: "${TARGET_KNOWN_HOSTS_FILE:?Supply a verified known_hosts file}"
: "${SSH_AUTH_SOCK:?Load the target credential with ssh-agent}"
port=${TARGET_SSH_PORT:-22}

[[ $TARGET_HOST =~ ^[a-zA-Z0-9:][a-zA-Z0-9.:-]*$ ]] || fail "TARGET_HOST must be a hostname or unbracketed IP address, without a username or port."
[[ $port =~ ^[0-9]{1,5}$ ]] || fail "SSH port must be an integer from 1 to 65535."
port=$((10#$port))
(( port >= 1 && port <= 65535 )) || fail "SSH port must be between 1 and 65535."
[[ -s $TARGET_KNOWN_HOSTS_FILE && -r $TARGET_KNOWN_HOSTS_FILE ]] || fail "The verified known_hosts file is empty or unreadable."
command -v ssh >/dev/null || fail "Install openssh-client on the provisioner."

report_dir=reports/target-smoke-test
mkdir -p "$report_dir"
report=$report_dir/result.txt
printf 'Target: %s\nSSH user: ops\nSSH port: %s\nStarted (UTC): %s\n\n' \
    "$TARGET_HOST" "$port" "$(date -u +%FT%TZ)" > "$report"

# Use only the supplied agent and host trust, independent of the provisioner's
# personal SSH configuration. Never forward credentials to the target.
if ssh -F /dev/null -T \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=yes \
    -o "UserKnownHostsFile=$TARGET_KNOWN_HOSTS_FILE" \
    -o GlobalKnownHostsFile=/dev/null \
    -o IdentityFile=none \
    -o ForwardAgent=no \
    -o ClearAllForwardings=yes \
    -o ConnectTimeout=10 \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=2 \
    -p "$port" -l ops "$TARGET_HOST" 'sh -s' >> "$report" 2>&1 <<'REMOTE'
set -eu
printf 'Identity: '
id
printf '\nHostname: '
hostname
printf '\nOperating system:\n'
cat /etc/os-release
printf '\nPython: '
python3 --version
printf '\nTarget time (UTC): '
date -u +%FT%TZ
REMOTE
then
    status=0
else
    status=$?
fi

printf '\nSSH exit status: %s\nFinished (UTC): %s\n' \
    "$status" "$(date -u +%FT%TZ)" >> "$report"
cat "$report"
exit "$status"
