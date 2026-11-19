---
title: "ADR-0032: Node Feature Discovery labels device nodes and device plugins expose the devices"
description: Add a devices system that runs Node Feature Discovery and device plugins on Talos. It names the node labels and resource names for USB serial radios, transcoding GPUs, and video decoders, adds the Talos GPU extensions, and passes devices through to Incus and Proxmox VMs.
---

# ADR-0032: Node Feature Discovery labels device nodes and device plugins expose the devices

## Status

Proposed (2026-11-18). Builds on [ADR-0026](0026-talos-node-pools.md), which
sets node labels through `machine.nodeLabels`, and on
[ADR-0028](0028-supported-incus-platform.md) section 5, which delivers Talos
extensions by installer upgrade. Scope is `cluster.driver: talos` on
`metal`, `incus`, and `proxmox`. Section 8 states what happens on the other
platforms.

The `home` blueprint selects nodes by the labels in section 1 and requests the
resources in section 2. Both sections are a contract between `core` and
`home`. A change to either MUST go through a new ADR that gives `home` a
migration.

## Context

The `home` blueprint v0.1.0 needs three device classes:

- A USB serial radio (Zigbee or Z-Wave) for Home Assistant and Zigbee2MQTT.
- A GPU that transcodes video for Jellyfin and Immich.
- A video decoder for Frigate.

A `home` app pins to a node through its `nodeSelector` value. `core` has no
device support today. Without it, a pod reaches `/dev/ttyUSB0` or `/dev/dri`
only through a `hostPath` volume and a privileged container.

These facts decide the design:

- `core` pins Talos `1.14.5` (`config-talos.yaml`) and Kubernetes `v1.37.2`
  (`terraform/cluster/talos`). The Colima workstation path pins Talos
  `1.13.11` and Kubernetes `v1.36.5`, but `docker` is out of scope.
- Dynamic Resource Allocation (DRA) is GA in the `resource.k8s.io/v1` API
  from Kubernetes 1.34. A `ResourceClaim` is namespaced.
- The Talos 1.14 base image ships the USB serial drivers `cdc-acm`, `ch341`,
  `cp210x`, `ftdi_sio`, and `pl2303` (`hack/modules-amd64.txt` in
  `siderolabs/talos`). The Talos udev package keeps `60-serial.rules`, so a
  node has `/dev/serial/by-id/` links. A by-id name carries the USB product
  string, such as `usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_<serial>-if00-port0`.
- The GPU kernel drivers are not in the base image. Each one is a Talos
  extension: `siderolabs/i915` and `siderolabs/xe` for Intel,
  `siderolabs/amdgpu` for AMD, and `siderolabs/nonfree-kmod-nvidia-lts` with
  `siderolabs/nvidia-container-toolkit-lts` for NVIDIA. On the Talos 1.14
  extension branch, the NVIDIA LTS driver is `580.196.07` and the production
  driver is `595.112.07`.
- The NVIDIA toolkit extension needs the `nvidia`, `nvidia_uvm`,
  `nvidia_drm`, and `nvidia_modeset` modules in `machine.kernel.modules`,
  the sysctl `net.core.bpf_jit_harden: 1`, and a `RuntimeClass` with the
  handler `nvidia`.
- `core` already has the extension path. `config-talos.yaml` keeps a
  catalog (`talos_common.csi_extensions`) and `option-storage.yaml` runs
  `cluster/talos/extensions` when the storage driver needs one. That module
  upgrades nodes to `factory.talos.dev/installer/<schematic>`. It does not
  keep the `qemu-guest-agent` schematic or the nocloud installer that
  `platform-proxmox.yaml` uses.
- Node Feature Discovery (NFD) `v0.20.1` reads the instance features
  `pci.device` (`class`, `vendor`, `device`) and `usb.device` (`class`,
  `vendor`, `device`, `serial`), and the flag feature `kernel.loadedmodule`.
  A `NodeFeatureRule` sets labels from them. nfd-master allows every label
  namespace except `kubernetes.io` by default, so a `windsorcli.dev` key
  needs no `-extra-label-ns` flag.
- `squat/generic-device-plugin` (chart `0.2.0`) advertises host device files
  as extended resources. It matches paths by glob, mounts a match at a fixed
  `mountPath`, lets one device be allocated `count` times, and takes a
  `--domain` for the resource names. The Talos device-plugin guide and Red
  Hat MicroShift both use it.
