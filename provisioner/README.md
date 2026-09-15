# OpsOrchestra Provisioner

The OpsOrchestra Provisioner is an always-on Ubuntu Jenkins agent responsible for infrastructure provisioning tasks.

Its initial responsibilities are:

* Connect to the OpsOrchestra Jenkins controller.
* Run Terraform.
* Run DigitalOcean tooling.
* Create and destroy ephemeral worker infrastructure.
* Perform infrastructure cleanup operations.

The provisioner is **not** intended to run normal application workloads.

## Architecture

```text
Jenkins Controller
        |
        | HTTPS / WebSocket
        v
Cloudflare Zero Trust
        |
        v
Cloudflare Tunnel
        |
        v
Public Jenkins Endpoint
        ^
        |
Local NGINX Proxy
127.0.0.1:8081
        ^
        |
Jenkins agent.jar
        |
Provisioner-01
```

Cloudflare Access protects the Jenkins controller.

The Jenkins agent cannot directly provide Cloudflare Access service-token headers, so a local NGINX instance acts as an authentication proxy.

The Jenkins agent connects to:

```text
http://127.0.0.1:8081/
```

NGINX then:

1. Proxies the request to the public Jenkins HTTPS endpoint.
2. Adds the Cloudflare Access service-token headers.
3. Passes WebSocket upgrade headers.
4. Forwards the connection through Cloudflare Access to Jenkins.

NGINX listens only on the loopback interface and is not exposed to the network.

---

# Host Requirements

Recommended starting configuration:

```text
Ubuntu Server
2 vCPU
2-4 GB RAM
20-30 GB disk
```

Required software:

```text
OpenJDK 21
NGINX
curl
Git
```

Terraform and DigitalOcean tooling will be installed separately.

---

# Install Packages

```bash
sudo apt update

sudo apt install -y \
    openjdk-21-jre-headless \
    nginx \
    curl \
    git
```

Verify Java:

```bash
java -version
```

---

# Create Jenkins User

Create a dedicated service account:

```bash
sudo useradd \
    --system \
    --create-home \
    --home-dir /opt/jenkins \
    --shell /bin/bash \
    jenkins
```

Ensure ownership:

```bash
sudo chown -R jenkins:jenkins /opt/jenkins
```

---

# Jenkins Node Configuration

In Jenkins:

```text
Manage Jenkins
→ Nodes
→ New Node
```

Create:

```text
Name:
Provisioner-01

Type:
Permanent Agent

Executors:
1

Remote root directory:
/opt/jenkins

Labels:
provisioner terraform digitalocean

Usage:
Only build jobs with label expressions matching this node

Launch method:
Launch agents by connecting it to the controller
```

Enable WebSocket when configuring the inbound agent.

---

# Cloudflare Access

Create a Cloudflare Access Service Token that is authorized to reach the Jenkins Access application.

The token provides:

```text
CF-Access-Client-ID
CF-Access-Client-Secret
```

Do not commit these values to Git.

---

# Configure OpsOrchestra Secrets

Create:

```bash
sudo mkdir -p /etc/opsorchestra
```

Copy the Cloudflare example:

```bash
sudo cp \
    provisioner/secrets/cloudflare-jenkins.conf.example \
    /etc/opsorchestra/cloudflare-jenkins.conf
```

Edit it:

```bash
sudo nano /etc/opsorchestra/cloudflare-jenkins.conf
```

Add the real Cloudflare credentials.

Protect the file:

```bash
sudo chown root:root \
    /etc/opsorchestra/cloudflare-jenkins.conf

sudo chmod 600 \
    /etc/opsorchestra/cloudflare-jenkins.conf
```

---

# Configure Jenkins Agent Secret

Copy:

```bash
sudo cp \
    provisioner/secrets/jenkins-agent.secret.example \
    /etc/opsorchestra/jenkins-agent.secret
```

Replace the placeholder with the secret Jenkins generated for `Provisioner-01`.

Protect it:

```bash
sudo chown root:jenkins \
    /etc/opsorchestra/jenkins-agent.secret

sudo chmod 640 \
    /etc/opsorchestra/jenkins-agent.secret
```

The Jenkins user needs read access to this file.

---

# Configure NGINX

The provisioner uses NGINX only as a local authentication proxy.

Disable the Ubuntu default site:

```bash
sudo rm -f /etc/nginx/sites-enabled/default
```

Copy the OpsOrchestra site:

```bash
sudo cp \
    provisioner/nginx/opsorchestra-agent.conf \
    /etc/nginx/sites-available/opsorchestra-agent
```

Edit the configuration and replace:

```text
jenkins.example.com
```

with the actual Jenkins hostname.

Enable it:

```bash
sudo ln -sf \
    /etc/nginx/sites-available/opsorchestra-agent \
    /etc/nginx/sites-enabled/opsorchestra-agent
```

Test:

```bash
sudo nginx -t
```

Install the NGINX recovery drop-in. It preserves the distribution's NGINX unit
and retries failed starts every 10 seconds, including temporary DNS failures:

```bash
sudo install -d -m 0755 /etc/systemd/system/nginx.service.d
sudo install -m 0644 \
    provisioner/systemd/nginx.service.d/opsorchestra-recovery.conf \
    /etc/systemd/system/nginx.service.d/opsorchestra-recovery.conf
sudo systemctl daemon-reload
```

Restart NGINX:

```bash
sudo systemctl restart nginx
sudo systemctl enable nginx
```

---

# Verify NGINX Exposure

NGINX should only listen on:

```text
127.0.0.1:8081
```

Check:

```bash
sudo ss -lntp | grep nginx
```

There should be no NGINX listener on:

