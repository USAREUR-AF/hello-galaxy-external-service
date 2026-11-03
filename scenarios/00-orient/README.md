# 00 — Orient

Prints the concept, the trust rule and the boundary rule, then checks your machine has
what the other scenarios need.

```bash
bash scenarios/00-orient/run.sh
```

What you will read:

- an **external service** is off-box, non-core and often temporary
- the **trust rule**: the goatnet authenticates, your service authorizes, claims grant nothing
- why the **fence is on your own host**: it sits in a tier every role group reaches directly
- the **boundary rule**: a temporary service's name lives only in its own declaration

Prerequisites checked: a Python with `PyJWT`, `cryptography` and `PyYAML`, and `curl`.
Nothing is started and nothing is written.
