# OpsOrchestra

OpsOrchestra is an automation control platform built around Jenkins and ephemeral compute workers.

The initial architecture consists of an always-on Jenkins controller hosted locally and exposed through Cloudflare Zero Trust.

Future versions will dynamically provision ephemeral worker infrastructure using providers such as DigitalOcean and destroy that infrastructure when workloads complete.

## Current Architecture

```text
Internet
   |
   v
Cloudflare Zero Trust
   |
   v
Cloudflare Tunnel
   |
   v
OpsOrchestra Docker Network
   |
   +-- cloudflared
   |
   +-- Jenkins Controller