- `compute/incus` already takes a `devices` map for each instance.
  `compute/proxmox` (`bpg/proxmox` `0.116.0`) has no USB or PCI block today.
  Its README grants a role that has no `Mapping.Use`.

### Support for each device class

| Device class | DRA driver | Device plugin | Picked |
|---|---|---|---|
| USB serial radio | None released. `kubernetes-sigs/dra-example-driver` is a sample. | `generic-device-plugin`. Akri `v0.14.0` discovers udev devices through its own agent, controller, and CRDs. | `generic-device-plugin` |
| Intel GPU (transcode, decode) | `intel-resource-drivers-for-kubernetes` `gpu-v0.12.1`, for Kubernetes 1.36 and later. Its README says "beta / non-production". | `intel-device-plugins-for-kubernetes` `v0.37.1`. The resource is `gpu.intel.com/i915` or `gpu.intel.com/xe` by kernel driver. `generic-device-plugin` on `/dev/dri/renderD*`. | `generic-device-plugin` |
| AMD GPU (transcode, decode) | `ROCm/k8s-gpu-dra-driver` `v1.0.1`. Not tested on Talos. | `ROCm/k8s-device-plugin` (`amd.com/gpu`). `generic-device-plugin` on `/dev/dri/renderD*`. | `generic-device-plugin` |
| NVIDIA GPU (transcode, decode) | `kubernetes-sigs/dra-driver-nvidia-gpu` `v0.5.1`. GPU allocation is GA from `v25.12.0`. | `NVIDIA/k8s-device-plugin` `v0.20.2`, with time-slicing. | NVIDIA device plugin |

A DRA claim shares one device between pods only through one `ResourceClaim`,
and a claim lives in one namespace. Jellyfin, Immich, and Frigate run in
their own namespaces and share one integrated GPU on a typical home node. A
device plugin with `count` or time-slicing shares the device across
namespaces with one `resources.limits` line in each pod. No released DRA
driver covers the USB serial class at all. This release therefore uses
device plugins for every class.

## Decision

### 1. Node labels

NFD sets these labels from `NodeFeatureRule` objects that `core` ships. The
value of each label is `"true"`. No other label is part of the contract. The
built-in `feature.node.kubernetes.io/*` labels stay at the NFD defaults.

| Label | Device class | Rule |
|---|---|---|
| `devices.windsorcli.dev/usb-serial` | USB serial radio | `kernel.loadedmodule` has one of `cdc_acm`, `ch341`, `cp210x`, `ftdi_sio`, `pl2303` |
| `devices.windsorcli.dev/gpu-intel` | Transcoding GPU | `pci.device` with `vendor: 8086` and `class` `0300` or `0380`, and `kernel.loadedmodule` has `i915` or `xe` |
| `devices.windsorcli.dev/gpu-amd` | Transcoding GPU | `pci.device` with `vendor: 1002` and `class` `0300` or `0380`, and `kernel.loadedmodule` has `amdgpu` |
| `devices.windsorcli.dev/gpu-nvidia` | Transcoding GPU | `pci.device` with `vendor: 10de` and `class` `0300` or `0302`, and `kernel.loadedmodule` has `nvidia` |
| `devices.windsorcli.dev/video-encode` | Transcoding GPU | Any `gpu-*` rule matches |
| `devices.windsorcli.dev/video-decode` | Video decoder | Any `gpu-*` rule matches |

A GPU rule requires the kernel module, so a node gets a GPU label only when
the matching extension from section 4 is installed. A GPU without its
extension gets no label and no resource.

`video-encode` and `video-decode` select by capability, so a `home` facet
does not list vendors. Both labels come from the same rules in this release,
because the media engine of a GPU does both. A later rule MAY set
`video-decode` alone for a decoder that is not a GPU, with no change to the
key.

The `usb-serial` rule reads loaded modules, because NFD does not read the USB
product string and the common bridge chips (`10c4:ea60`, `1a86:55d4`) carry
both Zigbee and Z-Wave radios. Talos udev loads the driver when the dongle is
plugged in. The label stays after an unplug until the node reboots. The
radio type is in the resource name (section 2), not in the label. The
implementation MUST confirm on Talos 1.14 that plugging a dongle loads its
driver with no `machine.kernel.modules` entry. If it does not, the rule MUST
match a `usb.device` vendor and device list instead, and this ADR is amended.

