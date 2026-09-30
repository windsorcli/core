---
title: Elasticsearch configuration requirements
description: Talos machine config sysctl Elasticsearch needs to run.
---

For Elasticsearch to work on Talos Linux nodes, apply this sysctl in the Talos machine configuration:

```
"machine":
  "sysctls":
    "vm.max_map_count": 262144
```
