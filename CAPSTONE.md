# Robot Shop, second capstone

This fork starts from [instana/robot-shop](https://github.com/instana/robot-shop) and lives at [wsticks/robot-shop](https://github.com/wsticks/robot-shop). I install it with the Helm chart that came with the repo, on the same EKS cluster as the voting app. The Instana agent is not part of this install.

The four services I actually watch are web, catalogue, cart, and payment. The rest just need to be up. Mongo, Redis, MySQL, and RabbitMQ come along with the chart.

## Instana

I took the agent host env var off cart, catalogue, user, dispatch, and payment, and off the Istio payment example. `eum.key` is empty, so the web pod does not get `INSTANA_EUM_KEY` either. I do not install the Instana agent chart.

The Python and Node files still import the Instana libraries. That is library code, not the agent. Payment is the exception: I removed `import instana` there because that process is the one sending traces to the OpenTelemetry collector instead.

## Install

You need the cluster from the voting-app Terraform, and `kubectl` pointed at it.

```bash
export SLACK_WEBHOOK_URL='https://hooks.slack.com/services/...'   # not committed
./observability/install.sh
```

The script installs kube-prometheus-stack, Loki, Fluent Bit, Jaeger, the collector, blackbox, the alert rules, the dashboard, and the shop. Load-gen starts with the shop (`loadgen.enabled` in `K8s/helm/values-capstone.yaml`) so there is traffic without me clicking around.

Grafana user is `admin`, password `prom-operator`. That is the chart default. Change it with `--set grafana.adminPassword=...` if the Grafana port is open to anything but your laptop.

```bash
kubectl -n robot-shop port-forward svc/web 8080:8080
kubectl -n observability port-forward svc/kube-prom-grafana 3000:80
kubectl -n observability port-forward svc/jaeger 16686:16686
```

Redis asks for a `gp3` volume. The storage class manifest and the EBS driver from the voting-app Terraform are what make that bind. If your cluster already has a different default class, change `redis.storageClassName` in the capstone values.

## One trace

The stock `robotshop/rs-payment` image does not have the OpenTelemetry packages, so a trace will not appear until payment is rebuilt.

```bash
docker build -t robotshop/rs-payment:capstone payment/
# push it somewhere the nodes can pull, then
# set payment.image in K8s/helm/values-capstone.yaml to that name
```

If you have not pushed it yet, install with the stock image:

```bash
SKIP_PAYMENT_IMAGE=1 ./observability/install.sh
```

When the new image is running, the collector config is `observability/otel-collector.yaml`. It listens for OTLP and forwards to Jaeger. Payment gets these env vars from the chart when `payment.otel.enabled` is true:

- `OTEL_SERVICE_NAME=payment`
- `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.observability.svc.cluster.local:4317`
- `OTEL_EXPORTER_OTLP_INSECURE=true`

Buy something in the shop (or let load-gen do it). In Jaeger, service `payment`, look for a span around `POST /pay`. The requests library calls to user, the gateway, and cart show up as child spans.

## Logs

Fluent Bit is a DaemonSet. It tails `/var/log/containers` and pushes to Loki with the namespace and the pod's `service` label.

```
{namespace="robot-shop", service="payment"} |= "ERROR"
{namespace="robot-shop", service="catalogue"} |= "error"
```

Service is a label. Level is a word in the line. Payment logs look like `ERROR` because of the Python formatter. Catalogue uses pino, so the word is usually `error` in the JSON.

## Dashboard

`observability/dashboards/robot-shop.json` is the dashboard. The install script loads it as a ConfigMap with the label the Grafana sidecar watches, so it shows up without me clicking import.

Panels:

- probe success for web, catalogue, cart, payment
- error ratio, which is just `1 - probe_success`
- probe latency
- payment request rate and p95, from the counters I added in `payment/payment.py`
- cart `items_added`, which the stock cart image already exposes

The payment request panels stay empty until the rebuilt image is the one running. The probe panels work against the stock images.

## SLO, runbook, drill

- `docs/slo.md` is the one page policy. 99% payment availability, 7 hours 12 minutes of budget in 30 days.
- `docs/runbook-payment.md` is what the alert links to.
- `scripts/drill-payment.sh` scales payment to 0. The alert should hit Slack in a few minutes. The write-up is `docs/postmortem.md`.

## Hand-in map

| Asked for | Where it is |
| --- | --- |
| Dashboard as code | observability/dashboards/robot-shop.json |
| Logging config | observability/fluent-bit.yaml and observability/loki.yaml |
| Tracing config | observability/otel-collector.yaml, observability/jaeger.yaml, payment env in the chart |
| SLO and error budget | docs/slo.md |
| Blameless postmortem | docs/postmortem.md |
| Runbook linked from the alert | https://github.com/wsticks/robot-shop/blob/main/docs/runbook-payment.md |
