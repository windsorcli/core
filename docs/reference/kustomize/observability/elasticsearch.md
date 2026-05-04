---
title: "Elasticsearch Configuration Requirements"
description: "Operator notes from kustomize/observability/elasticsearch (generated; edit README in kustomize/)."
---

# Elasticsearch Configuration Requirements

For Elasticsearch to work properly on Talos Linux nodes, the following sysctl configuration must be applied in the Talos machine configuration:

```
"machine":
  "sysctls":
    "vm.max_map_count": 262144
```