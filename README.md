# OpsOrchestra

OpsOrchestra is an automation control platform built around Jenkins, infrastructure-as-code, and ephemeral compute workers.

The goal is to keep the orchestration layer small, persistent, and self-hosted while dynamically creating short-lived worker infrastructure only when jobs need it.

OpsOrchestra is being built around three primary roles:

* **Jenkins Controller** — always-on orchestration and job control.
* **Provisioner Agent** — always-on Ubuntu worker responsible for infrastructure provisioning.
* **Ephemeral Workers** — temporary compute instances created for workloads and destroyed when work completes.

## Current Status

The current OpsOrchestra environment includes:

* Jenkins controller running in Docker.
* Jenkins persistent data stored in a Docker volume.
* Cloudflare Tunnel running alongside Jenkins.
* Jenkins protected by Cloudflare Zero Trust.
* Dedicated Ubuntu provisioner agent.
* Jenkins Remoting connection over WebSocket.
* Local NGINX authentication proxy on the provisioner.
* Cloudflare Access Service Token authentication for machine-to-machine access.
* Jenkins provisioner agent managed by systemd.

The next major milestone is adding Terraform and DigitalOcean provisioning to the provisioner.

## Current Architecture

```text
                         HOME INFRASTRUCTURE
┌───────────────────────────────────────────────────────────────┐
│                                                               │
│  Jenkins Controller                                           │
│  Docker                                                       │
│                                                               │
│        ▲                                                      │
│        │                                                      │
│        │ Jenkins WebSocket                                    │
│        │                                                      │
│  Cloudflare Tunnel                                            │
│        ▲                                                      │
└────────┼───────────────────────────────────────────────────────┘
         │
         │ Cloudflare Zero Trust
         │
         ▼
      Internet
         ▲
         │
         │ HTTPS / WebSocket
         │
┌────────┼───────────────────────────────────────────────────────┐
│        │                    PROVISIONER                        │
│        │                                                      │
│     NGINX                                                     │
│  127.0.0.1:8081                                               │
│        ▲                                                      │
│        │                                                      │
│  Jenkins agent.jar                                            │
│  Provisioner-01                                               │
│        │                                                      │
│        ├── Terraform        [planned]                         │
│        ├── doctl            [planned]                         │
│        └── provisioning tooling                               │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

The provisioner connects outward to Jenkins. No Jenkins agent TCP port is exposed publicly.

## Controller

The Jenkins controller runs locally using Docker Compose.

The controller is responsible for:

* Job orchestration.
* Pipeline execution control.
* Node management.
* Build history.
* Artifact storage.
* Reporting.
* Infrastructure workflow coordination.

The controller is not intended to run normal workloads directly.

Jenkins data is stored in the persistent Docker volume:

```text
opsorchestra_jenkins_home
```

This allows the Jenkins container to be upgraded or recreated without losing Jenkins configuration and state.

## Cloudflare Zero Trust

The Jenkins controller is accessed through Cloudflare Zero Trust.

The request path is:

```text
User
  |
  v
Cloudflare Access
  |
  v
Cloudflare Tunnel
  |
  v
cloudflared container
  |
  v
Jenkins container
```

Jenkins is not directly published through the host with an exposed Docker port.

The Cloudflare Tunnel connects to Jenkins internally through the OpsOrchestra Docker network:

```text
http://jenkins:8080
```

## Provisioner

OpsOrchestra uses a dedicated Ubuntu provisioner agent for infrastructure operations.

The provisioner currently runs:

* OpenJDK 21
* Jenkins inbound agent
* NGINX
* Git
* curl

Terraform, `doctl`, and additional infrastructure tooling will be installed as the provisioning layer is built.

The Jenkins node is currently:

```text
Provisioner-01
```

Recommended labels:

```text
provisioner
terraform
digitalocean
```

The provisioner is intended for infrastructure operations rather than normal build workloads.

Detailed setup and recovery documentation is available at:

```text
provisioner/README.md
```

## Provisioner Authentication Path

Cloudflare Access protects Jenkins from unauthenticated requests.

Because Jenkins Remoting does not directly provide the Cloudflare Access Service Token headers required by the environment, the provisioner uses a local NGINX proxy.

```text
agent.jar
    |
    v
127.0.0.1:8081
    |
    v
NGINX
    |
    +-- CF-Access-Client-ID
    +-- CF-Access-Client-Secret
    |
    v
Cloudflare Access
    |
    v
