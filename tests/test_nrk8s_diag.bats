#!/usr/bin/env bats
# Tests for nrk8s-diag.sh
# Run with: ./run_tests.sh  (requires bats-core)

SCRIPT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)/nrk8s-diag.sh"
MOCKS_DIR="${BATS_TEST_DIRNAME}/mocks"

setup() {
    export PATH="${MOCKS_DIR}:${PATH}"
    export MOCK_NS_VALID="newrelic"
    # Run from a temp dir so archives don't land in the project root
    cd "${BATS_TEST_TMPDIR}"
}

teardown() {
    rm -f "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz
}

# ── Argument parsing ───────────────────────────────────────────────────────────

@test "exits 1 and shows usage when -n is missing" {
    run bash "${SCRIPT}"
    [ "${status}" -eq 1 ]
    [[ "${output}" =~ "Usage:" ]]
}

@test "exits 1 and shows usage for unknown flag" {
    run bash "${SCRIPT}" -z
    [ "${status}" -eq 1 ]
    [[ "${output}" =~ "Usage:" ]]
}

@test "exits 1 and shows error when -n value is empty" {
    run bash "${SCRIPT}" -n "" -k
    [ "${status}" -eq 1 ]
    [[ "${output}" =~ "Usage:" ]]
}

@test "default helm release name is newrelic-bundle" {
    run bash "${SCRIPT}" -n newrelic -k
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ "newrelic-bundle" ]]
}

@test "-r overrides the helm release name" {
    run bash "${SCRIPT}" -n newrelic -r my-custom-release -k
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ "my-custom-release" ]]
}

@test "default eBPF release name is nr-ebpf-agent" {
    run bash "${SCRIPT}" -n newrelic -e
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ "nr-ebpf-agent" ]]
}

@test "-E overrides the eBPF release name" {
    run bash "${SCRIPT}" -n newrelic -e -E my-ebpf-release
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ "my-ebpf-release" ]]
}

@test "startup summary shows namespace" {
    run bash "${SCRIPT}" -n newrelic -k
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ "newrelic" ]]
}

@test "startup summary shows eBPF diagnostics flag" {
    run bash "${SCRIPT}" -n newrelic -e
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ "eBPF diagnostics" ]]
}

# ── Diagnostic mode selection ──────────────────────────────────────────────────

@test "no mode flags runs kube, pixie, and eBPF diagnostics" {
    run bash "${SCRIPT}" -n newrelic
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ "Kubernetes Diagnostics" ]]
    [[ "${output}" =~ "Pixie Diagnostics" ]]
    [[ "${output}" =~ "eBPF Agent Diagnostics" ]]
}

@test "-k runs only Kubernetes diagnostics" {
    run bash "${SCRIPT}" -n newrelic -k
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ "Kubernetes Diagnostics" ]]
    ! [[ "${output}" =~ "Pixie Diagnostics" ]]
    ! [[ "${output}" =~ "eBPF Agent Diagnostics" ]]
}

@test "-p runs only Pixie diagnostics" {
    run bash "${SCRIPT}" -n newrelic -p
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ "Pixie Diagnostics" ]]
    ! [[ "${output}" =~ "Kubernetes Diagnostics" ]]
    ! [[ "${output}" =~ "eBPF Agent Diagnostics" ]]
}

@test "-e runs only eBPF agent diagnostics" {
    run bash "${SCRIPT}" -n newrelic -e
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ "eBPF Agent Diagnostics" ]]
    ! [[ "${output}" =~ "Kubernetes Diagnostics" ]]
    ! [[ "${output}" =~ "Pixie Diagnostics" ]]
}

@test "-k and -p together runs kube and pixie only" {
    run bash "${SCRIPT}" -n newrelic -k -p
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ "Kubernetes Diagnostics" ]]
    [[ "${output}" =~ "Pixie Diagnostics" ]]
    ! [[ "${output}" =~ "eBPF Agent Diagnostics" ]]
}

@test "-k and -e together runs kube and eBPF only" {
    run bash "${SCRIPT}" -n newrelic -k -e
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ "Kubernetes Diagnostics" ]]
    [[ "${output}" =~ "eBPF Agent Diagnostics" ]]
    ! [[ "${output}" =~ "Pixie Diagnostics" ]]
}

