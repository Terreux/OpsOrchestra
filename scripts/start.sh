#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
    echo "ERROR: .env does not exist."
    echo
    echo "Create it with:"
    echo "  cp .env.example .env"
    echo
    echo "Then add your Cloudflare tunnel token."
    exit 1
fi

echo "Starting OpsOrchestra..."
docker compose pull
docker compose up -d

echo
docker compose ps