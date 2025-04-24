# Elasticsearch Configuration Requirements

For Elasticsearch to work properly on Talos Linux nodes, the following sysctl configuration must be applied in the Talos machine configuration:

```
"machine":
  "sysctls":
    "vm.max_map_count": 262144
```