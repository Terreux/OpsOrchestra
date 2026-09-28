#!/usr/bin/env bash

set -euo pipefail
umask 077

usage() {
    echo "Usage: sudo bash $0 PUBLIC_KEY_FILE"
    echo "Prepare an Ubuntu/Debian target with an ops account, SSH, and Python 3."
    echo "Accepts one Ed25519 public key. Does not grant sudo or change SSH policy."
}

fail() { echo "ERROR: $*" >&2; exit 1; }

if [[ ${1:-} == --help ]]; then usage; exit 0; fi
[[ $# == 1 ]] || { usage >&2; exit 1; }
[[ -r $1 && -f $1 ]] || fail "Provide a readable public key file."

# Read and validate before making changes. Do not accept private keys, options,
# or multiple keys from the supplied file.
mapfile -t key_lines < "$1"
[[ ${#key_lines[@]} == 1 ]] || fail "Expected exactly one public key line."
read -r key_type key_data key_comment <<< "${key_lines[0]}"
[[ $key_type == ssh-ed25519 && -n $key_data ]] || fail "Expected an Ed25519 public key, not a private key."
command -v ssh-keygen >/dev/null || fail "Install openssh-client first."
ssh-keygen -lf "$1" >/dev/null 2>&1 || fail "Invalid SSH public key."
[[ $EUID == 0 ]] || fail "Run this script using sudo or as root on the target."
[[ -f /etc/os-release ]] || fail "Cannot identify the target OS."
source /etc/os-release
[[ ${ID:-} == ubuntu || ${ID:-} == debian ]] || fail "This script supports Ubuntu and Debian only."
command -v systemctl >/dev/null || fail "This script requires systemd."

ops_home=/home/ops
if getent passwd ops >/dev/null; then
    IFS=: read -r _ _ ops_uid _ _ existing_home existing_shell < <(getent passwd ops)
    [[ $ops_uid -ge 1000 && $existing_home == "$ops_home" && $existing_shell == /bin/bash ]] || fail "Existing ops account does not match the expected regular user, /home/ops home, and /bin/bash shell. Review it manually."
else
    [[ ! -e $ops_home && ! -L $ops_home ]] || fail "Unowned account home already exists: $ops_home. Review it manually."
    useradd --create-home --user-group --shell /bin/bash ops
fi

[[ -d $ops_home && ! -L $ops_home ]] || fail "Expected a real home directory at $ops_home."
[[ $(stat -c %u "$ops_home") == "$(id -u ops)" ]] || fail "The ops home must belong to ops."
ssh_dir=$ops_home/.ssh
authorized_keys=$ssh_dir/authorized_keys
[[ ! -L $ssh_dir && ! -L $authorized_keys ]] || fail "Refusing symlinked SSH paths."
[[ ! -e $ssh_dir || -d $ssh_dir ]] || fail "$ssh_dir is not a directory."
[[ ! -e $authorized_keys || -f $authorized_keys ]] || fail "$authorized_keys is not a regular file."
if [[ -f $authorized_keys ]]; then
    [[ $(stat -c %h "$authorized_keys") == 1 ]] || fail "Refusing a hard-linked authorized_keys file."
fi

ops_group=$(id -gn ops)
chmod go-w "$ops_home"
install -d -m 700 -o ops -g "$ops_group" "$ssh_dir"
touch "$authorized_keys"
chown ops:"$ops_group" "$authorized_keys"
chmod 600 "$authorized_keys"

# Compare key material, ignoring comments. Preserve existing restrictions if this
# key is already present with authorized_keys options.
if awk -v type="$key_type" -v key="$key_data" '
    /^[[:space:]]*#/ { next }
    { for (i = 1; i < NF; i++) if ($i == type && $(i + 1) == key) found = 1 }
    END { exit !found }
' "$authorized_keys"; then
    echo "Public key already installed; preserving the existing entry."
else
    # The leading newline also handles existing files without a final newline.
    printf '\n%s %s opsorchestra\n' "$key_type" "$key_data" >> "$authorized_keys"
    echo "Public key installed for ops."
fi

missing_packages=()
for package in openssh-server python3; do
    if [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true) != 'install ok installed' ]]; then
        missing_packages+=("$package")
    fi
done
if (( ${#missing_packages[@]} )); then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing_packages[@]}"
fi

# ssh.service normally creates this runtime directory. It may be absent when
# validating a newly installed or currently stopped service.
install -d -m 0755 -o root -g root /run/sshd
/usr/sbin/sshd -t
systemctl enable --now ssh

echo
echo "Target prepared for SSH as ops. No sudo permissions were added."
echo "Existing SSH policy and firewall rules still apply."
echo "Verify these host-key fingerprints through your trusted admin connection:"
for host_key in /etc/ssh/ssh_host_*_key.pub; do
    [[ -f $host_key ]] || continue
    ssh-keygen -lf "$host_key"
done