### 2. Resource names and container paths

A `home` pod requests one unit of the resource in `resources.limits`. The
device plugin mounts the device. The pod needs no `hostPath` volume, no
privileged container, and no extra capability, so it passes the `baseline`
Pod Security level.

| Resource | Device class | Host match | Container path | Shares |
|---|---|---|---|---|
| `devices.windsorcli.dev/zigbee` | Zigbee radio | `/dev/serial/by-id/` globs | `/dev/zigbee` | 1 |
| `devices.windsorcli.dev/zwave` | Z-Wave radio | `/dev/serial/by-id/` globs | `/dev/zwave` | 1 |
| `devices.windsorcli.dev/dri` | Intel or AMD GPU | `/dev/dri/renderD*` | `/dev/dri/<name>` | 10 |
| `nvidia.com/gpu` | NVIDIA GPU | NVIDIA device plugin | Set by the NVIDIA runtime | 10 (time-slicing) |

A pod that requests `nvidia.com/gpu` MUST set `runtimeClassName: nvidia`.

The default globs are `*Zigbee*`, `*ConBee*`, `*SkyConnect*`, and `*ZBT-1*`
for `zigbee`, and `*Z-Wave*` and `*0658_0200*` for `zwave`. The
implementation MUST check each glob against the by-id name of a real dongle,
and drop a glob that it cannot check. A dongle whose by-id name names only
its bridge chip (for example
`usb-Silicon_Labs_CP2102N_USB_to_UART_Bridge_Controller_<serial>`) matches
no default glob. The user adds a glob for it (section 5). The implementation
MUST also confirm that the plugin mounts a by-id symlink as a device node.

`dri` exposes render nodes only. VA-API and Quick Sync in Jellyfin and Frigate
need only `/dev/dri/renderD128`. A firmware framebuffer driver can add a
`card*` node with no render node, so the two globs would not pair. On a node with an NVIDIA GPU and a second
GPU, `dri` MAY hand out the NVIDIA render node. This release does not fix
that.

The containerd default gives a mounted device node the owner and mode it has
on the host, so a non-root app cannot open it. Talos MUST set the containerd
CRI option `device_ownership_from_security_context` through a CRI
customization file, so the device takes the pod's `runAsUser` and
`runAsGroup`.

The share counts are fixed in this release. A later ADR MAY add a values key
for them.

### 3. Components

`core` installs these parts in a new Flux system `devices`, in the namespace
`system-devices` with the `privileged` Pod Security level:

- `node-feature-discovery` (Helm chart `0.20.1` from
  `oci://registry.k8s.io/nfd/charts`). The master and worker run. The
  topology updater stays off. The `NodeFeatureRule` CRD follows the `crds:`
  layer rule for charts that ship CRDs.
- `generic-device-plugin` (chart `0.2.0`) with `--domain
  devices.windsorcli.dev` and the `zigbee`, `zwave`, and `dri` devices.
  The `dri` device is in the config only when `intel` or `amd` is in
  `devices.gpu.drivers`.
- `nvidia-device-plugin` (chart `0.20.2`) with `runtimeClassName: nvidia`
  and a time-slicing config of 10 replicas, only when `nvidia` is in
  `devices.gpu.drivers`. A `RuntimeClass` named `nvidia` with the handler
  `nvidia` ships with it.

The `install` tier holds the Helm releases and the `RuntimeClass`. The
`resources` tier holds the `NodeFeatureRule` objects, because they need the
CRD. Each Helm source gets the `chart-registry` component, like the other
systems. The DaemonSets select every Linux node and run as `system-*` Pods
under the Kyverno baseline policies.

The NVIDIA GPU Operator is not used. On Talos the extensions supply the
driver and the toolkit, which the Operator would otherwise install.

### 4. Talos extensions and machine config

`config-talos.yaml` adds a catalog next to `csi_extensions`:

| `devices.gpu.drivers` entry | Extensions |
|---|---|
| `intel` | `siderolabs/i915`, `siderolabs/xe` |
| `amd` | `siderolabs/amdgpu` |
| `nvidia` | `siderolabs/nonfree-kmod-nvidia-lts`, `siderolabs/nvidia-container-toolkit-lts` |

`talos_common.extensions` MUST be the union of the CSI entry and the device
entries. The `cluster-extensions` step and its `gitops` dependency MUST run
when that list is not empty, not only when the storage driver needs an
extension.