@test "-k -p -e together runs all three diagnostics" {
    run bash "${SCRIPT}" -n newrelic -k -p -e
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ "Kubernetes Diagnostics" ]]
    [[ "${output}" =~ "Pixie Diagnostics" ]]
    [[ "${output}" =~ "eBPF Agent Diagnostics" ]]
}

# ── Namespace validation ───────────────────────────────────────────────────────

@test "exits 1 when namespace does not exist" {
    export MOCK_NS_VALID="other-ns"
    run bash "${SCRIPT}" -n newrelic -k
    [ "${status}" -eq 1 ]
    [[ "${output}" =~ "not a valid namespace" ]]
}

@test "exits 0 when namespace exists" {
    run bash "${SCRIPT}" -n newrelic -k
    [ "${status}" -eq 0 ]
}

@test "invalid namespace output lists valid namespaces" {
    export MOCK_NS_VALID="other-ns"
    run bash "${SCRIPT}" -n newrelic -k
    [ "${status}" -eq 1 ]
    [[ "${output}" =~ "Valid namespaces" ]]
}

# ── Archive creation ───────────────────────────────────────────────────────────

@test "kube mode creates a tar.gz archive" {
    run bash "${SCRIPT}" -n newrelic -k
    [ "${status}" -eq 0 ]
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    [ -n "${archive}" ]
}

@test "pixie mode creates a tar.gz archive" {
    run bash "${SCRIPT}" -n newrelic -p
    [ "${status}" -eq 0 ]
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    [ -n "${archive}" ]
}

@test "eBPF mode creates a tar.gz archive" {
    run bash "${SCRIPT}" -n newrelic -e
    [ "${status}" -eq 0 ]
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    [ -n "${archive}" ]
}

@test "archive name contains timestamp" {
    run bash "${SCRIPT}" -n newrelic -k
    [ "${status}" -eq 0 ]
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    [[ "${archive}" =~ nrk8s_diag_[0-9]{14}\.tar\.gz ]]
}

@test "output reports the archive path" {
    run bash "${SCRIPT}" -n newrelic -k
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ "nrk8s_diag_" ]]
    [[ "${output}" =~ ".tar.gz" ]]
}

# ── Archive contents ───────────────────────────────────────────────────────────

@test "kube archive contains cluster info file" {
    run bash "${SCRIPT}" -n newrelic -k
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    [[ "${contents}" =~ "01_cluster_info.log" ]]
}

@test "kube archive contains pod logs file" {
    run bash "${SCRIPT}" -n newrelic -k
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    [[ "${contents}" =~ "04_nrk8s_logs.log" ]]
}

@test "kube archive contains helm values file" {
    run bash "${SCRIPT}" -n newrelic -k
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    [[ "${contents}" =~ "06_helm_values.yaml" ]]
}

@test "pixie archive contains key info file" {
    run bash "${SCRIPT}" -n newrelic -p
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    [[ "${contents}" =~ "11_pixie_key_info.log" ]]
}

@test "pixie archive contains node info file" {
    run bash "${SCRIPT}" -n newrelic -p
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    [[ "${contents}" =~ "12_pixie_node_info.log" ]]
}

@test "eBPF archive contains daemonset status file" {
    run bash "${SCRIPT}" -n newrelic -e
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    [[ "${contents}" =~ "16_ebpf_daemonset_status.log" ]]
}

@test "eBPF archive contains node kernel info file" {
    run bash "${SCRIPT}" -n newrelic -e
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    [[ "${contents}" =~ "17_ebpf_node_kernel_info.log" ]]
}

@test "eBPF archive contains pod logs file" {
    run bash "${SCRIPT}" -n newrelic -e
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    [[ "${contents}" =~ "18_ebpf_pod_logs.log" ]]
}

@test "eBPF archive contains describe file" {
    run bash "${SCRIPT}" -n newrelic -e
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    [[ "${contents}" =~ "19_ebpf_describe.log" ]]
}

@test "eBPF archive contains helm values file" {
    run bash "${SCRIPT}" -n newrelic -e
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    [[ "${contents}" =~ "20_ebpf_helm_values.yaml" ]]
}

@test "eBPF archive contains rbac file" {
    run bash "${SCRIPT}" -n newrelic -e
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    [[ "${contents}" =~ "21_ebpf_rbac.log" ]]
}

