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
`PROXMOX_VE_INSECURE`, and either `PROXMOX_VE_USERNAME` with
`PROXMOX_VE_PASSWORD` or `PROXMOX_VE_API_TOKEN`. Operators set them in
the context's `environment:` block, with the password or token from a
secret reference or the context `.env` file, as for Hyper-V. The CLI
gets no typed `proxmox` block and no env printer.

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
- An image datastore with `import` enabled. On a node with other
  guests, a dedicated one:
  `pvesm add dir windsor-images --path /var/lib/windsor-images --content import`.
- A Linux bridge (`vmbr0` by default) on the LAN that `network.cidr_block`
  describes, with free addresses for the nodes and the load-balancer pool.
- Outbound HTTPS from the node to `factory.talos.dev`.
- A resource pool and a Proxmox user whose roles are scoped to that pool,
  the two datastores, the bridge, and `Sys.AccessNetwork` on the node.
  [Using a shared Proxmox host safely](#using-a-shared-proxmox-host-safely)
  lists the commands.

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
6. Create the pool, image datastore, roles, and user from
   [Using a shared Proxmox host safely](#using-a-shared-proxmox-host-safely).
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
   holds `PROXMOX_VE_ENDPOINT=https://127.0.0.1:8006/` and
   `PROXMOX_VE_INSECURE=true`, and the shell exports
   `PROXMOX_VE_USERNAME` and `PROXMOX_VE_PASSWORD`.
9. Set `policies.enabled: false` and `gateway.enabled: false`, which the
   nested node can't carry. Then `windsor bootstrap <ctx> --yes`, check
   the node and Flux, and `windsor destroy --confirm=<ctx>`.

Stop the lab with `limactl stop pve` and restart it with
`limactl start pve`. After a restart, run
`sudo mkdir -p /run/network && sudo systemctl restart networking` in the
guest if `vmbr0` is missing. Delete it with `limactl delete pve`.

### What the lab proved

The first lab run used a token with a role on `/`, not `root@pam`.
[What the shared-host lab proved](#what-the-shared-host-lab-proved)
covers the pool-scoped user.

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
- **Privileges.** Dropping each privilege in turn from that role on `/`
  and running apply, agent read, plan, and destroy showed which ones
  Windsor needs. `Datastore.Audit`, `VM.Config.CDROM`, and
  `VM.Config.Cloudinit` were not needed to create, refresh, or destroy.
  `VM.GuestAgent.Audit` is needed only by DHCP instances. The scoped
  roles in [Prepare the node](#prepare-the-node) split that set by ACL
  path and replace `Sys.Audit` and `Sys.Modify` with `Sys.AccessNetwork`.

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
4. Follow [Using a shared Proxmox host safely](#using-a-shared-proxmox-host-safely)
   for the pool, image datastore, user, roles, VM ID range, and addresses.
5. Reserve the control-plane address (`cidrhost` offset 10), worker
   addresses (offset 20 and up), and a load-balancer pool, all on the
   bridge's LAN.
6. Use a windsor CLI release that includes the proxmox platform.
7. `windsor init <ctx> --platform proxmox`, then set `proxmox.node`,
   `proxmox.bridge`, `proxmox.datastore`, `proxmox.image_datastore`,
   `proxmox.pool`, `proxmox.vm_id_start`, `network.cidr_block`,
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

## Using a shared Proxmox host safely

A Windsor run on a node that already holds other guests creates only its
own VMs and one image file, and destroy removes only what the
`compute/proxmox` state holds. Three guards in the module back this up,
and a pool-scoped Proxmox user enforces it on the node:

- The image file name carries the Talos version, schematic, architecture,
  and context id, e.g. `talos-v1.14.2-ce4c9805-amd64-<id>.qcow2`. When a
  file with that name already exists, the download fails with "File
  already exists in the datastore" instead of adopting or replacing it.
- With `proxmox.vm_id_start` set, `compute/proxmox` lists the guests the
  user can see and fails the plan when one of them holds a planned ID
  under another name. A pool-scoped user sees only the pool, so the
  `/cluster/nextid` check below covers the other guests. Without
  `vm_id_start`, Proxmox hands out the next free ID.
- Destroy deletes each VM with the disks it references and leaves any
  unreferenced `vm-<id>-disk-*` volumes alone.
- The user has no rights on `/`. It cannot see, stop, change, or delete
  guests outside the Windsor pool, or files outside Windsor's image
  datastore, and every such call returns 403.

### Prepare the node

Run these once as `root` on the node. Replace `pve`, `local-lvm`, and
`vmbr0` with the node name, VM datastore, and bridge Windsor will use.

```bash
pveum pool add windsor --comment "Windsor-managed VMs"
mkdir -p /var/lib/windsor-images
pvesm add dir windsor-images --path /var/lib/windsor-images --content import

pveum role add WindsorVM --privs "Pool.Audit,VM.Allocate,VM.Audit,VM.PowerMgmt,VM.Config.CPU,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options"
pveum role add WindsorDisk --privs "Datastore.AllocateSpace,Datastore.Audit"
pveum role add WindsorImage --privs "Datastore.Allocate,Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit"
pveum role add WindsorNet --privs "SDN.Use"
pveum role add WindsorNode --privs "Sys.AccessNetwork"

pveum user add windsor@pve --comment "Windsor provisioner"
pveum passwd windsor@pve

pveum acl modify /pool/windsor --users windsor@pve --roles WindsorVM
pveum acl modify /storage/local-lvm --users windsor@pve --roles WindsorDisk
pveum acl modify /storage/windsor-images --users windsor@pve --roles WindsorImage
pveum acl modify /sdn/zones/localnetwork/vmbr0 --users windsor@pve --roles WindsorNet
pveum acl modify /nodes/pve --users windsor@pve --roles WindsorNode
```

| ACL path | Role | Why |
|----------|------|-----|
| `/pool/windsor` | `WindsorVM` | Create VMs into the pool, read its membership, then configure, power, and delete them |
| `/storage/<VM datastore>` | `WindsorDisk` | Allocate VM, EFI, and cloud-init disks, without deleting other volumes |
| `/storage/windsor-images` | `WindsorImage` | Download the Talos image and delete it on destroy |
| `/sdn/zones/localnetwork/<bridge>` | `WindsorNet` | Attach NICs to the bridge |
| `/nodes/<node>` | `WindsorNode` | Query and download the image URL |

The roles are the same on Proxmox VE 8.4 and 9.x. Two additions apply
only in some setups:

- `network.dhcp: true` reads leases through the guest agent. Add
  `VM.GuestAgent.Audit` to `WindsorVM` on 9.x, or `VM.Monitor` on 8.4.
- `proxmox.vlan_id` needs `SDN.Use` on
  `/sdn/zones/localnetwork/<bridge>/<vlan_id>` as well.

`Datastore.Allocate` on `windsor-images` lets the user delete any file
there, so keep that datastore for Windsor alone. On the VM datastore the
user holds only `Datastore.AllocateSpace` and `Datastore.Audit`, so it
cannot delete other guests' disks, ISOs, or backups.

Authenticate with the password:

```bash
PROXMOX_VE_ENDPOINT=https://<node address>:8006/
PROXMOX_VE_USERNAME=windsor@pve
PROXMOX_VE_PASSWORD=<password>
PROXMOX_VE_INSECURE=true
```

To use an API token instead, create one that inherits the user's ACLs
and set `PROXMOX_VE_API_TOKEN=windsor@pve!terraform=<secret>` in place of
the username and password:

```bash
pveum user token add windsor@pve terraform --privsep 0
```

### Choose a VM ID range and addresses

`proxmox.vm_id_start` pins Windsor's VM IDs. Control plane N takes
`vm_id_start + N - 1` and worker N takes `vm_id_start + 9 + N`, so a
start of 10000 gives control planes 10000 to 10002 and workers from
10010. Pick a start whose next 20 IDs are free on the whole cluster.
`/cluster/nextid` checks every guest, including ones the Windsor user
can't see, and prints the ID back when it's free:

```bash
for id in $(seq 10000 10019); do pvesh get /cluster/nextid --vmid "$id" || echo "taken: $id"; done
pvesm list local-lvm | grep -E 'vm-100[0-1][0-9]-' || echo "no leftover disks"
```

Leaving `vm_id_start` unset lets Proxmox hand out the lowest free ID,
which never collides but mixes Windsor's VMs in with the rest.

Node addresses come from `cluster.*.nodes`, or `cidrhost` offsets 10 and
up for control planes and 20 and up for workers. `network.loadbalancer_ips`
needs its own free range. Before choosing them, check that nothing
answers and nothing is configured there:

```bash
grep -h '^ipconfig' /etc/pve/qemu-server/*.conf /etc/pve/lxc/*.conf 2>/dev/null
ip neigh show dev vmbr0
ping -c1 -W1 <address>
```

Keep the node addresses and the load-balancer range outside the LAN's
DHCP pool.

### Read the plan before applying

Plan the compute step of a fresh context with
`terraform.backend.type: local` set for that run only, then restore
`kubernetes`:

```bash
windsor plan terraform compute
```

The plan must show only creates: one `proxmox_download_file` whose
`file_name` ends in the context id and lands in `windsor-images`, and
one `proxmox_virtual_environment_vm` per node with `pool_id = "windsor"`,
the expected `vm_id`, `node_name`, datastore, bridge, and `ipv4`. Stop on
any `-` or `-/+` line, or on a plan error about a taken `vm_id`.

On a running cluster, `windsor plan` must report no changes for
`compute/proxmox`. `windsor destroy` prints a destroy plan before asking
for the context name. Its `compute/proxmox` block must list only the
image and the VMs from that state.

### What the shared-host lab proved

The lab ran Proxmox VE 9.2.10 with decoy VMs 100 (running) and 101
(stopped), decoy files on `local` (an import image and an ISO), and two
images named like Windsor's in `windsor-images`: the id-less name and
another context's name.

- **Apply, plan, and destroy as the scoped user.** With `windsor@pve`
  authenticated by password and exactly the roles above,
  `windsor bootstrap` created VM 10000 in pool `windsor` and the image
  `windsor-images:import/talos-v1.14.2-ce4c9805-arm64-<id>.qcow2`, and all
  11 kustomizations reached Ready. `windsor plan` then reported no
  changes. The destroy plan's `compute/proxmox` block listed only that
  image and VM 10000. After destroy, every decoy VM config and decoy file
  checksum matched the snapshot taken before the run.
- **Denied outside the grant.** While the cluster ran, the same user got
  403 reading, starting, stopping, reconfiguring, or deleting the decoy
  VMs. It also got 403 moving a decoy into the pool, creating a VM outside
  the pool, deleting the decoy files or a decoy VM's disk on `local`,
  downloading into `local`, editing datacenter options, adding a storage,
  and adding an ACL. A token with `--privsep 0` got the same answers.
- **Image name collision.** With a file of the planned name already in
  `windsor-images`, the apply failed with "File already exists in the
  datastore". Nothing entered state, and destroy left the file in place.
- **Pinned VM ID collision.** An admin token running the module without
  the guard, with `vm_id` set to a decoy's ID, took that VM over. It
  grew the decoy's disk to 10 GiB and started it, and destroy then deleted
  it. With the guard, the same plan failed. As the pool-scoped user, the
  takeover stopped with a 403 on the decoy's disk and left the decoy
  untouched, but the decoy's ID stayed in state until
  `terraform state rm`.
- **Picked VM IDs.** Without `vm_id_start`, Proxmox gave Windsor ID 102,
  skipping decoys 100 and 101.
- **Privileges.** `Pool.Audit` is needed, or every plan shows a `pool_id`
  change. `Sys.AccessNetwork` on the node replaces `Sys.Audit` and
  `Sys.Modify` on `/`. VM tags need `VM.Config.Options` on `/vms/<id>` at
  create time regardless of the pool, so `compute/proxmox` sets none.

Proxmox VE 8.4.1 ships pve-manager 8.4.1, qemu-server 8.3.12,
pve-storage 8.3.6, and pve-access-control 8.2.2. Their source runs the
same permission checks for each call above. `VM.Monitor` stands in for
`VM.GuestAgent.Audit` there. The lab didn't run 8.4, amd64, or LVM-thin
storage.

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

`bpg/proxmox` 0.116 adopts an existing VM when a pinned `vm_id` is
taken. Proxmox answers the create with HTTP 500, the provider retries it
as transient, and the retry treats "already exists" as success. The
provider then rewrites that VM's disks, and destroy deletes it. The
module's plan-time guard catches IDs the user can see, and the pool ACL
turns the rest into a 403. The fix belongs upstream: don't retry a 500
whose message says the VM already exists.

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
