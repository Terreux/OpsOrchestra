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
* Terraform and DigitalOcean CLI (`doctl`) on the provisioner.
* DigitalOcean API credentials stored in Jenkins.
* Jenkins pipeline for creating, verifying, and destroying a smoke-test Droplet.
* NGINX and Jenkins agent recovery configuration for process and startup failures.

The project is at the start of Phase 3. Infrastructure provisioning is implemented;
the smoke-test Droplet does not yet bootstrap or connect as a Jenkins worker.
The next milestone is a temporary worker that joins Jenkins, runs a small task,
returns an artifact, and is removed when the job finishes.

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
│        ├── Terraform                                          │
│        ├── doctl                                              │
│        └── provisioning tooling                               │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

The provisioner connects outward to Jenkins. No Jenkins agent TCP port is exposed publicly.

## Operating the Controller

For a new checkout, copy `.env.example` to `.env` and set
`CLOUDFLARE_TUNNEL_TOKEN` to the deployment's tunnel token. Keep `.env` out of Git.
The Cloudflare tunnel must route the Jenkins hostname to `http://jenkins:8080`.

From the repository root:

```bash
bash scripts/start.sh   # Pull images and start the controller and tunnel
bash scripts/logs.sh    # Follow container logs
bash scripts/stop.sh    # Stop containers; retain the Jenkins data volume
```

Provisioner installation and recovery are documented in the
[provisioner guide](provisioner/README.md).

## Onboarding Task Targets

Before adding disposable workers, prepare the servers they will operate on.
The provisioner generates a dedicated SSH key pair, Jenkins stores the private
key, and the target receives the public key for its `ops` account.

* `scripts/create-target-key.sh`: generate an onboarding key pair outside the repository.
* `scripts/setup-target.sh`: prepare an Ubuntu/Debian target with `ops`, SSH, and Python 3.

See [target onboarding](docs/target-onboarding.md) for commands, Jenkins credential
setup, host-key verification, and the optional Jenkins target smoke test.

## DigitalOcean Smoke Test

The root [Jenkinsfile](Jenkinsfile) runs on a node with the `provisioner` label.
It requires Terraform, `doctl`, and a Jenkins credential with ID
`digitalocean-api-token`. Configure a Jenkins Pipeline to load this repository's
`Jenkinsfile` from SCM.

The pipeline:

1. Checks the provisioner and installed tooling.
2. Runs `terraform init` and `terraform validate`.
3. Plans and applies the [smoke-test configuration](terraform/providers/digitalocean/smoke-test).
4. Queries the created Droplet using `doctl`.
5. Optionally connects to an existing target as `ops` and archives system details.
6. Attempts `terraform destroy` in its `post { always { ... } }` cleanup block.

Set `TARGET_HOST`, `TARGET_SSH_PORT`, `TARGET_SSH_CREDENTIAL_ID`, and
`TARGET_KNOWN_HOSTS_CREDENTIAL_ID` in **Build with Parameters** to enable the
target stage. It requires the Jenkins SSH Agent plugin, an SSH private-key
credential, and a Secret file credential containing verified host keys. Leave
`TARGET_HOST` blank for the original Droplet-only test. See the
[target test setup](docs/target-onboarding.md#4-run-the-jenkins-smoke-test).

The default Droplet is `opsorchestra-smoke-test`, using Ubuntu 24.04 in `sfo3`
with size `s-1vcpu-1gb`. Running this pipeline creates billable infrastructure.
It verifies provisioning and API access; it does not execute a task on the Droplet.

Terraform state currently lives in the Jenkins workspace. Cleanup depends on
that state, the provisioner, and API access remaining available. If cleanup fails,
check DigitalOcean for remaining resources before discarding the workspace.
Worker TTL enforcement and orphan cleanup are still planned.

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
* Terraform
* DigitalOcean CLI (`doctl`)

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

See the [provisioner guide](provisioner/README.md) for setup and recovery details.

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
├── AGENTS.md
├── Jenkinsfile
├── scripts/
│   ├── create-target-key.sh
│   ├── setup-target.sh
│   ├── target-smoke-test.sh
│   ├── start.sh
│   ├── stop.sh
│   └── logs.sh
├── docs/
│   └── target-onboarding.md
├── provisioner/
│   ├── README.md
│   ├── nginx/
│   │   └── opsorchestra-agent.conf
│   ├── systemd/
│   │   ├── opsorchestra-agent.service
│   │   └── nginx.service.d/
│   │       └── opsorchestra-recovery.conf
│   └── secrets/
│       ├── cloudflare-jenkins.conf.example
│       └── jenkins-agent.secret.example
└── terraform/
    └── providers/
        └── digitalocean/
            └── smoke-test/
                ├── main.tf
                ├── variables.tf
                └── outputs.tf
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

## Next Milestone: First Jenkins Worker Task

First, [onboard a target](docs/target-onboarding.md) and verify a read-only SSH
task from the existing provisioner. Then move the task to a temporary worker.

Build on the smoke test to complete one worker lifecycle:

1. Define a temporary Ubuntu worker with a unique Jenkins node name and label.
2. Bootstrap its runtime and authenticated outbound connection through Cloudflare Access.
3. Register the worker with Jenkins and wait for it to come online, with a timeout.
4. Run a small task on that worker: record the hostname, OS information, and a timestamp.
5. Archive the task output in Jenkins before destroying the worker.
6. Remove the temporary Jenkins node and destroy the Droplet on success or failure.

Worker bootstrap, credential delivery, and Jenkins registration are not implemented
yet. The existing provisioner remains responsible for infrastructure operations.

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
* [x] Terraform
* [x] DigitalOcean CLI
* [x] DigitalOcean credentials stored in Jenkins
* [x] Provisioner validation pipeline

### Phase 3 — Ephemeral Workers

* [x] Terraform DigitalOcean provider
* [x] Droplet provisioning smoke test with pipeline cleanup
* [ ] Worker specification
* [ ] Worker cloud-init bootstrap
* [ ] Dynamic Jenkins agent registration
* [ ] Workload execution
* [ ] Artifact collection
* [ ] Automated reporting
* [ ] Automatic worker destruction and Jenkins node removal

### Phase 4 — Reliability

* [x] Provisioner agent and NGINX service recovery configuration
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