@test "eBPF archive contains scheduling analysis file" {
    run bash "${SCRIPT}" -n newrelic -e
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    [[ "${contents}" =~ "22_ebpf_scheduling.log" ]]
}

@test "eBPF archive contains events file" {
    run bash "${SCRIPT}" -n newrelic -e
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    [[ "${contents}" =~ "23_ebpf_events.log" ]]
}

@test "eBPF archive contains log pattern scan file" {
    run bash "${SCRIPT}" -n newrelic -e
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    [[ "${contents}" =~ "24_ebpf_log_patterns.log" ]]
}

@test "kube archive does not contain pixie files when -k only" {
    run bash "${SCRIPT}" -n newrelic -k
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    ! [[ "${contents}" =~ "11_pixie_key_info.log" ]]
}

@test "kube archive does not contain eBPF files when -k only" {
    run bash "${SCRIPT}" -n newrelic -k
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    ! [[ "${contents}" =~ "16_ebpf_daemonset_status.log" ]]
}

@test "combined archive contains kube, pixie, and eBPF files" {
    run bash "${SCRIPT}" -n newrelic
    local archive
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    local contents
    contents=$(tar -tzf "${archive}")
    [[ "${contents}" =~ "01_cluster_info.log" ]]
    [[ "${contents}" =~ "11_pixie_key_info.log" ]]
    [[ "${contents}" =~ "16_ebpf_daemonset_status.log" ]]
}

# ── Archive file content ──────────────────────────────────────────────────────

@test "describe log contains resource descriptions" {
    run bash "${SCRIPT}" -n newrelic -k
    [ "${status}" -eq 0 ]
    local archive dir_name
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    dir_name=$(tar -tzf "${archive}" | head -1 | tr -d '/')
    tar -xzf "${archive}" -C "${BATS_TEST_TMPDIR}"
    [[ "$(cat "${BATS_TEST_TMPDIR}/${dir_name}/03_nrk8s_describe.log")" =~ "===" ]]
}

@test "pod logs file contains log output" {
    run bash "${SCRIPT}" -n newrelic -k
    [ "${status}" -eq 0 ]
    local archive dir_name
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    dir_name=$(tar -tzf "${archive}" | head -1 | tr -d '/')
    tar -xzf "${archive}" -C "${BATS_TEST_TMPDIR}"
    [[ "$(cat "${BATS_TEST_TMPDIR}/${dir_name}/04_nrk8s_logs.log")" =~ "Pod:" ]]
}

@test "eBPF daemonset status file contains daemonset output" {
    run bash "${SCRIPT}" -n newrelic -e
    [ "${status}" -eq 0 ]
    local archive dir_name
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    dir_name=$(tar -tzf "${archive}" | head -1 | tr -d '/')
    tar -xzf "${archive}" -C "${BATS_TEST_TMPDIR}"
    [[ "$(cat "${BATS_TEST_TMPDIR}/${dir_name}/16_ebpf_daemonset_status.log")" =~ "nr-ebpf-agent" ]]
}

@test "eBPF node kernel info file contains kernel version" {
    run bash "${SCRIPT}" -n newrelic -e
    [ "${status}" -eq 0 ]
    local archive dir_name
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    dir_name=$(tar -tzf "${archive}" | head -1 | tr -d '/')
    tar -xzf "${archive}" -C "${BATS_TEST_TMPDIR}"
    [[ "$(cat "${BATS_TEST_TMPDIR}/${dir_name}/17_ebpf_node_kernel_info.log")" =~ "Kernel" ]]
}

@test "eBPF pod logs file contains pod log output" {
    run bash "${SCRIPT}" -n newrelic -e
    [ "${status}" -eq 0 ]
    local archive dir_name
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    dir_name=$(tar -tzf "${archive}" | head -1 | tr -d '/')
    tar -xzf "${archive}" -C "${BATS_TEST_TMPDIR}"
    [[ "$(cat "${BATS_TEST_TMPDIR}/${dir_name}/18_ebpf_pod_logs.log")" =~ "nr-ebpf-agent" ]]
}