The NVIDIA entry uses the LTS branch, because it supports more of the older
consumer GPUs that home media servers use. The production branch MAY replace
it in a later release.

When `devices.enabled` is true, every node gets the containerd CRI patch from
section 2. When `nvidia` is in `devices.gpu.drivers`, every node also gets
the four NVIDIA modules in `machine.kernel.modules` and the sysctl
`net.core.bpf_jit_harden: 1`. That sysctl lowers a Talos KSPP default on
every node, control planes included, not only on nodes with an NVIDIA GPU.
This release accepts that cost, because `core` has no per-node or per-pool
machine config patch on every target platform yet. The `nvidia` entry MUST
say so in its schema description. A later ADR MAY scope the patch to the
nodes of one pool.

Extensions and patches apply to every node in this release. Talos loads
`i915`, `xe`, and `amdgpu` only on matching hardware. The NVIDIA modules are
in `machine.kernel.modules`, so Talos tries to load them on every node. The
implementation MUST check that a node with no NVIDIA GPU still boots and
joins with that patch. Extensions for one pool only wait for a later change
to ADR-0026.

### 5. Values

```yaml
devices:
  enabled: true          # NFD, generic-device-plugin, serial radios
  gpu:
    drivers: [intel]     # intel | amd | nvidia
  serial:
    zigbee: ["*MyCoordinator*"]   # added to the default zigbee globs
    zwave: []
```

- `devices.enabled` defaults to `false`. It installs the `devices` system and
  the CRI patch.
- `devices.gpu.drivers` defaults to `[]`. Each entry adds its extensions,
  its machine config, and its device plugin. A non-empty list with
  `devices.enabled: false` MUST fail composition with the message
  "devices.gpu.drivers needs devices.enabled: true".
- `devices.serial.zigbee` and `devices.serial.zwave` default to `[]`. Each
  entry is a glob under `/dev/serial/by-id/` that adds to the defaults.
- Each node entry in `cluster.controlplanes.nodes`, `cluster.workers.nodes`,
  and a pool's `nodes` gets `passthrough` (section 7).

### 6. Facet layout

A new facet `addon-devices.yaml` owns the `devices` Flux system, the
`requires:` rules, and the device catalog entries. `config-talos.yaml` owns
the extension catalog and the machine config patches. `option-storage.yaml`
keeps the `cluster-extensions` step with the new condition from section 4.
`platform-incus.yaml` and `platform-proxmox.yaml` map `passthrough` into
their compute inputs. The Kustomize tree is `kustomize/devices/install` and
`kustomize/devices/resources`.

### 7. Platforms

#### metal

The devices are on the host, so no passthrough exists. `passthrough` on a
`metal` node MUST fail composition with the message "passthrough is not
supported on platform metal". Extensions reach the node through
`cluster/talos/extensions`. A node's `install_image` MUST carry the device
extensions, as the schema already says for the storage extensions.

#### incus

The Incus member that hosts the VM gives the device to it:

```yaml
cluster:
  workers:
    nodes:
      worker-1:
        placement: host-a
        passthrough:
          - type: usb
            id: "10c4:ea60"        # vendor:product
          - type: pci
            id: "0000:00:02.0"     # PCI address on the member
```

`platform-incus.yaml` maps a `usb` entry to an Incus `usb` device with
`vendorid` and `productid`, and a `pci` entry to an Incus `pci` device with
`address`. The member that `placement` names MUST have the device. A PCI
device needs IOMMU and VFIO on the member, and it leaves the member while the
VM runs. Extensions follow ADR-0028 section 5, so the schematic MUST keep
`incus-guest-agent` when the extension list grows.

#### proxmox

Proxmox passes a device to a VM through a cluster resource mapping. A
mapping is what lets a role without `root@pam` attach host hardware.

```yaml
cluster:
  workers:
    nodes:
      worker-1:
        placement: pve1
        passthrough:
          - type: usb
            mapping: zigbee        # Datacenter > Resource Mappings > USB
          - type: pci
            mapping: igpu          # Datacenter > Resource Mappings > PCI
```

`compute/proxmox` adds a `usb` block with `mapping` and a `hostpci` block
with `mapping` and `pcie = true` for each entry. The VM already uses the
`q35` machine type on `amd64`. The role MUST gain `Mapping.Use` on
`/mapping/usb/<id>` and `/mapping/pci/<id>`, and the README MUST list it.
The user creates the mappings, and the mapping MUST have an entry for the
node that `placement` names. On `proxmox`, an entry with `id` and no
`mapping` MUST fail composition. On `incus`, an entry with `mapping` and no
`id` MUST fail composition.

