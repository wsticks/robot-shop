#!/usr/bin/env bash
# Installs the shop and the bits I use to watch it.
# Run this from the robot-shop repo root, with kubectl pointed at the capstone cluster.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "kubectl is not talking to a cluster yet."
  echo "From the voting-app repo: terraform apply, then aws eks update-kubeconfig."
  exit 1
fi

kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace robot-shop --dry-run=client -o yaml | kubectl apply -f -

if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
  echo "SLACK_WEBHOOK_URL is not set."
  echo "Create an incoming webhook in Slack and export it in this shell. It is not written to git."
  exit 1
fi

kubectl -n observability create secret generic alertmanager-slack \
  --from-literal=webhook-url="$SLACK_WEBHOOK_URL" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f observability/storageclass-gp3.yaml

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kube-prom prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --version 65.8.1 \
  -f observability/kube-prometheus-stack-values.yaml \
  --wait --timeout 15m

kubectl apply -f observability/loki.yaml
kubectl apply -f observability/fluent-bit.yaml
kubectl apply -f observability/jaeger.yaml
kubectl apply -f observability/otel-collector.yaml
kubectl apply -f observability/blackbox.yaml
kubectl apply -f observability/probes-and-rules.yaml

kubectl -n observability create configmap robot-shop-dashboard \
  --from-file=robot-shop.json=observability/dashboards/robot-shop.json \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n observability label configmap robot-shop-dashboard grafana_dashboard=1 --overwrite

# Only turn tracing on if the rebuilt payment image is what we are about to install.
HELM_VALUES=( -f K8s/helm/values-capstone.yaml )
if [[ "${SKIP_PAYMENT_IMAGE:-}" == "1" ]]; then
  HELM_VALUES+=( --set payment.image="" --set payment.otel.enabled=false )
  echo "Installing the stock payment image. Traces will not show until you build payment/."
fi

helm upgrade --install robot-shop K8s/helm \
  --namespace robot-shop \
  "${HELM_VALUES[@]}"

echo
echo "Shop:    kubectl -n robot-shop port-forward svc/web 8080:8080"
echo "Grafana: kubectl -n observability port-forward svc/kube-prom-grafana 3000:80"
echo "         user admin, password prom-operator (the chart default)"
echo "Jaeger:  kubectl -n observability port-forward svc/jaeger 16686:16686"
echo "Loki:    {namespace=\"robot-shop\", service=\"payment\"} |= \"ERROR\""
