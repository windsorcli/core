---
title: "ADR-0032: Node Feature Discovery labels device nodes and device plugins expose the devices"
description: Add a devices system that runs Node Feature Discovery and device plugins on Talos. It names the node labels and resource names for USB serial devices and Intel GPUs, adds the Talos Intel GPU extensions, and passes devices through to Incus and Proxmox VMs.
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
- The Intel GPU kernel drivers are not in the base image. They are the
  Talos extensions `siderolabs/i915` and `siderolabs/xe`. Lunar Lake,
  Battlemage, and newer GPUs bind `xe`. Older Intel GPUs bind `i915`.
- `core` already has the extension path. `config-talos.yaml` keeps a
  catalog (`talos_common.csi_extensions`) and `option-storage.yaml` runs
  `cluster/talos/extensions` when the storage driver needs one. That module
  upgrades nodes to `factory.talos.dev/installer/<schematic>`. It does not
  keep the `qemu-guest-agent` schematic or the nocloud installer that
  `platform-proxmox.yaml` uses.
- Node Feature Discovery (NFD) `v0.20.1` reads the instance features
  `pci.device` (`class`, `vendor`, `device`) and `usb.device` (`class`,
  `vendor`, `device`, `serial`), and the flag feature `kernel.loadedmodule`.
  A `NodeFeatureRule` sets labels from them. nfd-master allows the
  `feature.node.kubernetes.io` namespace by default.
- Kubernetes reserves the `kubernetes.io` domain and its subdomains for
  extended resource names, so a device plugin registers its resources under
  a domain its owner picks, such as `gpu.intel.com`.
- Intel's GPU device plugin (`intel-device-plugins-for-kubernetes`
  `v0.37.1`) registers each GPU as `gpu.intel.com/i915` or
  `gpu.intel.com/xe`, by the kernel driver that bound it. Its
  `-shared-dev-num` flag lets several containers share one GPU. Upstream
  ships it as a plain DaemonSet, and as a Helm chart that needs its operator.
- `squat/generic-device-plugin` (chart `0.2.0`) advertises host device files
  as extended resources. It matches paths by glob, mounts a match at a fixed
  `mountPath`, lets one device be allocated `count` times, and takes a
  `--domain` for the resource names. The Talos device-plugin guide and Red
  Hat MicroShift both use it.
- `compute/incus` already takes a `devices` map for each instance.
  `compute/proxmox` (`bpg/proxmox` `0.116.0`) has no USB or PCI block today.
  Its README grants a role that has no `Mapping.Use`.

### Support for each device class

The `home` v0.1.0 target is an Intel NUC, so this release covers USB serial
devices and Intel GPUs. AMD and NVIDIA GPUs wait for a later ADR.

| Device class | DRA driver | Device plugin | Picked |
|---|---|---|---|
| USB serial radio | None released. `kubernetes-sigs/dra-example-driver` is a sample. | `generic-device-plugin`. Akri `v0.14.0` discovers udev devices through its own agent, controller, and CRDs. | `generic-device-plugin` |
| Intel GPU (transcode, decode) | `intel-resource-drivers-for-kubernetes` `gpu-v0.12.1`, for Kubernetes 1.36 and later. Its README says "beta / non-production". | Intel's GPU device plugin `v0.37.1`. `generic-device-plugin` on `/dev/dri/renderD*`. | Intel's GPU device plugin |

A DRA claim shares one device between pods only through one `ResourceClaim`,
and a claim lives in one namespace. Jellyfin, Immich, and Frigate run in
their own namespaces and share one integrated GPU on a typical home node. A
device plugin with a share count shares the device across namespaces with
one `resources.limits` line in each pod. No released DRA driver covers the
USB serial class at all. This release therefore uses device plugins for
every class.

## Decision

### 1. Node labels

NFD sets these labels from `NodeFeatureRule` objects that `core` ships. The
value of each label is `"true"`. The labels use NFD's own namespace,
`feature.node.kubernetes.io`, so no Windsor name is on a node. No other label
is part of the contract. The built-in NFD labels stay at their defaults.

