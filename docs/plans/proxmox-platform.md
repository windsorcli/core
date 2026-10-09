# Proxmox VE platform support

`platform: proxmox` runs Talos clusters as VMs on a Proxmox VE node, the
same way `hyperv` and `vsphere` do on their hypervisors. This plan maps the
platform against the Hyper-V and vSphere precedent, records the decisions
taken, and lists the phases that deliver it.

## Precedent map

Every on-premises VM platform is a compute module, a platform facet, and a
schema block. `cluster/talos`, `gitops/flux`, and the Flux systems are
shared.

| Layer | Hyper-V | vSphere | Proxmox |
|---|---|---|---|
| Terraform provider | `windsorcli/hyperv` (Windsor-owned) | `vmware/vsphere` | `bpg/proxmox` |
| Compute module | `compute/hyperv` | `compute/vsphere` | `compute/proxmox` |
| Talos image | `metal-amd64.iso` + nocloud kernel arg | `vmware-amd64.ova` | `nocloud-<arch>.qcow2` |
| Guest agent extension | `hyperv-guest-agent` | `vmtoolsd-guest-agent` | `qemu-guest-agent` |
| Network config delivery | CIDATA seed ISO | guestinfo | Proxmox cloud-init drive |
| Machineconfig delivery | baked into CIDATA by compute | baked into guestinfo by compute | applied by `cluster/talos` over the maintenance-mode API |
| Cluster identity | minted in compute | minted in compute | minted in `cluster/talos` |
| Credentials | `HYPERV_*` env | `VSPHERE_*` env | `PROXMOX_VE_*` env |
| Schema block | `hyperv` | `vsphere` | `proxmox` |
| State backend | `kubernetes` | `kubernetes` | `kubernetes` |

## Decisions

Each decision below is taken. Each changes a module boundary, not just an
input.

**Provider: `bpg/proxmox`, pinned `~> 0.116`.** It covers everything Talos
needs over the Proxmox API alone. `proxmox_download_file` pulls an image
through the PVE `download-url` API. `disk.import_from` imports it as a VM
disk. `initialization` writes a nocloud cloud-init drive. The agent block
reports guest addresses. Telmate's provider has no disk import and no
download-url resource, and its v3 line is still release candidates. A
Windsor-owned provider, as for Hyper-V, would cost tens of thousands of
lines with nothing gained here. The provider is renaming
`proxmox_virtual_environment_*` resources to `proxmox_*` before v1.0, so
the module uses `proxmox_download_file` already and keeps the SDK-based
`proxmox_virtual_environment_vm` until v1.0 ships a production
replacement.

**Machineconfig delivery: applied over the Talos API.** The VM boots the
nocloud image with a static address from the Proxmox cloud-init drive and
waits in maintenance mode. `cluster/talos` generates the cluster identity
and applies each node's config, the path `metal` and `hetzner` already
use. Baking the config into cloud-init user-data, as Hyper-V and vSphere
do, needs snippet uploads, which the Proxmox API doesn't offer. That would
add SSH access and a snippets datastore to the operator's prerequisites.

**Static addressing by default.** Node addresses come from
`cluster.*.nodes` or `cidrhost` offsets 10 and 20, matching vSphere.
`compute/proxmox` also emits each static address as a machineconfig patch
in its `controlplanes` and `workers` outputs, so the apply keeps it.
`network.dhcp: true` switches to DHCP leases reported by qemu-guest-agent,
which runs in maintenance mode.

**Upgrades keep the platform image.** `machine.install.image` is
`factory.talos.dev/nocloud-installer/<schematic>:v<talos_version>`. The
platform-specific installer keeps both the qemu-guest-agent extension and
the nocloud platform across upgrades.

**Credentials are env-only.** The provider reads `PROXMOX_VE_ENDPOINT`,
`PROXMOX_VE_API_TOKEN`, and `PROXMOX_VE_INSECURE`. Operators set them in
the context's `environment:` block, with the token from a secret
reference or the context `.env` file, as for Hyper-V. The CLI gets no
typed `proxmox` block and no env printer.

**CNI: Cilium.** The platform-base default stays, as on vSphere. A flat
Proxmox bridge supports L2 load-balancer announcements. Flannel with
kube-vip stays a `cluster.cni.driver` override. DHCP with Cilium requires
`cluster.endpoint`, since kube-proxy replacement needs the API address at
render time.

**Scope: one node, local storage.** `proxmox.node` names a single node,
like vSphere's `host_system`. Storage stays on the Talos default
(OpenEBS). Multi-node placement, shared storage, a control-plane VIP, and
the Proxmox CSI plugin are follow-ups.

**Architectures: amd64 and arm64.** amd64 is the default. `proxmox.arch:
arm64` selects the `nocloud-arm64` image, the `virt` machine, OVMF
firmware, the `host` CPU type, and a SCSI cloud-init drive, for Proxmox VE
on arm64 hosts.

## Host prerequisites

Windsor doesn't manage the Proxmox node itself. The operator prepares it
once:

- Proxmox VE 8.4 or later, for the `import` content type. 9.x is the
  target.
- An image datastore with `import` enabled:
  `pvesm set local --content iso,vztmpl,backup,import`.
- A Linux bridge (`vmbr0` by default) on the LAN that `network.cidr_block`
  describes, with free addresses for the nodes and the load-balancer pool.
