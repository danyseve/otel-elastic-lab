# ADR-0001: Run Elasticsearch in KVM virtual machines, not LXC containers

- **Status:** Accepted
- **Date:** 2026-10-20

## Context

Elasticsearch needs kernel tuning (`vm.max_map_count`), no swapping, and predictable memory for
the JVM heap. LXC containers share the host kernel. Applying these settings would mean changing the
hypervisor itself, and the container's memory accounting can confuse the JVM.

## Decision

Every node runs in a KVM VM with its own kernel: `cpu=host`, ballooning disabled,
virtio-scsi-single with iothread, provisioned from the Debian cloud image with cloud-init.

## Consequences

- ✅ All tuning stays inside the guest. The hypervisor stays generic.
- ✅ The Ansible layer is portable to any cloud or on-prem VM.
- ✅ Failure experiments (hard stop, network cut) don't put the host at risk.
- ❌ About 300–500 MB extra RAM per VM, and slower provisioning than containers.
