# Postmortem: payment had no replicas

Status: practice drill, not a customer outage.
Severity: checkout down, browsing still worked.
Length: about 15 minutes from the scale-down to the pod being Ready again.

## Summary

Payment was scaled to 0 replicas. The web, catalogue, and cart pods stayed up, so the front of the shop looked healthy. Paying for a cart failed. The availability alert fired. Scaling the deployment back to 1 replica restored checkout. Nothing was wrong with the payment code.

## Impact

Anyone who reached the payment step got an error. People only looking at products were fine. Load-gen kept running and its payment calls failed for the same window. No orders were lost in a database, because the request never got into payment.

## Timeline

Times are from my laptop clock during the drill. The script is `scripts/drill-payment.sh`.

| Time | What happened |
| --- | --- |
| 0:00 | `kubectl scale deploy/payment --replicas=0`. The payment pod went away. |
| 0:01 | `kubectl get pods` showed web, catalogue, and cart still Running, and no payment pod. I checked the homepage first, which was a waste of a minute. |
| 0:02 | Probe latency panel stopped getting a 200 from payment. The other three probes stayed at 1. |
| 0:04 | Loki query `{namespace="robot-shop", service="payment"}` went quiet. No new lines. That matched "the process is gone", not "the process is throwing". |
| ~0:05 | `PaymentAvailabilityLow` went to Slack. The message had the runbook path on it. |
| 0:06 | Followed the runbook. `spec.replicas` was 0. Scaled it back to 1. |
| 0:08 | Pod Ready. Probe returned to 1. I did not roll the chart back, because the chart was never the thing that changed. |
| 0:15 | Alert cleared after the 5 minute window filled back up with successes. |

## Root cause

The replica count was changed on the live deployment and not in the Helm values. Helm's last release still said 1. Kubernetes was running 0. The payment container, the database, and the gateway were all fine.

I am writing this down because it is easy to call that "the cluster broke". It did not. A person (in the drill, me, on purpose) edited the running object.

## What helped

- The alert carried the runbook, so I did not go hunting through old notes.
- Probes on all four services made it obvious the failure was payment and not "the whole shop".
- Logs going silent was a useful signal. An ERROR line would have meant the process was alive and unhappy. No lines meant it was gone.

## What did not help

- I opened the website first. It loads without payment, so it told me nothing.
- Jaeger had nothing for the gap. There is no trace when the process is not there. I should have looked at pod count before I looked at traces. The runbook order is pods, then logs, then traces, and I did traces too early.

## Action items

| Item | Done |
| --- | --- |
| Runbook says to read `spec.replicas` before guessing at the code | yes, in docs/runbook-payment.md |
| Fast alert is 2 minutes, not 15, so a drill finishes inside the demo | yes |
| After a drill, `helm upgrade` once so the replica count is owned by the chart again | do this at the end of the demo if I scaled by hand |

## Blameless note

The scale-down was the drill. If the same thing happens because someone was debugging and forgot to scale back up, the fix is the same and the write-up should still name the change, not the person.
