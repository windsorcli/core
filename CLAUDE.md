# Comments

This section applies to every comment in every file: YAML, Terraform, Go, Markdown code fences, everywhere. Rules below use RFC 2119 keywords (MUST, MUST NOT, SHOULD, MAY). Comments that state an obligation or constraint about the code MUST use the same words, not hedged phrasing ("this needs to", "it's important that").

Comments exist only to clarify code that is not self-evident. They MUST NOT narrate.

- A comment MUST describe active functionality: what the code does, at its current site, present tense.
- A comment MUST be one line. It MAY run to two lines only when a single short "why" clause is the operative fact (e.g. "avoids a dependency cycle"). Never three.
- A comment MUST carry exactly one idea. It MUST NOT chain facts with dashes, semicolons, or "so"/"which" clauses.
- A comment MUST NOT justify: no rationale for a value, no "what breaks without it", no what upstream does internally, no tradeoffs, no alternatives considered, no debugging story. That belongs in a design doc, not a comment.
- A comment MUST NOT narrate migration or WIP history: never "now lives in X", "moved to Y", "used to be Z", "previously".
- A comment MUST NOT describe the diff. It explains the file as it stands. Reviewers read the diff; the comment outlives it.
- A comment MUST NOT reference ADRs: no links, no "See docs/adr/0003". ADRs are internal and gitignored.
- A comment MUST NOT use AI-punchy prose: no em-dash as rhetoric, no antithesis ("not X, but Y"), no bold-headword bullets, no quotable fragments.

Default: no comment. Add one only when its absence would leave the code genuinely unclear.

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

Bad:
```yaml
# Provider package install, plus a ClusterPolicy that force-sets the
# windsorcli.dev/cluster tag on every Instance CR — the crossplane_rds
# IAM role's tag condition needs it, so it ships bundled with the
# provider rather than requiring a chart author to remember it.
```

Good:
```yaml
# Provider package install. Bundles a ClusterPolicy that force-sets
# the windsorcli.dev/cluster tag the IAM role's condition requires.
```

# Commits

- The subject line MUST be a short imperative sentence (Conventional Commits format, as already used in this repo's history).
- The body MUST be omitted by default.
- The body MAY exist only to state a fact the diff itself cannot show: a live-verified result, an issue number, a measured number. It MUST NOT restate what the diff already shows.
- The body MUST NOT narrate the debugging process, alternatives considered, or tradeoffs weighed. That belongs in the PR discussion, never in permanent commit history.
