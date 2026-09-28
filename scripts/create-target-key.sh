#!/usr/bin/env bash

set -euo pipefail
umask 077

usage() {
    echo "Usage: bash $0 TARGET_NAME [KEY_DIRECTORY]"
    echo "Generate an Ed25519 key pair for target onboarding; prompts for a passphrase."
    echo "Default directory: \$HOME/.local/share/opsorchestra/ssh/TARGET_NAME"
}

fail() { echo "ERROR: $*" >&2; exit 1; }

if [[ ${1:-} == --help ]]; then usage; exit 0; fi
[[ $# -ge 1 && $# -le 2 ]] || { usage >&2; exit 1; }
target=$1
[[ $target =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$ ]] || fail "Use a target name of 1-63 letters, digits, dots, underscores, or hyphens, starting with a letter or digit."
command -v ssh-keygen >/dev/null || fail "Install openssh-client first."

key_dir=$(realpath -m -- "${2:-$HOME/.local/share/opsorchestra/ssh/$target}")
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
case "$key_dir/" in
    "$repo_dir/"*) fail "Store keys outside the repository." ;;
esac

# A fresh directory prevents accidental key replacement, including concurrent runs.
mkdir -p -- "$(dirname -- "$key_dir")"
mkdir -m 700 -- "$key_dir" || fail "Key directory already exists or cannot be created: $key_dir. Existing keys were not changed."

ssh-keygen -t ed25519 -a 100 -C "opsorchestra:ops:$target" -f "$key_dir/id_ed25519"

echo
echo "Private key: $key_dir/id_ed25519 (store in Jenkins; never copy to the target)"
echo "Public key:  $key_dir/id_ed25519.pub (copy to the target)"
echo "Jenkins credential: SSH Username with private key; username ops."
echo "Suggested credential ID: ops-ssh-$target"
echo "Store the passphrase with the Jenkins credential if you set one."
echo "After verifying access and Jenkins storage, remove the temporary private key copy."
