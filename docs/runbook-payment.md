# Runbook: PaymentAvailabilityLow

The alert means payment is missing, or checkout is returning errors. The shop front page can still look fine. Do not trust the homepage.

Linked from the alert annotation `runbook_url`.

## Mitigate first

1. `kubectl -n robot-shop get pods -l service=payment`
2. If the count is 0, or the pod is not Running:
   ```bash
   kubectl -n robot-shop scale deploy/payment --replicas=1
   kubectl -n robot-shop rollout status deploy/payment
   ```
   The drill script scales it to 0. This is the undo.
3. If the pod is CrashLoopBackOff and a rollout just happened:
   ```bash
   helm -n robot-shop history robot-shop
   helm -n robot-shop rollback robot-shop
   ```
4. Tell the channel you scaled it or rolled it back, then keep looking. Restoring the pod is not the root cause.

## Find out why

Logs, payment only, errors only:

```
{namespace="robot-shop", service="payment"} |= "ERROR"
```

In Grafana that is the Loki datasource. The same query works in a port-forward to Loki on port 3100 if you have logcli. Fluent Bit copies the `service` label from the pod. Payment writes its level in the line (`ERROR`), so the search is a filter, not a label.

If the rebuilt image is in and tracing is on, open Jaeger (service `payment`) for the same minute. A checkout span that stops on the PayPal call means the gateway, not the pod.

Things that have actually broken this service:

- Replica count was changed with `kubectl scale` and no longer matches the chart. `kubectl -n robot-shop get deploy payment -o jsonpath='{.spec.replicas}'` shows 0. Helm still thinks it is 1. The next `helm upgrade` will set it back, which is what you want.
- `PAYMENT_GATEWAY` points somewhere that is not returning 200. Payment logs the URL and the status. Set it back or leave the value empty so it uses the default.
- The image tag in `values-capstone.yaml` was never pushed, so the pod is ImagePullBackOff. Either push `robotshop/rs-payment:capstone` or reinstall with `SKIP_PAYMENT_IMAGE=1`.
- The node ran out of memory and the pod was evicted. `kubectl -n robot-shop describe pod -l service=payment` says Evicted. That is a cluster problem, not a payment bug. Look at the node, not the Python.

## After it is green

Watch the payment panels on the Robot Shop dashboard for ten minutes. The fast alert resolves on its own once `probe_success` is back to 1. If it is the third time today, stop shipping and read the error budget section in `docs/slo.md`.
