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
- An API token whose role on `/` holds `Datastore.Allocate`,
  `Datastore.AllocateSpace`, `Datastore.AllocateTemplate`, `Sys.Audit`,
  `Sys.Modify`, `SDN.Use`, `VM.Allocate`, `VM.Audit`, `VM.PowerMgmt`,
  `VM.GuestAgent.Audit`, `VM.Config.CPU`, `VM.Config.Disk`,
  `VM.Config.HWType`, `VM.Config.Memory`, `VM.Config.Network`, and
  `VM.Config.Options`. The lab verified this set on Proxmox VE 9.2. On
  8.x, `VM.Monitor` replaces `VM.GuestAgent.Audit`.

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
packages, so a real lab fits on a Mac. The lab below ran on Apple silicon
with Lima 2.2.1 and Proxmox VE 9.2.10.

1. Create and start the VM:
   `limactl create --name pve --vm-type vz --set '.nestedVirtualization=true' --cpus 8 --memory 16 --disk 80 template:debian-13`,
   then `limactl start pve`. Check that `/dev/kvm` exists in the guest.
2. In the guest, set `manage_etc_hosts: false` for cloud-init and map the
   hostname to the bridge address (`10.10.0.1 lima-pve`) in `/etc/hosts`.
   Add the `pve-no-subscription` repository for `trixie` with
   `proxmox-archive-keyring-trixie.gpg`, then
   `apt install proxmox-ve postfix open-iscsi chrony`.
3. Keep booting the Debian cloud kernel, which exposes `/dev/kvm` under
   Apple's hypervisor:
   `grub-set-default "Advanced options for Proxmox VE GNU/Linux>Proxmox VE GNU/Linux, with Linux $(uname -r)"`.
4. Leave `eth0` to netplan so Lima keeps its uplink. Define only `vmbr0`
   in `/etc/network/interfaces` (`address 10.10.0.1/24`,
   `bridge-ports none`, and a `MASQUERADE` rule for `10.10.0.0/24` out
   `eth0` in `post-up`), set `net.ipv4.ip_forward = 1`, then
   `mkdir -p /run/network && systemctl start networking`.
5. `pvesm set local --content iso,vztmpl,backup,import,images,snippets`.
   The lab has no LVM thin pool, so `proxmox.datastore: local`.
6. Create the role, user, and token from the host prerequisites above.
7. Clone the blueprint into the guest and serve it to Flux over git smart
   HTTP on `10.10.0.1`, for example with `git http-backend` behind a small
   HTTP server. Point the context at it in `contexts/<ctx>/blueprint.yaml`
   with `repository.url` and `repository.ref.branch`, so nothing is pushed.
8. Run Windsor inside the guest, where the Talos VMs on `vmbr0` are
   directly reachable. The context sets `platform: proxmox`,
   `proxmox.node: lima-pve`, `proxmox.arch: arm64`,
   `proxmox.datastore: local`, `network.cidr_block: 10.10.0.0/24`,
   `network.gateway: 10.10.0.1`, an explicit `network.loadbalancer_ips`
   pool, and one control plane with 6 CPUs and 12 GiB. The context `.env`
   holds `PROXMOX_VE_ENDPOINT=https://127.0.0.1:8006/`,
   `PROXMOX_VE_INSECURE=true`, and `PROXMOX_VE_API_TOKEN`.
9. Set `policies.enabled: false` and `gateway.enabled: false`, which the
   nested node can't carry. Then `windsor bootstrap <ctx> --yes`, check
   the node and Flux, and `windsor destroy --confirm=<ctx>`.

Stop the lab with `limactl stop pve` and restart it with
`limactl start pve`. After a restart, run
`sudo mkdir -p /run/network && sudo systemctl restart networking` in the
guest if `vmbr0` is missing. Delete it with `limactl delete pve`.

### What the lab proved

Every step ran with the restricted token, not `root@pam`.

- **Plan.** The `compute/proxmox` plan shows one `proxmox_download_file`
  and one VM with the `virt` machine, OVMF, the `host` CPU, a SCSI
  cloud-init drive, and `10.10.0.10/24` on `vmbr0`.
- **Image import.** `download-url` landed
  `local:import/talos-v1.14.2-ce4c9805-arm64-<id>.qcow2` in 18 seconds,
  and the VM imported it as `scsi0`.
- **Boot and static IP.** Talos booted the nocloud image into
  maintenance mode at `10.10.0.10/24` with the gateway route from the
  Proxmox cloud-init drive. Talos reports `platform: nocloud`, the
  `qemu-guest-agent` extension, and schematic `ce4c9805`. Proxmox's
  guest agent query returns the same address on `eth0`.
- **Talos apply and bootstrap.** `cluster/talos` applied the config over
  the maintenance API and bootstrapped etcd. The applied config holds the
  per-node static address patch and
  `install.image: factory.talos.dev/nocloud-installer/ce4c9805…:v1.14.2`.
