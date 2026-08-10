# Comments

Apply to every comment in every file (YAML, Terraform, Go, Markdown code fences, everywhere):

- Describe active functionality: say what the code does, at its current site, in present tense. A comment is not the place to argue for the code.
- Tasteful and terse: a comment should let another developer pick up what's going on quickly, not slow them down. Say what's needed, specifically, and stop — no filler, no restating what the code already makes obvious, no padding a short fact into a long sentence. One line is the norm; two is the ceiling.
- No justification: don't explain why a value was chosen, what breaks without it, what upstream does differently, or what a tool does internally. A short "why" is fine only when it is the operative fact (e.g. "avoids a dependency cycle"). Never narrate a tradeoff, an alternative considered, a failure mode, or the debugging story behind it. If it needs more than a couple of lines, it belongs in a design doc.
- No migration/WIP narration: never "now lives in X", "moved to Y", "used to be Z", "previously". A comment describes the code at its current site, present tense.
- Don't comment the diff: a comment explains the file as it stands, never what changed or why it changed. Reviewers read the diff; the comment outlives it.
- No ADR references: no links, no "See docs/adr/0003", no "ADR-0008". ADRs are internal/gitignored.
- No AI-punchy prose voice: no em-dashes as a rhetorical device, no antithesis ("not X, but Y"), no bold-headword bullets, no quotable fragments. Plain, flat, informational.

Default to no comment at all when the code is self-evident. When a comment is warranted, prefer the shorter version that still carries the specific, useful fact — not the shortest possible string, and not an exhaustive one.

Bad:
```yaml
# cilium/prometheus is a ServiceMonitor and needs Prometheus's CRDs, but
# cni-install itself must not wait on telemetry-install — csi-install
# depends on cni-install, and telemetry-install depends on csi-install
# (PVC needs the storage driver present at both install and destroy time).
# Keeping the CRD-dependent component in the resources tier avoids that cycle.
```

Good:
```yaml
# cilium/prometheus in resources, not install: avoids a cni-install ->
# telemetry-install -> csi-install -> cni-install cycle.
```

Bad:
```yaml
# Postgres, as its own resources tier so the server can wait on it. Waits
# for the database operator, which supplies the Cluster CRD. Timeout covers
# PVC bind and initdb, matching database-install. kstatus reports a CNPG
# Cluster Current the moment it is applied, so gate on its Ready condition.
```

Good:
```yaml
# Postgres, gated on the Cluster's Ready condition.
```
