# Payment availability, and the error budget

The number I care about is whether a customer can pay. Browsing can be slow for a minute. Checkout cannot.

## The SLI

Success rate of the payment service.

I count two things, and the worse one wins:

1. The blackbox probe of `http://payment:8080/health`. That is a request from inside the cluster, every 30 seconds. `probe_success` is 1 when payment answers, 0 when it does not.
2. Real checkouts, once the rebuilt payment image is running. `payment_requests_total` split by status. Anything in the 500s is a failure. `/metrics` and `/health` are not in that counter, so the scrape does not water down the number.

The other three services I watch (web, catalogue, cart) are on the same dashboard, but the SLO is payment. That is the one that takes money.

## The SLO

99% of payment checks succeed, measured over a rolling 30 days.

I picked 99% and not 99.9% because this is one replica of a demo shop on two nodes. A single pod restart already eats a 99.9% budget. 99% is a number I can defend in the Q&A.

## The error budget

1% of 30 days.

30 * 24 * 60 * 0.01 = 432 minutes, which is 7 hours and 12 minutes.

That is the amount of payment downtime the SLO allows in a month. It is not a target. It is the slack I have for releases, a bad node, and the drill.

## What we do with the budget

| Budget left | What I do |
| --- | --- |
| More than half | Normal changes. I still roll back if the alert fires. |
| Under half | No feature work on payment, cart, or the gateway call. Fixes only. |
| Gone | Freeze the shop chart. The only changes are the ones that stop the errors. |

A release that trips `PaymentAvailabilityLow` gets rolled back the same day. I do not spend the afternoon debugging it in production while checkout is red. The runbook says mitigate first.

## The alert

`PaymentAvailabilityLow` pages Slack when, for 2 minutes, either the 5 minute probe success is under 99% or the 5 minute checkout error rate is over 5%. Five percent in five minutes is a fast burn. At that rate the monthly budget is gone in a couple of hours, so I do not wait for the 30 day number to move.

`PaymentErrorBudgetBurn` is the slower one. It looks at the last hour. I left it in because a slow leak (a gateway that fails one request in fifty) would never trip the fast alert and would still empty the budget. It is a ticket, not a page.

Both alerts carry `runbook_url` set to https://github.com/wsticks/robot-shop/blob/main/docs/runbook-payment.md.

The Slack webhook is a Kubernetes secret named `alertmanager-slack`. The install script creates it from `SLACK_WEBHOOK_URL`. The URL is not in the repo.

## What this SLO does not cover

Web, catalogue, and cart have graphs and probes. They do not have their own budget yet. If I add one later it would be the same shape: probe success, 99%, 30 days. I am not writing three policies for a one week lab.