| Label | Device class | Rule |
|---|---|---|
| `feature.node.kubernetes.io/usb-serial` | USB serial radio | `kernel.loadedmodule` has one of `cdc_acm`, `ch341`, `cp210x`, `ftdi_sio`, `pl2303` |
| `feature.node.kubernetes.io/gpu-intel` | Transcoding GPU | `pci.device` with `vendor: 8086` and `class` `0300` or `0380`, and `kernel.loadedmodule` has `i915` or `xe` |
| `feature.node.kubernetes.io/video-encode` | Transcoding GPU | The `gpu-intel` rule matches |
| `feature.node.kubernetes.io/video-decode` | Video decoder | The `gpu-intel` rule matches |

A GPU rule requires the kernel module, so a node gets a GPU label only when
the matching extension from section 4 is installed. A GPU without its
extension gets no label and no resource.

`video-encode` and `video-decode` select by capability, so a `home` facet
does not list vendors. Both labels come from the Intel rule in this release,
because the media engine of a GPU does both. A rule for another GPU vendor
sets the same two labels. A later rule MAY set
`video-decode` alone for a decoder that is not a GPU, with no change to the
key.

The `usb-serial` rule reads loaded modules, because NFD does not read the USB
product string and the common bridge chips (`10c4:ea60`, `1a86:55d4`) carry
both Zigbee and Z-Wave radios. Talos udev loads the driver when the dongle is
plugged in. The label stays after an unplug until the node reboots. The
device type is in the resource name the user picks (section 2), not in the
label. The
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
| `devices.windsorcli.dev/<name>` | USB serial device, one per `devices.serial` key | `/dev/serial/by-id/` globs | `/dev/<name>` | 1 |
| `gpu.intel.com/i915` or `gpu.intel.com/xe` | Intel GPU, by kernel driver | Intel's GPU device plugin | The card and render nodes under `/dev/dri/` | 10 |

`core` ships no default globs and no default serial names. A by-id name
carries a product string that `core` cannot check for every dongle, one
product can run more than one protocol depending on its firmware, and a
dongle can name only its bridge chip (for example
`usb-Silicon_Labs_CP2102N_USB_to_UART_Bridge_Controller_<serial>`). The user
reads `/dev/serial/by-id/` on the node and writes the globs (section 5). The
implementation MUST confirm that the plugin mounts a by-id symlink as a
device node.

The Intel resource name depends on the GPU generation. A `home` facet MUST
request the name that matches the node's kernel driver. A values key that
picks the name is left to `home`.

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
  devices.windsorcli.dev` and one device per `devices.serial` key. The
  plugin installs only when `devices.serial` has a key.
- `intel-gpu-plugin`, Intel's upstream DaemonSet vendored through
  `kustomize/crds/sources.yaml`, with `-shared-dev-num=10` and a
  `nodeSelector` on `feature.node.kubernetes.io/gpu-intel`. It installs only
  when `intel` is in `devices.gpu.drivers`. Its operator and Helm chart are
  not used.

The `install` tier holds the device plugins and the NFD release. The
`resources` tier holds the `NodeFeatureRule` objects, because they need the
CRD. Each Helm source gets the `chart-registry` component, like the other
systems. The DaemonSets run as `system-*` Pods under the Kyverno baseline
policies.

### 4. Talos extensions and machine config

`config-talos.yaml` adds a catalog next to `csi_extensions`:

| `devices.gpu.drivers` entry | Extensions |
|---|---|
| `intel` | `siderolabs/i915`, `siderolabs/xe` |

`talos_common.extensions` MUST be the union of the CSI entry and the device
entries. The `cluster-extensions` step and its `gitops` dependency MUST run
when that list is not empty, not only when the storage driver needs an
extension.

When `devices.enabled` is true, every node gets the containerd CRI patch from
section 2. Extensions apply to every node in this release. Talos loads `i915`
and `xe` only on matching hardware. Extensions for one pool only wait for a
later change to ADR-0026.

### 5. Values

```yaml
devices:
  enabled: true          # NFD and the CRI patch
  gpu:
    drivers: [intel]     # intel
  serial:
    zigbee: ["*Sonoff_Zigbee*"]   # resource devices.windsorcli.dev/zigbee
