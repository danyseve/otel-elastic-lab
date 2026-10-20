# ADR-0001: Kubernetes nodes are KVM virtual machines, not LXC containers

- **Status:** Accepted
- **Date:** 2026-10-20

## Context

The cluster runs Elasticsearch, which needs kernel tuning (`vm.max_map_count`), no swapping and
predictable memory. Kubernetes (k3s) itself also expects its own kernel: cgroups, overlay
filesystems and `sysctl`s. LXC containers share the host kernel. Running Kubernetes inside them
means privileged containers, and every tuning change becomes a change to the hypervisor.

## Decision

Each Kubernetes node is a KVM VM with its own kernel: `cpu=host`, ballooning disabled,
virtio-scsi-single with iothread, provisioned from the Debian cloud image with cloud-init. There is
one VM per physical hypervisor host.

## Consequences

- ✅ All tuning stays inside the guest. The hypervisor stays generic.
- ✅ The same layout works on any on-prem virtualization or in a cloud.
- ✅ Failure experiments (hard stop, network cut) don't put the host at risk.
- ❌ About 300–500 MB extra RAM per VM, and slower provisioning than containers.
