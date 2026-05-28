[![New Relic Experimental header](https://github.com/newrelic/opensource-website/raw/master/src/images/categories/Experimental.png)](https://opensource.newrelic.com/oss-category/#new-relic-experimental)

# Kubernetes Diag Utilities

A repository of utilities for troubleshooting Kubernetes, Pixie, and eBPF agent installation issues.

## nrk8s-diag.sh (Unified Script)

`nrk8s-diag.sh` combines Kubernetes, Pixie, and eBPF agent diagnostics into a single script. Use `-k`, `-p`, and `-e` to run specific diagnostic sets. If no flags are specified, all three are run.

### Usage

Run from a terminal with `kubectl` and (optionally) `helm` access to the cluster. The namespace will typically be `newrelic`.

```bash
# Run all diagnostics (Kubernetes + Pixie + eBPF)
./nrk8s-diag.sh -n newrelic

# Kubernetes diagnostics only
./nrk8s-diag.sh -n newrelic -k

# Pixie diagnostics only
./nrk8s-diag.sh -n newrelic -p

# eBPF agent diagnostics only
./nrk8s-diag.sh -n newrelic -e

# Kubernetes + eBPF diagnostics
./nrk8s-diag.sh -n newrelic -k -e

# Custom Helm release names
./nrk8s-diag.sh -n newrelic -r my-bundle-release -E my-ebpf-release -k -e
```

| Flag | Description |
|------|-------------|
| `-n NAMESPACE` | **(Required)** Namespace where New Relic is installed |
| `-r RELEASE_NAME` | *(Optional)* Helm release name (default: `newrelic-bundle`) |
| `-E EBPF_RELEASE_NAME` | *(Optional)* eBPF agent Helm release name (default: `nr-ebpf-agent`) |
| `-k` | Run Kubernetes diagnostics |
| `-p` | Run Pixie diagnostics |
| `-e` | Run eBPF agent diagnostics |

### Kubernetes Diagnostics (`-k`)

- New Relic endpoint connectivity checks
- Cluster info, nodes, versions, storage classes
- New Relic CRDs and ClusterRoles/ClusterRoleBindings
- Workload status (pods, deployments, daemonsets)
- Full resource descriptions for the namespace *(parallelized — up to 10 concurrent)*
- Pod logs, current and previous *(parallelized — up to 10 pods concurrent)*
- Namespace events and network policies
- Helm values and history

### Pixie Diagnostics (`-p`)

- Node memory and count validation (Pixie requires ≥ 8 GB RAM per node)
- Node system info and resource allocations
- Pixie agent status and log collection via `px` CLI (if available)
- Namespaced resource listing across `olm`, `px-operator`, and the target namespace
- Deployment logs for Pixie-related workloads
- Per-pod event collection

If you have the `px` CLI installed, authenticate before running:

```bash
px auth login
px run px/cluster
```

### eBPF Agent Diagnostics (`-e`)

- DaemonSet status, pod readiness, per-container restart counts, OOMKill/crash history
- Node kernel versions with BTF/CO-RE availability analysis (kernel ≥ 5.2 → CO-RE fallback available without kernel headers; kernel < 5.2 → kernel headers required)
- Pod logs for both the `kernel-header-installer` init container and the `nr-ebpf-agent` main container
- Full resource descriptions (DaemonSet, Service, ConfigMaps, individual pods)
- eBPF-specific ClusterRole, ClusterRoleBinding, and ServiceAccount
- Scheduling analysis: DaemonSet desired vs ready vs node count, per-node taints, DaemonSet tolerations, namespace Pod Security Admission (PSA) labels (K8s 1.25+ — `restricted` mode blocks privileged pods), and PodSecurityPolicies (pre-1.25)
- Events filtered to the `nr-ebpf-agent` DaemonSet and its pods
- Known error pattern scan across collected pod logs: kernel header failures, BTF availability, OOMKill, permission denied, RLIMIT_MEMLOCK, connection errors, and more
- Helm values for the eBPF release

> **Note:** If the eBPF agent is deployed as part of `nri-bundle` rather than standalone, pass the bundle release name with `-E` or use `-r` for the bundle and omit `-E`.

### Output

A compressed archive named `nrk8s_diag_<timestamp>.tar.gz` containing numbered log files for each diagnostic section. Attach this file to your New Relic support ticket.

| File | Content |
|------|---------|
| `00_nrk8s_diag_*.log` | Combined stdout/stderr from the entire run |
| `01–10_*.log` | Kubernetes diagnostics |
| `11–15_*.log` | Pixie diagnostics |
| `16–24_*.log` | eBPF agent diagnostics |

Temporary working files are automatically cleaned up on exit, including on failure or interrupt.

---

## Individual Scripts (Legacy)

The original standalone scripts are still available:

- `kube-diag/nrk8s-diag.sh` — Kubernetes-only diagnostics
- `pixie-diag/pixie-diag` — Pixie-only diagnostics

See the README in each subdirectory for usage details.

---

## Support

New Relic has open-sourced this project. This project is provided AS-IS WITHOUT WARRANTY OR DEDICATED SUPPORT. Issues and contributions should be reported to the project here on GitHub.

>We encourage you to bring your experiences and questions to the [Explorers Hub](https://discuss.newrelic.com) where our community members collaborate on solutions and new ideas.


## Contributing

We encourage your contributions to improve `k8s-diag-utilities`! Keep in mind when you submit your pull request, you'll need to sign the CLA via the click-through using CLA-Assistant. You only have to sign the CLA one time per project. If you have any questions, or to execute our corporate CLA, required if your contribution is on behalf of a company, please drop us an email at opensource@newrelic.com.

**A note about vulnerabilities**

As noted in our [security policy](../../security/policy), New Relic is committed to the privacy and security of our customers and their data. We believe that providing coordinated disclosure by security researchers and engaging with the security community are important means to achieve our security goals.

If you believe you have found a security vulnerability in this project or any of New Relic's products or websites, we welcome and greatly appreciate you reporting it to New Relic through [HackerOne](https://hackerone.com/newrelic).

## License

`k8s-diag-utilities` is licensed under the [Apache 2.0](http://apache.org/licenses/LICENSE-2.0.txt) License.

>[If applicable: [Project Name] also uses source code from third-party libraries. You can find full details on which libraries are used and the terms under which they are licensed in the third-party notices document.]