The extensions step MUST build its Proxmox installer from a schematic that
keeps `siderolabs/qemu-guest-agent`, and it MUST use
`factory.talos.dev/nocloud-installer`. Today the step uses the plain
installer with the requested extensions only, which also breaks `longhorn`
on Proxmox. The fix is in scope for the implementation of this ADR, and it
MUST land in its own PR before the device extensions, so `longhorn` gets it
without `devices.enabled`.

### 8. Scope on the other platforms

- `docker`: `devices.enabled` MUST fail composition. Talos in a container
  takes no extension.
- `aws`, `azure`, `gcp` (`eks`, `aks`, `gke`): `devices.enabled` MUST fail
  composition. Those platforms use the vendor's GPU node images.
- `hyperv`, `vsphere`, `hetzner`: the `devices` system and the extensions
  install, with no acceptance test. `passthrough` MUST fail composition there.

### 9. Tests and verification

- Facet tests cover each `devices.gpu.drivers` entry, the extension union
  with `longhorn`, every `requires:` message, and the `passthrough` mapping
  on `incus` and `proxmox`.
- The implementation MUST record, in its PR, a live run on one Talos node
  with an Intel integrated GPU and one USB Zigbee dongle. The run shows the
  labels from section 1, the resources from section 2, a non-root pod that
  opens `/dev/zigbee`, and a pod that runs `vainfo` on `/dev/dri/renderD128`.
- NVIDIA, AMD, Incus passthrough, and Proxmox passthrough ship without a
  live run. Their schema descriptions MUST say that they are untested.

## Consequences

- A `home` facet requests a resource and sets a `nodeSelector` default from
  section 1. It needs no `hostPath` or privileged Pod, which closes that open
  point of `home` v0.1.0.
- The labels and resource names are a contract. Moving a class to DRA later
  changes how a pod asks for the device, so that ADR MUST keep the labels and
  give `home` a migration for the resource.
- `generic-device-plugin` is one maintainer's project. It covers the serial
  and render-node classes with one component and one resource domain.
- `nvidia` relaxes `bpf_jit_harden` on every node of the cluster.
- The device extensions add one installer upgrade and reboot per node, the
  same cost as the storage extensions.

## Alternatives considered

- DRA for every class. No DRA driver covers USB serial devices. The Intel
  GPU driver is beta. A claim shares a device inside one namespace only, and
  every `home` app would need a `ResourceClaimTemplate`.
- The Intel GPU device plugin. It names its resource by kernel driver
  (`i915` or `xe`), so a facet would branch on the GPU generation. Its
  operator adds CRDs that a home node does not need.
- The AMD ROCm device plugin. It targets ROCm compute. VA-API needs only the
  render node, which `generic-device-plugin` already exposes.
- Akri for the serial class. It needs a controller, an agent, CRDs, and a
  broker per device, for the same result.
- Radio labels from a USB vendor and device list. Zigbee and Z-Wave sticks
  share bridge chips, so the list cannot tell them apart.
- One label with the GPU vendor as its value. A node with an integrated GPU
  and a discrete GPU needs two values.
- The NVIDIA GPU Operator. On Talos it duplicates the driver and toolkit
  extensions.

## References

- [Node Feature Discovery customization guide](https://kubernetes-sigs.github.io/node-feature-discovery/master/usage/customization-guide.html)
- [nfd-master command line reference](https://kubernetes-sigs.github.io/node-feature-discovery/master/reference/master-commandline-reference.html)
- [squat/generic-device-plugin](https://github.com/squat/generic-device-plugin)
- [Talos device plugins guide](https://docs.siderolabs.com/kubernetes-guides/advanced-guides/device-plugins)
- [siderolabs/extensions](https://github.com/siderolabs/extensions)
- [Intel GPU resource driver](https://github.com/intel/intel-resource-drivers-for-kubernetes/blob/main/doc/gpu/README.md)
- [DRA driver for NVIDIA GPUs](https://dra-driver-nvidia-gpu.sigs.k8s.io/docs/)
- [NVIDIA device plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [ROCm GPU DRA driver](https://github.com/ROCm/k8s-gpu-dra-driver)