@test "eBPF rbac file contains ClusterRole output" {
    run bash "${SCRIPT}" -n newrelic -e
    [ "${status}" -eq 0 ]
    local archive dir_name
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    dir_name=$(tar -tzf "${archive}" | head -1 | tr -d '/')
    tar -xzf "${archive}" -C "${BATS_TEST_TMPDIR}"
    [[ "$(cat "${BATS_TEST_TMPDIR}/${dir_name}/21_ebpf_rbac.log")" =~ "ClusterRole" ]]
}

@test "eBPF scheduling file contains daemonset scheduling summary" {
    run bash "${SCRIPT}" -n newrelic -e
    [ "${status}" -eq 0 ]
    local archive dir_name
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    dir_name=$(tar -tzf "${archive}" | head -1 | tr -d '/')
    tar -xzf "${archive}" -C "${BATS_TEST_TMPDIR}"
    [[ "$(cat "${BATS_TEST_TMPDIR}/${dir_name}/22_ebpf_scheduling.log")" =~ "Desired" ]]
}

@test "eBPF scheduling file contains namespace PSA label output" {
    run bash "${SCRIPT}" -n newrelic -e
    [ "${status}" -eq 0 ]
    local archive dir_name
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    dir_name=$(tar -tzf "${archive}" | head -1 | tr -d '/')
    tar -xzf "${archive}" -C "${BATS_TEST_TMPDIR}"
    [[ "$(cat "${BATS_TEST_TMPDIR}/${dir_name}/22_ebpf_scheduling.log")" =~ "newrelic" ]]
}

@test "eBPF events file contains events output" {
    run bash "${SCRIPT}" -n newrelic -e
    [ "${status}" -eq 0 ]
    local archive dir_name
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    dir_name=$(tar -tzf "${archive}" | head -1 | tr -d '/')
    tar -xzf "${archive}" -C "${BATS_TEST_TMPDIR}"
    [[ "$(cat "${BATS_TEST_TMPDIR}/${dir_name}/23_ebpf_events.log")" =~ "nr-ebpf-agent" ]]
}

@test "eBPF node kernel info file contains BTF analysis" {
    run bash "${SCRIPT}" -n newrelic -e
    [ "${status}" -eq 0 ]
    local archive dir_name
    archive=$(ls "${BATS_TEST_TMPDIR}"/nrk8s_diag_*.tar.gz 2>/dev/null | head -1)
    dir_name=$(tar -tzf "${archive}" | head -1 | tr -d '/')
    tar -xzf "${archive}" -C "${BATS_TEST_TMPDIR}"
    [[ "$(cat "${BATS_TEST_TMPDIR}/${dir_name}/17_ebpf_node_kernel_info.log")" =~ "BTF" ]]
}

# ── Temp directory cleanup ─────────────────────────────────────────────────────

@test "no temp directories are left after successful run" {
    run bash "${SCRIPT}" -n newrelic -k
    [ "${status}" -eq 0 ]
    local leaked
    leaked=$(find /private/var/folders /tmp -maxdepth 6 -type d -name "nrk8s_diag_*" 2>/dev/null || true)
    [ -z "${leaked}" ]
}

@test "no temp directories are left after failed run" {
    export MOCK_NS_VALID="other-ns"
    run bash "${SCRIPT}" -n newrelic -k
    [ "${status}" -eq 1 ]
    local leaked
    leaked=$(find /private/var/folders /tmp -maxdepth 6 -type d -name "nrk8s_diag_*" 2>/dev/null || true)
    [ -z "${leaked}" ]
}

# ── px CLI availability ────────────────────────────────────────────────────────

@test "pixie diagnostics complete when px CLI is unavailable" {
    # Build a PATH with kubectl and helm mocks but no px
    local no_px_dir="${BATS_TEST_TMPDIR}/mocks_no_px"
    mkdir -p "${no_px_dir}"
    ln -sf "${MOCKS_DIR}/kubectl" "${no_px_dir}/kubectl"
    ln -sf "${MOCKS_DIR}/helm"    "${no_px_dir}/helm"
    local clean_path
    clean_path=$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v "^${MOCKS_DIR}$" | tr '\n' ':')
    export PATH="${no_px_dir}:${clean_path}"

    run bash "${SCRIPT}" -n newrelic -p
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ "px CLI unavailable" ]]
}

@test "pixie diagnostics show agent status when px CLI is available" {
    run bash "${SCRIPT}" -n newrelic -p
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ "Pixie Agent Status" ]]
}