```text
0.0.0.0:80
0.0.0.0:443
[::]:80
[::]:443
```

The local proxy should not be remotely accessible.

---

# Test Cloudflare Proxy

Test:

```bash
curl -I http://127.0.0.1:8081/
```

A Jenkins HTTP response confirms that NGINX successfully:

```text
Local Request
    ↓
NGINX
    ↓
Cloudflare Service Token
    ↓
Cloudflare Access
    ↓
Jenkins
```

---

# Download Jenkins Agent

Download the Jenkins agent through the local proxy:

```bash
sudo -u jenkins curl -fL \
    http://127.0.0.1:8081/jnlpJars/agent.jar \
    -o /opt/jenkins/agent.jar
```

Verify:

```bash
file /opt/jenkins/agent.jar
```

The result should identify the file as a Java/JAR archive rather than HTML.

Check ownership:

```bash
sudo chown jenkins:jenkins /opt/jenkins/agent.jar
```

---

# Install Jenkins Agent Service

Copy the systemd service:

```bash
sudo cp \
    provisioner/systemd/opsorchestra-agent.service \
    /etc/systemd/system/opsorchestra-agent.service
```

Reload systemd:

```bash
sudo systemctl daemon-reload
```

Enable and start:

```bash
sudo systemctl enable --now opsorchestra-agent
```

Check:

```bash
sudo systemctl status opsorchestra-agent
```

Watch logs:

```bash
sudo journalctl \
    -u opsorchestra-agent \
    -f
```

A successful connection should contain messages similar to:

```text
WebSocket connection open
Connected
```

Jenkins should show:

```text
Provisioner-01
Online
```

---

# Service Dependencies

The Jenkins connection requires the local NGINX proxy, but the Java process can
run while that proxy is unavailable. The agent uses `Wants=nginx.service` and
`After=nginx.service` to request the proxy at startup and wait for its initial
start attempt. A failed or stopped proxy does not stop the agent; Remoting can
continue retrying its connection.

The NGINX recovery drop-in retries failed starts and process failures every
10 seconds. If DNS is temporarily unavailable during the startup configuration
check, NGINX retries until it can resolve the controller hostname. `network-online.target` is startup ordering,
not a guarantee that DNS remains available during later maintenance.

The agent uses `Restart=always` with a 10-second delay. Both units disable
start rate limiting so prolonged failures do not exhaust their restart attempts.
Invalid configuration will also keep retrying; inspect the journal and correct
the configuration rather than expecting retries to fix it. An explicit
`systemctl stop` still leaves the stopped service down until it is started again.

These settings recover process/startup failures. They do not detect a running
Java process whose connection is stuck, or guarantee that interrupted jobs resume.

---

# Verify Service Recovery

Check the effective settings and confirm `Provisioner-01` is online in Jenkins:

```bash
systemctl show opsorchestra-agent -p Wants -p Requires -p Restart -p StartLimitIntervalUSec
systemctl show nginx -p Restart -p RestartUSec -p StartLimitIntervalUSec
sudo journalctl -u nginx -u opsorchestra-agent --since "10 minutes ago" --no-pager
```

For a controlled proxy outage test, with no jobs running:

```bash
sudo systemctl stop nginx
systemctl is-active opsorchestra-agent
sudo systemctl start nginx
sudo journalctl -u nginx -u opsorchestra-agent --since "5 minutes ago" --no-pager
```

The agent should remain active while NGINX is stopped and reconnect after the
proxy starts. Confirm Jenkins reports it online again. This tests reconnect
behavior; an intentional stop does not exercise NGINX's automatic failure retries.

---

# Reboot Test

Verify both services are enabled:

```bash
systemctl is-enabled nginx
systemctl is-enabled opsorchestra-agent
```

Both should return:

```text
enabled
```

Reboot:

```bash
sudo reboot
```

After startup:

```bash
systemctl status nginx
systemctl status opsorchestra-agent
```

Verify NGINX:

```bash
sudo ss -lntp | grep 8081
```

Verify Jenkins reports `Provisioner-01` online.

---

# Important Files

```text
/etc/opsorchestra/
├── cloudflare-jenkins.conf
└── jenkins-agent.secret

/etc/nginx/sites-available/
└── opsorchestra-agent

/etc/systemd/system/
├── opsorchestra-agent.service
└── nginx.service.d/
    └── opsorchestra-recovery.conf

/opt/jenkins/
├── agent.jar
├── remoting/
└── workspace/
```

Permissions:

```text
/etc/opsorchestra/cloudflare-jenkins.conf
root:root
0600

/etc/opsorchestra/jenkins-agent.secret
root:jenkins
0640

/opt/jenkins
jenkins:jenkins
```

---

# Security Model

The provisioner follows these principles:

* NGINX listens only on `127.0.0.1`.
* No NGINX ports are exposed externally.
* Cloudflare Access remains enabled for Jenkins.
* Machine authentication uses a dedicated Cloudflare Service Token.
* Cloudflare credentials are not available to Jenkins jobs.
* The Jenkins agent runs as a dedicated `jenkins` user.
* The Jenkins agent secret is not stored directly in the systemd unit.
* Jenkins Remoting uses WebSocket over the local authenticated proxy.
* systemd automatically restarts the agent after failures or reboots.

---

# Next Steps

The next OpsOrchestra provisioner milestones are:

1. Install Terraform.
2. Install `doctl`.
3. Configure DigitalOcean credentials securely.
4. Run a Jenkins Pipeline on the `provisioner` label.
5. Provision the first disposable DigitalOcean worker.
6. Bootstrap the worker.
7. Register the worker dynamically with Jenkins.
8. Run a workload.
9. Collect artifacts and reports.
10. Destroy the worker automatically.
