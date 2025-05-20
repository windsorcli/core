# Azure AKS Module

This module creates an Azure Kubernetes Service (AKS) cluster with configurable node pools, networking, and security settings.

## Prerequisites

The following features must be enabled in your Azure subscription before using this module:

- EncryptionAtHost feature for Microsoft.Compute provider
  ```bash
  az feature register --namespace Microsoft.Compute --name EncryptionAtHost
  az provider register --namespace Microsoft.Compute
  ```

### Subscription Requirements

This module requires a paid Azure subscription. Free tier subscriptions are not supported due to:
- Insufficient vCPU quotas
- Restricted VM sizes
- Limited node pool operations