- Outbound HTTPS from the node to `factory.talos.dev`.
- An API token. The starting privilege set, to confirm on a live host, is
  `VM.Allocate`, `VM.Config.*`, `VM.PowerMgmt`, `VM.Audit`,
  `VM.GuestAgent.Audit` (`VM.Monitor` on 8.x), `Datastore.AllocateSpace`,
  `Datastore.AllocateTemplate`, `Datastore.Audit`, `Sys.Audit`,
  `Sys.Modify`, and `SDN.Use`.

The Talos schematic is `ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515`,
which holds `siderolabs/qemu-guest-agent` only. Recompute it when the
extension list changes:

```bash
curl -sX POST -H 'Content-Type: application/yaml' \
  -d $'customization:\n  systemExtensions:\n    officialExtensions:\n      - siderolabs/qemu-guest-agent\n' \
  https://factory.talos.dev/schematics
```

## New pieces, by directory

```
terraform/compute/proxmox/                   Talos VMs, image download, cloud-init
contexts/_template/facets/platform-proxmox.yaml
contexts/_template/tests/platform-proxmox.test.yaml
contexts/_template/schema.yaml               platform enum + proxmox block
docs/plans/proxmox-platform.md               this plan
```

Outside this repo:

```
windsor-cli      platform enum, cluster.driver and backend defaults, --platform help
windsor-action   proxmox in the cloud-auth and kubeconfig no-op lists
windsor-docs     content/virtual/proxmox.md and cross-links
```

The CLI intersects its built-in platform enum with this blueprint's, so
`platform: proxmox` fails validation until the CLI lists it. Core CI
installs the CLI from `main`, so the CLI change merges first.

## Phase order

1. **CLI.** `proxmox` in the CLI platform enum, the talos driver default,
   and the kubernetes backend default.
2. **Compute module.** `compute/proxmox` with mock-provider tests. No
   dependency on the CLI.
3. **Facet and schema.** `platform-proxmox.yaml`, its tests, and the
   `proxmox` schema block, wiring compute, cluster, and gitops. Needs
   phase 1 on the CLI's `main`.
4. **Local lab.** A single-node cluster on an arm64 Proxmox VE in a nested
   Lima VM (see below).
5. **CI action and docs.** windsor-action no-op lists, the windsor-docs
   page, and the site nav.
6. **Real host.** amd64 validation on an operator's Proxmox VE node.

## Local lab

Docker-hosted Proxmox VE and API simulators can't boot VMs, so they test
little beyond request formats. Apple Silicon M3 or later on macOS 15 or
later supports nested virtualization, and Proxmox VE publishes arm64
packages, so a real lab fits on a Mac:

1. `limactl create --name pve --vm-type vz --set '.nestedVirtualization=true' --cpus 8 --memory 24 --disk 120 template://debian-13`,
   then `limactl start pve`. Check that `/dev/kvm` exists in the guest.
2. In the guest, add `deb http://download.proxmox.com/debian/pve trixie
   pve-no-subscription`, install `proxmox-ve`, and create `vmbr0` on a
   private subnet with NAT to the uplink.
3. Enable `import` on `local` and create a token with
   `pveum user token add root@pam windsor --privsep 0`.
4. Run Windsor inside the guest, so the Talos VMs on `vmbr0` are directly
   reachable. Use `platform: proxmox`, `proxmox.arch: arm64`, a `/24` on
   `vmbr0`, an explicit `network.loadbalancer_ips` pool, and the
   `PROXMOX_VE_*` variables pointing at `https://127.0.0.1:8006/`.
5. `windsor up --wait`, check that the nodes come up at their static
   addresses and Flux reconciles, then `windsor destroy`.

The lab covers the Proxmox API, image download and import, cloud-init
networking, the guest agent, the Talos apply, and bootstrap. It doesn't
cover amd64 firmware and CPU types, multi-node Proxmox clusters, shared
storage, or production VLANs. The real-host phase covers those.

## Real-host validation

1. Record `pveversion` and confirm the prerequisites above.
2. Run `windsor plan` on a throwaway context and read it before applying.
3. Apply a single control plane, then three control planes and a worker.
4. Exercise `network.dhcp: true`, then `windsor destroy`.
5. Upgrade one node with `windsor upgrade node` and the nocloud installer
   image. Confirm the guest agent and the static address survive.

## What this plan doesn't cover

Multi-node Proxmox clusters with per-instance placement, shared or Ceph
storage, the Proxmox CSI plugin and cloud controller manager, a
control-plane VIP, and Proxmox SDN. Each is its own follow-on scope once
a single-node cluster runs.

## Known gaps

`talos_version` changes drift silently on Proxmox, as they do on vSphere
and Hyper-V. `disk.import_from` is read only at VM creation, so a new
version reaches the machineconfig but not the installed OS. Nodes upgrade
through `windsor upgrade node`.

`platform-base.yaml` defaults `network.loadbalancer_ips` to `cidrhost`
offsets 266 to 356. On a `/24` network that fails composition unless the
operator sets the pool, which most Proxmox LANs need. A prefix-aware
default in platform-base would fix every LAN platform at once.

`cluster/talos/extensions` builds its upgrade schematic from the CSI
extensions only and upgrades to the generic installer. With Longhorn or
Mayastor, that upgrade likely drops `qemu-guest-agent` and the nocloud
installer on Proxmox, and the matching agents on Hyper-V and vSphere. The
fix is a per-platform extension list and installer flavour in that
module.

The windsor-docs vSphere page puts `vsphere.server` and `vsphere.user` in
values, which this schema's `vsphere` block rejects. Proxmox avoids the
same trap by keeping connection settings env-only.

The bpg provider removes `proxmox_virtual_environment_vm` at v1.0. The
module then needs a `moved` block to the replacement resource.
