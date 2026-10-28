#!/usr/bin/env bash
# Practice drill. Takes payment away, then puts it back.
set -euo pipefail

echo "Scaling payment to 0."
kubectl -n robot-shop scale deploy/payment --replicas=0
kubectl -n robot-shop get pods -l service=payment

cat <<'EOF'

Payment is down. Checkout should fail. The catalogue still loads.

What I check, in this order:
  kubectl -n robot-shop get pods
  Grafana, dashboard "Robot Shop requests, errors, latency"
  Loki: {namespace="robot-shop", service="payment"}
  The alert PaymentAvailabilityLow. It needs about 3 minutes.

The runbook is docs/runbook-payment.md.
The write-up of this drill is docs/postmortem.md.

EOF

if [[ -t 0 ]]; then
  read -r -p "Press enter to scale payment back to 1. "
  kubectl -n robot-shop scale deploy/payment --replicas=1
  kubectl -n robot-shop rollout status deploy/payment
else
  echo "Restore with: kubectl -n robot-shop scale deploy/payment --replicas=1"
fi