```

- `devices.enabled` defaults to `false`. It installs the `devices` system and
  the CRI patch.
- `devices.gpu.drivers` defaults to `[]`. Each entry adds its extensions,
  and its device plugin. A non-empty list with
  `devices.enabled: false` MUST fail composition with the message
  "devices.gpu.drivers needs devices.enabled: true".
- `devices.serial` defaults to `{}`. Each key is a DNS label that names the
  resource and the container path, and its value is a non-empty list of
  globs under `/dev/serial/by-id/`.
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
  with an Intel integrated GPU and one USB Zigbee dongle, configured as
  `devices.serial.zigbee`. The run shows the
  `usb-serial`, `gpu-intel`, `video-encode`, and `video-decode` labels, the
  `devices.windsorcli.dev/zigbee` resource and the Intel GPU resource, a
  non-root pod that opens `/dev/zigbee`, and two pods in different
  namespaces that each run `vainfo` on `/dev/dri/renderD128` at the same
  time.
- Incus passthrough and Proxmox passthrough ship without a live run. Their
  schema descriptions MUST say that they are untested.

### 10. Path to DRA

DRA is the target for device allocation. A class moves from its device
plugin to a DRA driver only when all of these hold:

1. A released DRA driver covers the class and runs on the Talos version that
   `core` pins.
2. The driver shares one device between pods in different namespaces, through
   consumable capacity (KEP-5075) or an equal mechanism.
3. A pod keeps the resource names from section 2 in `resources.limits`,
   through extended resources backed by DRA (KEP-5004), or the move ADR gives
   `home` a migration.

Intel moves when its DRA driver drops the beta notice. The serial class waits
for a DRA driver for host devices. The labels from section 1 stay the same
after any move.

## Consequences

- A `home` facet requests a resource and sets a `nodeSelector` default from
  section 1. It needs no `hostPath` or privileged Pod, which closes that open
  point of `home` v0.1.0.
- The labels and resource names are a contract. Moving a class to DRA later
  changes how a pod asks for the device, so that ADR MUST keep the labels and
  give `home` a migration for the resource.
- `generic-device-plugin` is one maintainer's project. It covers only the
  serial class, which no vendor plugin covers.
- A `home` facet branches on the Intel kernel driver for its GPU resource.
- The device extensions add one installer upgrade and reboot per node, the
  same cost as the storage extensions.

## Alternatives considered

- DRA for every class. No DRA driver covers USB serial devices. The Intel
  GPU driver is beta. A claim shares a device inside one namespace only, and
  every `home` app would need a `ResourceClaimTemplate`.
- `generic-device-plugin` on `/dev/dri/renderD*` as one `dri` resource for
  every GPU vendor. One name would spare `home` the `i915` and `xe` branch,
  but it puts the GPU path on one maintainer's project when Intel maintains
  its own plugin.
- Intel's GPU plugin through its operator and Helm chart. The operator adds
  CRDs and a controller that one DaemonSet does not need.
- AMD and NVIDIA GPUs in this release. The `home` v0.1.0 target has neither,
  so no live run could cover them.
- Akri for the serial class. It needs a controller, an agent, and CRDs, its
  resource names are `akri.sh/<configuration>`, and it mounts the device at
  its host path, such as `/dev/ttyACM0`, which can change between boots.
  Home Assistant takes a fixed device path in its configuration.
- Default serial names and product globs in `core`, such as `zigbee` and
  `zwave`. The globs cannot be checked for every product, a radio's protocol
  can depend on its firmware, and each new device class would need a schema
  change.
- Radio labels from a USB vendor and device list. Zigbee and Z-Wave sticks
  share bridge chips, so the list cannot tell them apart.
- Resources under `feature.node.kubernetes.io` like the labels. Kubernetes
  rejects extended resource names in `kubernetes.io` domains.
- Resources under the plugin's default domain `squat.ai`. It ties the
  contract to the plugin author's domain, so the resources keep
  `devices.windsorcli.dev`.
- One label with the GPU vendor as its value. A node with an integrated GPU
  and a discrete GPU needs two values.

## References

- [Node Feature Discovery customization guide](https://kubernetes-sigs.github.io/node-feature-discovery/master/usage/customization-guide.html)
- [nfd-master command line reference](https://kubernetes-sigs.github.io/node-feature-discovery/master/reference/master-commandline-reference.html)
- [squat/generic-device-plugin](https://github.com/squat/generic-device-plugin)
- [Talos device plugins guide](https://docs.siderolabs.com/kubernetes-guides/advanced-guides/device-plugins)
- [siderolabs/extensions](https://github.com/siderolabs/extensions)
- [Intel GPU resource driver](https://github.com/intel/intel-resource-drivers-for-kubernetes/blob/main/doc/gpu/README.md)
- [Intel GPU device plugin](https://github.com/intel/intel-device-plugins-for-kubernetes/blob/main/cmd/gpu_plugin/README.md)