Jenkins
```

NGINX listens only on:

```text
127.0.0.1:8081
```

and is not exposed to the local network or Internet.

The Jenkins agent runs as the dedicated:

```text
jenkins
```

system user and is managed by systemd.

## Repository Structure

The repository currently follows this general structure:

```text
OpsOrchestra/
├── compose.yaml
├── .env.example
├── .gitignore
├── README.md
│
├── scripts/
│   ├── start.sh
│   ├── stop.sh
│   └── logs.sh
│
└── provisioner/
    ├── README.md
    ├── nginx/
    │   └── opsorchestra-agent.conf
    ├── systemd/
    │   └── opsorchestra-agent.service
    └── secrets/
        ├── cloudflare-jenkins.conf.example
        └── jenkins-agent.secret.example
```

## Secrets

Secrets must never be committed to the repository.

Examples include:

* Cloudflare Tunnel tokens.
* Cloudflare Access Service Token credentials.
* Jenkins agent secrets.
* DigitalOcean API tokens.
* Terraform state containing sensitive values.

Local configuration should be stored outside Git using protected files such as:

```text
.env

/etc/opsorchestra/cloudflare-jenkins.conf

/etc/opsorchestra/jenkins-agent.secret
```

Example files may be stored in Git with placeholder values.

## Design Principles

OpsOrchestra is being built around a few simple rules:

* The Jenkins controller orchestrates but does not perform heavy workloads.
* Infrastructure provisioning runs on a dedicated provisioner.
* Workers should be disposable whenever possible.
* Workers connect back to Jenkins rather than requiring inbound access.
* Secrets stay outside the repository.
* Infrastructure configuration should be reproducible from Git.
* Persistent data and runtime infrastructure should remain separate.
* Failed jobs should still clean up their infrastructure.
* No ephemeral worker should be allowed to exist indefinitely.

## Planned Worker Lifecycle

The intended DigitalOcean worker lifecycle is:

```text
REQUESTED
    |
    v
PROVISIONING
    |
    v
BOOTSTRAPPING
    |
    v
WAITING_FOR_AGENT
    |
    v
READY
    |
    v
RUNNING
    |
    v
COLLECTING_RESULTS
    |
    v
GENERATING_REPORT
    |
    v
DESTROYING
    |
    v
COMPLETE
```

Failures should still follow a cleanup path:

```text
FAILED
   |
   v
COLLECT_LOGS
   |
   v
DESTROYING
   |
   v
FAILED_CLEAN
```

## Planned Ephemeral Worker Architecture

The next stage of OpsOrchestra will introduce dynamically provisioned DigitalOcean workers.

```text
Jenkins Controller
       |
       v
Provisioner-01
       |
       | Terraform
       v
DigitalOcean API
       |
       v
Ephemeral Ubuntu Worker
       |
       | Jenkins WebSocket Agent
       v
Jenkins Controller
       |
       v
Run Workload
       |
       v
Collect Results
       |
       v
Terraform Destroy
```

The worker should contain nothing that must survive after the job completes.

Artifacts, logs, reports, and test results must be copied back before the worker is destroyed.

## Roadmap

### Phase 1 — Controller

* [x] Jenkins controller
* [x] Docker Compose deployment
* [x] Persistent Jenkins volume
* [x] Cloudflare Tunnel
* [x] Cloudflare Zero Trust protection

### Phase 2 — Provisioner

* [x] Ubuntu provisioner host
* [x] Permanent Jenkins agent
* [x] Jenkins WebSocket connectivity
* [x] Cloudflare machine authentication
* [x] Local NGINX authentication proxy
* [x] systemd-managed Jenkins agent
* [ ] Terraform
* [ ] DigitalOcean CLI
* [ ] DigitalOcean credentials
* [ ] Provisioner validation pipeline

### Phase 3 — Ephemeral Workers

* [ ] Terraform DigitalOcean provider
* [ ] Worker specification
* [ ] Worker cloud-init bootstrap
* [ ] Dynamic Jenkins agent registration
* [ ] Workload execution
* [ ] Artifact collection
* [ ] Automated reporting
* [ ] Automatic worker destruction

### Phase 4 — Reliability

* [ ] Worker TTL enforcement
* [ ] Orphaned resource cleanup
* [ ] Infrastructure failure handling
* [ ] Controller backup and restore
* [ ] Provisioner rebuild automation
* [ ] Jenkins Configuration as Code

### Phase 5 — Multiple Compute Providers

The long-term architecture may support multiple worker providers behind a common interface.

```text
providers/
├── digitalocean/
├── proxmox/
├── aws/
└── local/
```

The Jenkins pipeline should eventually request compute capabilities without needing to know the implementation details of the underlying provider.

## Project Goal

OpsOrchestra should eventually make infrastructure-backed automation feel like requesting a temporary capability:

```text
I need:
- Ubuntu
- 4 vCPU
- 8 GB RAM
- Docker
- Python
- Ansible
```

OpsOrchestra should handle:

```text
provision
    |
bootstrap
    |
connect
    |
execute
    |
collect
    |
report
    |
destroy
```

The compute is temporary.

The orchestration, configuration, history, and results remain persistent.