- **Node and Flux.** The node reached `Ready` on Kubernetes v1.37.1.
  Flux pulled the blueprint from the lab git server, and the cilium,
  openebs, kyverno, and metrics-server HelmReleases reconciled. With
  `policies.enabled: false` and `gateway.enabled: false`,
  `windsor apply --wait` brought all 11 kustomizations and every
  HelmRelease to Ready, and an OpenEBS volume bound and took writes.
- **Idempotence.** `windsor plan` on the running cluster reports no
  changes for `compute/proxmox`, `cluster/talos`, `cni/cilium`, and
  `gitops/flux`.
- **Destroy.** `windsor destroy` removed the kustomizations, the cluster,
  the VM with its disks, and the downloaded image in one pass. The node
  had no VMs and no `images` or `import` volumes afterwards. An earlier
  token without `Datastore.Allocate` left the image behind with a 403.
- **DHCP.** With a dnsmasq pool on `vmbr0` and no `ipv4`, the module
  waited for the guest agent and emitted the leased address in
  `controlplanes`, with an empty `config_patches`.
- **Privileges.** Dropping each privilege in turn and running apply,
  agent read, plan, and destroy showed that every privilege in the set
  above is required. `Datastore.Audit`, `VM.Config.CDROM`, and
  `VM.Config.Cloudinit` were not needed to create, refresh, or destroy.
  `VM.GuestAgent.Audit` is needed only by DHCP instances.

### What the lab can't cover

- amd64 specifics: SeaBIOS, the `q35` machine, the `x86-64-v2-AES` CPU
  type, the IDE cloud-init drive, and the `nocloud-amd64` image.
- Multi-node Proxmox clusters, shared or Ceph storage, and LVM-thin
  `local-lvm` disks.
- Tagged VLANs on a trunk to a real switch, and a LAN DHCP server.
- Performance and the full stack. Nested arm64 virtualization starves
  the Talos node for CPU. With Kyverno enabled, API requests time out and
  the stack never converges, so the lab ran without policy and gateway.
- Upgrades through `windsor upgrade node`, and three control planes.

## Real-host validation

Run this on the operator's amd64 Proxmox VE node with a throwaway
context. Use addresses on the node's LAN that nothing else holds.

1. On the node, record `pveversion`. For Proxmox VE before 8.4, stop: the
   `import` content type is missing.
2. `pvesm status` and `pvesm config <image datastore>`. Enable `import`
   on the image datastore. If the VM datastore is a directory store,
   enable `images` on it too.
3. `curl -sSI https://factory.talos.dev` from the node gets an HTTP response.
4. Create the role, user, and token from the host prerequisites. On 8.x
   swap `VM.GuestAgent.Audit` for `VM.Monitor`.
5. Reserve the control-plane address (`cidrhost` offset 10), worker
   addresses (offset 20 and up), and a load-balancer pool, all on the
   bridge's LAN.
6. Use a windsor CLI release that includes the proxmox platform.
7. `windsor init <ctx> --platform proxmox`, then set `proxmox.node`,
   `proxmox.bridge`, `proxmox.datastore`, `network.cidr_block`,
   `network.gateway`, `network.nameservers`, `network.loadbalancer_ips`,
   and `cluster.controlplanes.count: 1`. Put the `PROXMOX_VE_*` variables
   in the context `.env`. Set `repository.url` in
   `contexts/<ctx>/blueprint.yaml` to a git remote the cluster can reach.
8. `windsor plan terraform compute` with `terraform.backend.type: local`
   set for that run only, and read the plan: `q35`, `seabios`,
   `x86-64-v2-AES`, `ide2` cloud-init, the static address, and the
   `nocloud-amd64.qcow2` URL. Restore `type: kubernetes` afterwards.
9. `windsor bootstrap <ctx> --yes`. Verify with
   `talosctl -n <ip> get addresses`, `talosctl -n <ip> get extensions`,
   `qm agent <vmid> network-get-interfaces`, `kubectl get nodes`, and
   `flux get kustomizations -A`.
10. `windsor plan` reports no changes for every Terraform component.
11. `windsor destroy --confirm=<ctx>`, then confirm `qm list` and
    `pvesm list <image datastore> --content import` hold nothing from the
    context.
12. Repeat with `cluster.controlplanes.count: 3` and
    `cluster.workers.count: 1`, then with `network.dhcp: true` and a set
    `cluster.endpoint`.
13. Upgrade one node with `windsor upgrade node` to the next Talos patch.
    Confirm the node keeps its static address, `qemu-guest-agent`, and
    `platform: nocloud`.

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

`windsor plan` on a context that has never been bootstrapped fails to
initialize the `kubernetes` state backend, because the cluster that
holds it doesn't exist yet. This affects every platform with that
backend. Plan a fresh context with `terraform.backend.type: local` set
for that run only.

Turning telemetry off breaks Cilium platforms, Proxmox included. With
`telemetry.metrics.enabled: false`, the `cilium/hubble` component still
enables the Hubble `ServiceMonitor`, but the prometheus-operator CRDs are
not installed, so `cni-install` fails. With `telemetry.logs.enabled:
false`, `option-cni.yaml` still adds the Cilium Grafana dashboards to
`observability-resources`, whose `system-observability` namespace then
never exists.
