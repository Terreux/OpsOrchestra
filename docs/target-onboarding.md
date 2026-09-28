# Target onboarding

Targets are persistent servers that automation workers connect to over SSH.
They do not need a Jenkins agent. The initial baseline supports Ubuntu/Debian
with systemd, an `ops` account, OpenSSH server, and Python 3 for future Ansible
tasks. It grants no sudo access; privileged tasks need a separate permission
decision.

## 1. Generate a key on the provisioner

As your administrator account on the provisioner, from the repository root:

```bash
bash scripts/create-target-key.sh web-01
```

You can also copy `scripts/create-target-key.sh` to the provisioner on its own
and run `bash create-target-key.sh web-01`; a repository checkout is not required.

Use a stable inventory name for the target. The script creates:

```text
~/.local/share/opsorchestra/ssh/web-01/id_ed25519
~/.local/share/opsorchestra/ssh/web-01/id_ed25519.pub
```

It prompts for a passphrase. Store that passphrase with the Jenkins credential.
An optional second argument selects a different key directory outside any Git
checkout. The script checks the destination for Git metadata, independently of
where the script is located. The directory must not already exist: rerunning the script refuses to
replace keys. If generation is interrupted, inspect the directory before retrying
with a new directory.

Create a Jenkins credential, scoped to the jobs/folder that need this target:

* Kind: **SSH Username with private key**
* ID: `ops-ssh-web-01`
* Username: `ops`
* Private key: contents of `id_ed25519`, entered through the credential interface
* Passphrase: the passphrase selected during generation

Do not put the private key into Git, job parameters, cloud-init, or build logs.
Only the public `.pub` file goes to the target. Workers will receive the Jenkins
credential for the task that needs it; pipeline integration is still pending.

## 2. Prepare the target

Using your existing trusted administrator connection, copy
`scripts/setup-target.sh` and `id_ed25519.pub` to the target. Then run there:

```bash
sudo bash setup-target.sh id_ed25519.pub
```

The target needs `ssh-keygen` (provided by `openssh-client`) to validate the key
before any changes. The script creates `ops` with a locked password and
`/home/ops` as its home, adds the key, and sets SSH file permissions. It installs
`openssh-server` and `python3` if missing, validates SSH configuration, and enables
and starts the `ssh` service. Installing missing packages requires apt repository
access. An existing regular `ops` account is reused only if its home and shell
match the baseline; its password and group memberships are preserved.

Rerunning with the same key does not duplicate it. Other authorized keys and any
restrictions on an existing matching entry are preserved. It does not modify
SSH authentication policy, firewall rules, sudoers, or your administrator login.
Existing restrictions such as `AllowUsers` may need an administrator to authorize
`ops`. Concurrent onboarding runs on the same target are not supported.

Record the SSH host-key fingerprints printed by the script through this trusted
administrator connection. Also record the target address, SSH port, username,
Jenkins credential ID, and how workers will reach it. Target onboarding does not
create a private network route or change network exposure.

## 3. Verify access

From the provisioner, using the target's reachable address:

```bash
ssh -o StrictHostKeyChecking=ask -o IdentitiesOnly=yes \
  -i "$HOME/.local/share/opsorchestra/ssh/web-01/id_ed25519" \
  ops@TARGET_ADDRESS 'id; hostname; cat /etc/os-release; python3 --version'
```

For a non-default SSH port, add `-p PORT`. On first connection, compare the
presented host-key fingerprint with the trusted record before accepting it.
Stop and investigate mismatches. Future workers need the verified `known_hosts`
entry supplied alongside the credential, with strict host-key checking enabled.
The provisioner's local known-hosts file does not automatically reach workers.

After verifying access and confirming the private key and passphrase are stored
correctly in Jenkins, remove the temporary private key copy from the provisioner.
Keep the public key and fingerprint associated with the target inventory.

For rotation, generate a new pair in a new directory, onboard its public key,
update Jenkins, and verify access before removing the old authorized key. The
setup script deliberately does not revoke existing keys.

The next step is a Jenkins task that connects with this credential, records
hostname/OS details, and archives the output. Disposable workers come after that
connection and reporting path is established.
