# Comments

Apply to every comment in every file (YAML, Terraform, Go, Markdown code fences, everywhere):

- Tasteful and terse: a comment should let another developer pick up what's going on quickly, not slow them down. Say what's needed, specifically, and stop — no filler, no restating what the code already makes obvious, no padding a short fact into a long sentence.
- No rationale essays: a short "why" is fine when it's the fact that matters (e.g. "avoids a dependency cycle"), but don't narrate the tradeoff, the alternatives considered, or the debugging story behind it. If explaining it properly needs more than a couple of lines, that's a sign it belongs in a design doc, not a comment.
- No migration/WIP narration: never "now lives in X", "moved to Y", "used to be Z", "previously". A comment describes the code at its current site, present tense.
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
