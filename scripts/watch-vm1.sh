#!/bin/bash
set -euo pipefail

NAMESPACE="${1:-ad-gomis-dev}"
INTERVAL="${2:-20}"

printf '[watch-vm1] namespace=%s interval=%ss\n' "$NAMESPACE" "$INTERVAL"

while true; do
  status=$(oc get vm vm1-firewall -n "$NAMESPACE" -o jsonpath='{.status.printableStatus}' 2>/dev/null || echo "Unknown")

  if [ "$status" != "Running" ] && [ "$status" != "Starting" ]; then
    printf '[watch-vm1] vm1-firewall status=%s -> start\n' "$status"
    virtctl start vm1-firewall -n "$NAMESPACE" >/dev/null 2>&1 || true
  fi

  sleep "$INTERVAL"
done
