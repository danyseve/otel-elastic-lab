# ADR-0006: Terraform API-only with a least-privilege token

- **Status:** Accepted
- **Date:** 2026-10-21

## Context

The first Terraform version provisioned the three k3s VMs over the Proxmox API **and** over SSH:
cloud-init user-data was uploaded as a *snippet* file, and the `bpg/proxmox` provider needs an SSH
connection to write snippets because the Proxmox API has no endpoint to upload them (`pvesh usage
/nodes/<node>/storage/<store>/upload` only accepts `import`, `iso` and `vztmpl`).

That design had three costs:

1. Terraform had to be run with **root SSH access** to every hypervisor, so the automation credential
   was far more powerful than the task.
2. The image datastore had to be duplicated per node (`local` is not shared) and one hypervisor also
   needed a datastore with the `snippets` content type enabled.
3. Any change in the user-data template (timezone, package list) meant an SSH round trip to each node.

## Decision

Drop SSH and snippets entirely and use only the Proxmox API:

- **No provider `ssh {}` block.** The provider runs with an API token alone.
- **Cloud-init from the provider.** `initialization.user_account` (user + public key), `ip_config` and
  `dns` generate the cloud-init drive through the API. No template file, no snippet.
- **`agent.enabled` follows `agent_enabled` (default `false`).** The guest agent is installed by
  Ansible (role `common`) on first boot; enabling it earlier breaks backups and logs warnings on
  every clone. Once Ansible has installed it, set `agent_enabled = true` and apply again to turn it
  on in the VM config.
- **Least-privilege token.** A dedicated `terraform@pve` user with a token (`privsep = 1`) holding a
  custom role scoped to a resource pool: `VM.Allocate`, `VM.Audit`, `VM.Config.*`, `VM.PowerMgmt`,
  `Datastore.AllocateSpace`, `Datastore.AllocateTemplate`, `Datastore.Audit`, `Sys.Audit`, `Pool.Audit`.
  No `Sys.Modify`, no `Permissions.Modify`, no `Datastore.Allocate` and no root access.
- **The token expiry is set**, so a forgotten credential stops working on its own.
- **`network_vlan`** tags the NIC explicitly instead of relying on the bridge default.

Two Proxmox details are worth recording because they are not obvious:

- The API hides bridges unless the token can audit the SDN path. Reading
  `/nodes/<node>/network` with an under-privileged token returns only physical interfaces
  (`eno1`, …) with no `vmbr0`, and creating a VM with `net0=…,bridge=vmbr0` fails with
  `Permission check failed (/sdn/zones/localnetwork/vmbr0/<vlan>, SDN.Use)` **even when SDN is not
  installed** (the endpoints answer `501 no handler`). The token therefore needs `SDN.Audit` and
  `SDN.Use` on `/sdn/zones` for the bridge it attaches.
- The image datastore must be readable from every hypervisor that hosts a VM. With node-local storage
  all VMs would have to live on `image_node`, so shared storage is the recommended setup.

## Consequences

- ✅ No root SSH anywhere in the provisioning path; the credential can only touch the lab pool.
- ✅ Reproducible on a plain Proxmox node: no snippets datastore, no SSH keys distributed.
- ✅ One image import instead of one per node.
- ❌ Requires `SDN.Audit` + `SDN.Use` in the token role, a privilege pair that reads as irrelevant
  until the first `bridge = "vmbr0"` fails.
- ❌ Cloud-init user-data is limited to what the provider exposes (no arbitrary YAML). Anything
  beyond user, keys, IP, DNS and package updates belongs in Ansible.
