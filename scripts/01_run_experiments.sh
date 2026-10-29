#!/usr/bin/env bash
# Host-side OrbStack launcher. The VM script writes all evidence into this repo.
set -euo pipefail

VM_NAME="${VM_NAME:-ubuntu-2404-dev}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VM_PROJECT_DIR="/mnt/mac${PROJECT_DIR}"

if ! command -v orb >/dev/null 2>&1; then
    echo "ERROR: OrbStack CLI 'orb' is not installed or not on PATH." >&2
    exit 1
fi

mkdir -p "$PROJECT_DIR/evidence"
orb -m "$VM_NAME" bash "$VM_PROJECT_DIR/scripts/01_run_experiments_vm.sh" "$VM_PROJECT_DIR"
echo "Experiments finished. Review evidence/ and the three reports/ files."
