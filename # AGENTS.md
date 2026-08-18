# AGENTS.md

# OpsOrchestra

OpsOrchestra is an automation orchestration platform for managing execution engines, infrastructure, and ephemeral workers through a unified control plane.

Jenkins is the initial execution engine, but the architecture should not assume Jenkins is the only backend OpsOrchestra will ever support.

The long-term goal is to allow OpsOrchestra to coordinate:

- Jenkins controllers and jobs
- ephemeral Linux/Windows workers
- cloud infrastructure provisioning
- Terraform and Ansible workflows
- containerized execution environments
- external automation services
- stateful, event-driven automation workflows

OpsOrchestra should own orchestration and lifecycle decisions. Execution engines such as Jenkins should focus on executing work.

---

## Engineering Philosophy

Prefer simple systems that can grow.

Do not introduce complexity unless it solves a real problem.

When choosing between:

1. a clever solution
2. a boring, understandable, maintainable solution

Prefer the maintainable solution unless the clever solution provides a clear architectural benefit.

Infrastructure should be reproducible.

Manual configuration should be minimized.

Anything important enough to rebuild should eventually be represented in this repository.

---

## Architecture Principles

### Jenkins Controller

The Jenkins controller should:

* orchestrate jobs
* manage configuration
* schedule work
* remain relatively lightweight

The controller should **not** become the primary execution host.

Builds and automation workloads should run on agents whenever practical.

---

### Jenkins Agents

Agents should be treated as disposable compute.

Design agents so they can eventually be:

1. created
2. connected to Jenkins
3. execute work
4. return results
5. shut down or destroyed

Avoid designs that require significant persistent state on agents.

Prefer bootstrap automation over manually configured hosts.

---

### Containers

Use official container images whenever practical.

Do not create custom images unless there is a clear reason.

Container configuration should be explicit and reproducible.

For Docker Compose:

* keep configuration readable
* use named volumes for persistent data
* use environment variables for deployment-specific configuration
* never store credentials directly in compose files
* pin important image versions when stability matters

Docker Compose files belong in the repository.

---

## Security

Security should be designed into the system rather than added later.

### Secrets

Never commit:

* passwords
* API keys
* Cloudflare tokens
* Jenkins secrets
* SSH private keys
* cloud provider credentials

Use environment variables, secret stores, Jenkins credentials, or external secret management.

Provide `.env.example` files when environment variables are required.

---

### Network Exposure

Avoid exposing management interfaces directly to the public internet.

Jenkins should be accessed through Cloudflare Zero Trust / Cloudflare Tunnel.

Prefer outbound tunnel connections instead of opening inbound firewall ports.

Do not add public ports unless there is a documented reason.

---

### Least Privilege

Services and automation should receive only the permissions they need.

Avoid:

* privileged containers
* broad sudo access
* unrestricted API tokens
* root execution when unnecessary

If elevated privileges are required, document why.

---

## Repository Structure

Keep the repository organized by responsibility.

A likely structure is:

```text
.
├── AGENTS.md
├── README.md
├── compose.yaml
├── .env.example
├── config/
│   └── jenkins/
├── scripts/
├── infrastructure/
│   ├── terraform/
│   └── ansible/
└── docs/
```

Do not create directories merely to match this structure.

Add them when the project actually requires them.

---

## Coding Style

### General

Prefer:

* small understandable functions
* clear names
* explicit behavior
* DRY implementations
* structured logging
* useful error messages

Avoid unnecessary abstractions.

Do not rewrite functioning code simply to make it stylistically different.

---

### Shell

Shell scripts should:

* use Bash when Bash functionality is required
* use `set -euo pipefail` when appropriate
* quote variables
* fail clearly
* validate required environment variables
* return meaningful exit codes

Prefer commands that can safely be run multiple times.

---

### YAML

YAML should prioritize readability.

Avoid excessive nesting.

For Docker Compose:

* group related configuration logically
* use named networks where useful
* use named volumes for persistent state
* document unusual configuration

---

### Python

When Python is used:

* prefer Python 3
* use type hints where useful
* favor standard library solutions when reasonable
* use structured logging rather than scattered print statements
* separate infrastructure/API logic from business logic

---

## Automation

Automation should be idempotent whenever practical.

Running an automation twice should not unexpectedly damage or duplicate infrastructure.

Provisioning logic should clearly distinguish between:

* desired state
* current state
* actions required to reach desired state

This project may evolve toward controller/state-machine-based orchestration.

When designing provisioning workflows, favor explicit states instead of large sequences of loosely connected scripts.

Example conceptual lifecycle:

```text
REQUESTED
    ↓
PROVISIONING
    ↓
BOOTSTRAPPING
    ↓
CONNECTING
    ↓
READY
    ↓
RUNNING
    ↓
IDLE
    ↓
TERMINATING
    ↓
TERMINATED
```

Do not implement this state machine unless the current task requires it.

Use it as an architectural direction.

---

## Changes

Before making significant changes:

1. inspect the existing repository
2. understand the current architecture
3. identify the smallest useful change
4. preserve existing working behavior
5. explain architectural consequences when relevant

Do not perform broad refactors unless requested or clearly necessary.

When discovering something that changes the architecture, point it out before burying it inside an implementation.

---

## Testing

Configuration changes should be validated whenever tools exist to validate them.

Examples:

```bash
docker compose config
```

```bash
bash -n script.sh
```

```bash
terraform validate
```

```bash
ansible-playbook --syntax-check playbook.yml
```

When changing executable code, run relevant tests if they exist.

Do not claim a test passed unless it was actually executed.

---

## Documentation

Update documentation when behavior, configuration, or architecture changes.

README documentation should explain how a human operates the project.

AGENTS.md should explain how an AI coding agent should work within the project.

Architecture decisions that require substantial explanation should eventually move into:

```text
docs/architecture/
```

rather than making this file excessively large.

---

## Working With the User

The user is technically experienced and comfortable with:

* Linux
* Docker
* networking
* Jenkins
* Ansible
* Terraform
* Kubernetes
* Bash
* PowerShell
* CI/CD
* infrastructure architecture

Do not over-explain basic system administration concepts unless they are relevant to a decision.

Focus explanations on:

* architecture
* tradeoffs
* failure modes
* security
* maintainability
* how components interact

When proposing an implementation, explain **why the design makes sense**, not merely which commands to type.

The user prefers understanding and controlling the architecture rather than blindly copying generated code.

---

## Agent Behavior

When working in this repository:

* inspect before editing
* make focused changes
* preserve working behavior
* avoid unnecessary dependencies
* do not invent infrastructure that does not exist
* do not silently change architectural direction
* never expose secrets
* run available validation after changes
* report what changed
* report what was tested
* report anything that still needs human action

When uncertain between two architectural approaches, describe the tradeoff rather than silently choosing a major direction.

For small implementation details, use good engineering judgment and proceed.