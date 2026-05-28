#!/usr/bin/env bash
# nrk8s-diag.sh - Kubernetes, Pixie, and eBPF agent diagnostics for New Relic Kubernetes integrations.
# Run with -k for Kubernetes-only, -p for Pixie-only, -e for eBPF-only, or omit all to run all diagnostics.

set -euo pipefail
IFS=$'\n\t'

# ── Defaults ──────────────────────────────────────────────────────────────────
NAMESPACE=""
RELEASE_NAME="newrelic-bundle"
EBPF_RELEASE_NAME="nr-ebpf-agent"
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
ARCHIVE_NAME="nrk8s_diag_$TIMESTAMP"
ARCHIVE_FILE="$PWD/${ARCHIVE_NAME}.tar.gz"
RUN_KUBE=false
RUN_PIXIE=false
RUN_EBPF=false

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 -n NAMESPACE [-r RELEASE_NAME] [-E EBPF_RELEASE_NAME] [-k] [-p] [-e]"
    echo ""
    echo "  -n NAMESPACE            (Required) Namespace where New Relic is installed."
    echo "  -r RELEASE_NAME         (Optional) Helm release name. (Default: newrelic-bundle)"
    echo "  -E EBPF_RELEASE_NAME    (Optional) eBPF agent Helm release name. (Default: nr-ebpf-agent)"
    echo "  -k                      Run Kubernetes diagnostics."
    echo "  -p                      Run Pixie diagnostics."
    echo "  -e                      Run eBPF agent diagnostics."
    echo ""
    echo "If none of -k, -p, or -e is specified, all three diagnostics are run."
    exit 1
}

# ── Option parsing ─────────────────────────────────────────────────────────────
while getopts ":n:r:E:kpe" opt; do
    case "${opt}" in
        n) NAMESPACE="${OPTARG}" ;;
        r) RELEASE_NAME="${OPTARG}" ;;
        E) EBPF_RELEASE_NAME="${OPTARG}" ;;
        k) RUN_KUBE=true ;;
        p) RUN_PIXIE=true ;;
        e) RUN_EBPF=true ;;
        *) usage ;;
    esac
done

if [[ -z "${NAMESPACE}" ]]; then
    echo "Error: Namespace (-n) is required."
    usage
fi

# Default: run all if no mode flag given
if ! "${RUN_KUBE}" && ! "${RUN_PIXIE}" && ! "${RUN_EBPF}"; then
    RUN_KUBE=true
    RUN_PIXIE=true
    RUN_EBPF=true
fi

# ── Setup output directory ─────────────────────────────────────────────────────
TEMP_DIR=$(mktemp -d)
OUTPUT_DIR="$TEMP_DIR/$ARCHIVE_NAME"
mkdir -p "$OUTPUT_DIR"

trap 'rm -rf "${TEMP_DIR}"' EXIT

MAIN_LOG_FILE="$OUTPUT_DIR/00_nrk8s_diag_$TIMESTAMP.log"

# Kube output files
CLUSTER_INFO_FILE="$OUTPUT_DIR/01_cluster_info.log"
WORKLOAD_STATUS_FILE="$OUTPUT_DIR/02_workload_status.log"
DESCRIBE_LOG_FILE="$OUTPUT_DIR/03_nrk8s_describe.log"
POD_LOGS_FILE="$OUTPUT_DIR/04_nrk8s_logs.log"
EVENTS_FILE="$OUTPUT_DIR/05_namespace_events.log"
HELM_VALUES_FILE="$OUTPUT_DIR/06_helm_values.yaml"
HELM_HISTORY_FILE="$OUTPUT_DIR/07_helm_history.log"
NETPOL_FILE="$OUTPUT_DIR/08_network_policies.log"
CRD_FILE="$OUTPUT_DIR/09_newrelic_crds.log"
CLUSTER_ROLE_FILE="$OUTPUT_DIR/10_newrelic_clusterroles.log"

# Pixie output files
PIXIE_KEY_INFO_FILE="$OUTPUT_DIR/11_pixie_key_info.log"
PIXIE_NODE_INFO_FILE="$OUTPUT_DIR/12_pixie_node_info.log"
PIXIE_RESOURCES_FILE="$OUTPUT_DIR/13_pixie_resources.log"
PIXIE_DEPLOY_LOGS_FILE="$OUTPUT_DIR/14_pixie_deploy_logs.log"
PIXIE_POD_EVENTS_FILE="$OUTPUT_DIR/15_pixie_pod_events.log"

# eBPF output files
EBPF_DAEMONSET_FILE="$OUTPUT_DIR/16_ebpf_daemonset_status.log"
EBPF_NODE_KERNEL_FILE="$OUTPUT_DIR/17_ebpf_node_kernel_info.log"
EBPF_LOGS_FILE="$OUTPUT_DIR/18_ebpf_pod_logs.log"
EBPF_DESCRIBE_FILE="$OUTPUT_DIR/19_ebpf_describe.log"
EBPF_HELM_VALUES_FILE="$OUTPUT_DIR/20_ebpf_helm_values.yaml"
EBPF_RBAC_FILE="$OUTPUT_DIR/21_ebpf_rbac.log"
EBPF_SCHEDULING_FILE="$OUTPUT_DIR/22_ebpf_scheduling.log"
EBPF_EVENTS_FILE="$OUTPUT_DIR/23_ebpf_events.log"
EBPF_LOG_PATTERNS_FILE="$OUTPUT_DIR/24_ebpf_log_patterns.log"

exec > >(tee -a "$MAIN_LOG_FILE") 2>&1

# ── Helpers ───────────────────────────────────────────────────────────────────
declare -a NAMES_ONLY=( --no-headers -o jsonpath='{.items[*].metadata.name}' )

my_banner() {
    local msg="${1:-}"
    local size="${2:-57}"
    printf "\n"
    printf '%*s' "${size}" '' | tr ' ' '*'
    printf "\n* %s\n" "${msg}"
    printf '%*s' "${size}" '' | tr ' ' '*'
    printf "\n\n"
}

titleize() {
    printf '%s' "${1}" | tr '_' ' ' | sed 's/\b\(.\)/\u\1/g'
}

validate_namespace() {
    if ! kubectl get ns "${NAMESPACE}" >/dev/null 2>&1; then
        local valid_namespaces
        valid_namespaces="$(kubectl get ns "${NAMES_ONLY[@]}" 2>/dev/null || true)"
        printf "ERROR: '%s' is not a valid namespace.\n" "${NAMESPACE}"
        printf "Valid namespaces:\n"
        for ns in ${valid_namespaces}; do
            printf "  %s\n" "${ns}"
        done
        exit 1
    fi
}

# ── Shared ────────────────────────────────────────────────────────────────────
check_newrelic_connectivity() {
    my_banner "Checking Connectivity to New Relic Endpoints"

    local endpoints=(
        "https://metric-api.newrelic.com/stat/v1"
        "https://metric-api.eu.newrelic.com/stat/v1"
        "https://log-api.newrelic.com/log/v1"
        "https://log-api.eu.newrelic.com/log/v1"
    )

    for endpoint in "${endpoints[@]}"; do
        printf "Checking: %s\n" "${endpoint}"
        local http_status
        http_status=$(kubectl run "nr-diag-conn-$$" \
            --image=curlimages/curl \
            --rm \
            --restart=Never \
            --attach \
            --quiet \
            --command -- sh -c \
            "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 ${endpoint}") \
            || { printf "  Connectivity pod failed.\n"; continue; }
        printf "  HTTP Status: %s\n" "${http_status}"
    done
}

# ── Kube diagnostics ──────────────────────────────────────────────────────────
gather_cluster_info() {
    my_banner "Gathering Cluster Information → $(basename "${CLUSTER_INFO_FILE}")"
    {
        printf "Cluster Name: %s\n" "$(kubectl config current-context)"

        printf "\nKubectl Version:\n"
        kubectl version --client

        printf "\nKubernetes Version:\n"
        kubectl version --short 2>/dev/null || kubectl version

        printf "\nCluster Info:\n"
        kubectl cluster-info

        printf "\nCluster Nodes:\n"
        kubectl get nodes -o wide

        printf "\nNode Count: %s\n" "$(kubectl get nodes --no-headers | wc -l)"

        printf "\nNode Capacity:\n"
        kubectl get nodes -o jsonpath="{range .items[*]}Name: {.metadata.name}, CPU: {.status.capacity.cpu}, Memory: {.status.capacity.memory}\n{end}"

        printf "\nStorage Classes:\n"
        kubectl get storageclass

        printf "\nTop Nodes:\n"
        kubectl top nodes || printf "Metrics (top) not available.\n"

    } >> "${CLUSTER_INFO_FILE}" 2>&1
}

gather_crds() {
    my_banner "Gathering New Relic CRDs → $(basename "${CRD_FILE}")"
    {
        printf "CRDs matching 'newrelic' or 'nri':\n"
        kubectl get crds | grep -i -E 'newrelic|nri' || printf "No New Relic CRDs found.\n"
    } >> "${CRD_FILE}" 2>&1
}

gather_cluster_roles() {
    my_banner "Gathering New Relic ClusterRoles → $(basename "${CLUSTER_ROLE_FILE}")"
    {
        printf "ClusterRoles matching 'newrelic' or 'nri':\n"
        kubectl get clusterrole -o wide | grep -i -E 'newrelic|nri' || printf "None found.\n"

        printf "\nClusterRoleBindings matching 'newrelic' or 'nri':\n"
        kubectl get clusterrolebinding -o wide | grep -i -E 'newrelic|nri' || printf "None found.\n"
    } >> "${CLUSTER_ROLE_FILE}" 2>&1
}

gather_workload_status() {
    my_banner "Gathering Workload Status for '${NAMESPACE}' → $(basename "${WORKLOAD_STATUS_FILE}")"
    {
        printf "Deployments, DaemonSets, StatefulSets, Jobs:\n"
        kubectl get deployment,daemonset,statefulset,job,cronjob -n "${NAMESPACE}" -o wide

        printf "\nAll Pods:\n"
        kubectl get pods -n "${NAMESPACE}" -o wide

        printf "\nPods with non-Running/Succeeded status:\n"
        kubectl get pods -n "${NAMESPACE}" \
            --field-selector=status.phase!=Running,status.phase!=Succeeded \
            || printf "All pods are Running or Succeeded.\n"

        printf "\nTop Pods:\n"
        kubectl top pods -n "${NAMESPACE}" || printf "Metrics (top) not available.\n"

    } >> "${WORKLOAD_STATUS_FILE}" 2>&1
}

describe_all_resources() {
    my_banner "Describing All Resources in '${NAMESPACE}' → $(basename "${DESCRIBE_LOG_FILE}")"

    local resource_types
    resource_types=$(kubectl api-resources --namespaced=true -o name | grep -vE "^events$|^events\." | sort | uniq)

    local work_dir
    work_dir=$(mktemp -d)
    local job_count=0
    local max_jobs=10

    for resource in ${resource_types}; do
        (
            local names
            names=$(kubectl get "${resource}" -n "${NAMESPACE}" \
                --no-headers -o custom-columns=":metadata.name" 2>/dev/null) || exit 0
            [[ -z "${names}" ]] && exit 0

            {
                for name in ${names}; do
                    printf "\n===  %s/%s  ===\n" "${resource}" "${name}"
                    kubectl describe "${resource}" "${name}" -n "${NAMESPACE}"
                done
            } > "${work_dir}/${resource}.log" 2>&1
        ) &

        job_count=$(( job_count + 1 ))
        if [[ ${job_count} -ge ${max_jobs} ]]; then
            wait
            job_count=0
        fi
    done
    wait

    {
        for f in $(find "${work_dir}" -name "*.log" -type f | sort); do
            cat "${f}"
        done
    } >> "${DESCRIBE_LOG_FILE}" 2>&1

    rm -rf "${work_dir}"
}

retrieve_pod_logs() {
    my_banner "Retrieving Pod Logs for '${NAMESPACE}' → $(basename "${POD_LOGS_FILE}")"

    local pods
    pods=$(kubectl get pods -n "${NAMESPACE}" --no-headers -o custom-columns=":metadata.name")

    if [[ -z "${pods}" ]]; then
        printf "No pods found in namespace '%s'.\n" "${NAMESPACE}" >> "${POD_LOGS_FILE}"
        return
    fi

    local work_dir
    work_dir=$(mktemp -d)
    local job_count=0
    local max_jobs=10

    for pod in ${pods}; do
        (
            local containers
            containers=$(kubectl get pod "${pod}" -n "${NAMESPACE}" \
                -o jsonpath='{range .spec.initContainers[*]}{.name} {end}{range .spec.containers[*]}{.name} {end}') || exit 0
            IFS=' ' read -r -a container_array <<< "${containers}"

            {
                for container in "${container_array[@]}"; do
                    printf "\n=====  Pod: %s / Container: %s  =====\n" "${pod}" "${container}"
                    echo "--- CURRENT ---"
                    kubectl logs "${pod}" -c "${container}" -n "${NAMESPACE}" --tail=1000 \
                        || printf "No current logs.\n"
                    echo "--- PREVIOUS ---"
                    kubectl logs --previous "${pod}" -c "${container}" -n "${NAMESPACE}" --tail=1000 \
                        || printf "No previous logs (normal if pod has not restarted).\n"
                done
            } > "${work_dir}/${pod}.log" 2>&1
        ) &

        job_count=$(( job_count + 1 ))
        if [[ ${job_count} -ge ${max_jobs} ]]; then
            wait
            job_count=0
        fi
    done
    wait

    {
        for f in $(find "${work_dir}" -name "*.log" -type f | sort); do
            cat "${f}"
        done
    } >> "${POD_LOGS_FILE}" 2>&1

    rm -rf "${work_dir}"
}

gather_namespace_events() {
    my_banner "Gathering Events for '${NAMESPACE}' → $(basename "${EVENTS_FILE}")"
    {
        kubectl get events -n "${NAMESPACE}" --sort-by='.lastTimestamp'
    } >> "${EVENTS_FILE}" 2>&1
}

gather_network_policies() {
    my_banner "Gathering NetworkPolicies in '${NAMESPACE}' → $(basename "${NETPOL_FILE}")"
    {
        kubectl get networkpolicy -n "${NAMESPACE}" -o yaml \
            || printf "No NetworkPolicies found or error retrieving them.\n"
    } >> "${NETPOL_FILE}" 2>&1
}

get_helm_values() {
    my_banner "Helm Values for '${RELEASE_NAME}' → $(basename "${HELM_VALUES_FILE}")"
    helm get values --all -n "${NAMESPACE}" "${RELEASE_NAME}" > "${HELM_VALUES_FILE}" || {
        printf "Failed to retrieve Helm values for release '%s' in namespace '%s'.\n" \
            "${RELEASE_NAME}" "${NAMESPACE}"
        printf "Re-run with: -r YOUR_RELEASE_NAME\n"
    }
}

get_helm_history() {
    my_banner "Helm History for '${RELEASE_NAME}' → $(basename "${HELM_HISTORY_FILE}")"
    helm history -n "${NAMESPACE}" "${RELEASE_NAME}" > "${HELM_HISTORY_FILE}" || {
        printf "Failed to retrieve Helm history for release '%s'.\n" "${RELEASE_NAME}"
    }
}

# ── Pixie diagnostics ─────────────────────────────────────────────────────────
is_px_cli_available() {
    if ! type px >/dev/null 2>&1; then
        printf "px CLI unavailable — skipping Pixie agent checks.\n" >&2
        return 1
    fi
    return 0
}

get_pixie_agent_status() {
    my_banner "Pixie Agent Status"
    if px run px/agent_status; then
        printf "\nCollecting Pixie logs...\n"
        px collect-logs
    fi
}

get_pixie_key_information() {
    my_banner "Pixie Key Information → $(basename "${PIXIE_KEY_INFO_FILE}")"
    {
        local nodecount
        nodecount=$(kubectl get nodes --no-headers | wc -l)
        printf "Cluster has %d nodes\n" "${nodecount}"
        [[ "${nodecount}" -gt 100 ]] && printf "WARNING: Node count exceeds 100\n"

        local memory
        memory=$(kubectl get nodes -o jsonpath='{.items[0].status.capacity.memory}' | sed 's/Ki$//')
        printf "Node memory (first node): %s Ki\n" "${memory}"
        if [[ "${memory}" -lt 7950912 ]]; then
            printf "WARNING: Pixie requires nodes with >= 8GB RAM; got %s Ki.\n" "${memory}"
        fi

        local pods_not_running
        pods_not_running=$(kubectl -n "${NAMESPACE}" get pods --no-headers | grep -v Running || true)
        local count
        count=$(printf "%s" "${pods_not_running}" | grep -c . || true)
        if [[ "${count}" -gt 0 ]]; then
            printf "\nThere are %d pods not running:\n%s\n" "${count}" "${pods_not_running}"
        fi
    } >> "${PIXIE_KEY_INFO_FILE}" 2>&1
}

get_pixie_node_information() {
    my_banner "Pixie Node Information → $(basename "${PIXIE_NODE_INFO_FILE}")"
    {
        local nodes=()
        IFS=' ' read -r -a nodes <<< "$(kubectl get no "${NAMES_ONLY[@]}")"
        local regex='Kernel|OS( Image)?|Architecture|(Container Runtime|Kubelet) Version'

        printf "=== System Info ===\n"
        for node in "${nodes[@]}"; do
            printf "\n%s:\n" "${node}"
            kubectl describe node "${node}" | grep -iE "${regex}"
        done

        printf "\n=== Allocated Resources ===\n"
        for node in "${nodes[@]}"; do
            printf "\n%s:\n" "${node}"
            kubectl describe node "${node}" | grep -i "allocated resources" -A 9
        done

        printf "\n=== Node Details (first 3) ===\n"
        local i=0
        for node in "${nodes[@]}"; do
            [[ ${i} -ge 3 ]] && break
            kubectl describe node "${node}"
            i=$(( i + 1 ))
        done
    } >> "${PIXIE_NODE_INFO_FILE}" 2>&1
}

get_pixie_namespaced_resources() {
    my_banner "Pixie Namespaced Resources → $(basename "${PIXIE_RESOURCES_FILE}")"
    local pixie_namespaces=( 'olm' 'px-operator' "${NAMESPACE}" )
    {
        local api_resources
        api_resources="$(kubectl api-resources --verbs=list --namespaced=true -o name \
            | grep -v "events" | sort -u)"

        for resource in ${api_resources}; do
            for ns in "${pixie_namespaces[@]}"; do
                local output
                output=$(kubectl -n "${ns}" get "${resource}" --no-headers 2>/dev/null || true)
                if [[ -n "${output}" ]]; then
                    printf "\n*** %s in namespace: %s ***\n%s\n" "${resource}" "${ns}" "${output}"
                fi
            done
        done
    } >> "${PIXIE_RESOURCES_FILE}" 2>&1
}

get_pixie_deployment_logs() {
    my_banner "Pixie Deployment Logs → $(basename "${PIXIE_DEPLOY_LOGS_FILE}")"
    local pixie_namespaces=( 'olm' 'px-operator' "${NAMESPACE}" )
    {
        for ns in "${pixie_namespaces[@]}"; do
            local deployments
            deployments=$(kubectl -n "${ns}" get deployments "${NAMES_ONLY[@]}" 2>/dev/null || true)

            for deployment in ${deployments}; do
                local cmd=( kubectl -n "${ns}" logs --tail=50 "deployments/${deployment}" )

                if [[ "${deployment}" =~ ^.*nri-kube-events.*$ ]]; then
                    for container in 'kube-events' 'forwarder'; do
                        printf "\n=====  %s / container: %s  =====\n" "${deployment}" "${container}"
                        "${cmd[@]}" -c "${container}" || true
                    done
                else
                    printf "\n=====  %s  =====\n" "${deployment}"
                    "${cmd[@]}" || true
                fi
            done
        done
    } >> "${PIXIE_DEPLOY_LOGS_FILE}" 2>&1
}

get_pixie_pod_events() {
    my_banner "Pixie Pod Events → $(basename "${PIXIE_POD_EVENTS_FILE}")"
    {
        local pods
        pods=$(kubectl -n "${NAMESPACE}" get pods "${NAMES_ONLY[@]}")

        for pod in ${pods}; do
            local events
            events=$(kubectl get -A events --sort-by='.lastTimestamp' 2>/dev/null \
                | grep -i "${pod}" || true)
            if [[ -n "${events}" ]]; then
                printf "\nEvents for pod %s:\n%s\n" "${pod}" "${events}"
            fi
        done
    } >> "${PIXIE_POD_EVENTS_FILE}" 2>&1
}

# ── eBPF agent diagnostics ────────────────────────────────────────────────────
gather_ebpf_daemonset_status() {
    my_banner "eBPF Agent DaemonSet Status → $(basename "${EBPF_DAEMONSET_FILE}")"
    {
        printf "DaemonSet:\n"
        kubectl get daemonset nr-ebpf-agent -n "${NAMESPACE}" -o wide \
            || printf "nr-ebpf-agent DaemonSet not found in namespace '%s'.\n" "${NAMESPACE}"

        printf "\nAll eBPF agent pods:\n"
        kubectl get pods -n "${NAMESPACE}" -l app=nr-ebpf-agent -o wide || true

        printf "\neBPF pods with non-Running/Succeeded status:\n"
        kubectl get pods -n "${NAMESPACE}" -l app=nr-ebpf-agent \
            --field-selector=status.phase!=Running,status.phase!=Succeeded \
            || printf "All eBPF agent pods are Running or Succeeded.\n"

        printf "\nContainer status per pod:\n"
        kubectl get pods -n "${NAMESPACE}" -l app=nr-ebpf-agent \
            -o jsonpath='{range .items[*]}Pod: {.metadata.name}{"\n"}{range .status.initContainerStatuses[*]}  Init [{.name}]: ready={.ready} restarts={.restartCount}{"\n"}{end}{range .status.containerStatuses[*]}  Container [{.name}]: ready={.ready} restarts={.restartCount}{"\n"}{end}{end}' \
            || true

        printf "\nOOMKill / crash history (OOMKilled eBPF agents indicate TABLE_STORE_DATA_LIMIT_MB is too low):\n"
        kubectl get pods -n "${NAMESPACE}" -l app=nr-ebpf-agent \
            -o jsonpath='{range .items[*]}Pod: {.metadata.name}{"\n"}{range .status.initContainerStatuses[*]}  Init [{.name}]: lastTerminated={.lastState.terminated.reason} exitCode={.lastState.terminated.exitCode}{"\n"}{end}{range .status.containerStatuses[*]}  [{.name}]: lastTerminated={.lastState.terminated.reason} exitCode={.lastState.terminated.exitCode}{"\n"}{end}{end}' \
            || true
    } >> "${EBPF_DAEMONSET_FILE}" 2>&1
}

gather_ebpf_node_kernel_info() {
    my_banner "eBPF Node Kernel Information → $(basename "${EBPF_NODE_KERNEL_FILE}")"
    {
        printf "Kernel versions per node (eBPF agent requires Linux kernel >= 4.14):\n"
        kubectl get nodes \
            -o jsonpath='{range .items[*]}Node: {.metadata.name}  Kernel: {.status.nodeInfo.kernelVersion}  OS: {.status.nodeInfo.osImage}  Arch: {.status.nodeInfo.architecture}{"\n"}{end}' \
            || printf "Failed to retrieve node kernel info.\n"

        printf "\nContainer runtime per node:\n"
        kubectl get nodes \
            -o jsonpath='{range .items[*]}Node: {.metadata.name}  Runtime: {.status.nodeInfo.containerRuntimeVersion}{"\n"}{end}' \
            || true

        printf "\nBTF/CO-RE availability analysis:\n"
        printf "(kernel >= 5.2 → BTF at /sys/kernel/btf/vmlinux, CO-RE fallback possible without kernel headers)\n"
        printf "(kernel < 5.2  → kernel headers REQUIRED for eBPF agent to function)\n"
        printf "(COS/Bottlerocket/RHCOS: check 18_ebpf_pod_logs.log for installer-specific output)\n\n"
        kubectl get nodes \
            -o jsonpath='{range .items[*]}{.metadata.name} {.status.nodeInfo.kernelVersion} {.status.nodeInfo.osImage}{"\n"}{end}' 2>/dev/null \
        | awk '{
            n=$1; kv=$2
            split(kv, parts, /[.-]/)
            major=int(parts[1]); minor=int(parts[2])
            btf = (major > 5 || (major == 5 && minor >= 2)) ? "BTF=likely-available" : "BTF=not-available (kernel-headers required)"
            printf "%-40s kernel=%-30s %s\n", n, kv, btf
        }' || printf "Failed to retrieve node kernel info for BTF analysis.\n"
    } >> "${EBPF_NODE_KERNEL_FILE}" 2>&1
}

gather_ebpf_pod_logs() {
    my_banner "eBPF Agent Pod Logs → $(basename "${EBPF_LOGS_FILE}")"

    local pods
    pods=$(kubectl get pods -n "${NAMESPACE}" -l app=nr-ebpf-agent \
        --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)

    if [[ -z "${pods}" ]]; then
        printf "No nr-ebpf-agent pods found in namespace '%s'.\n" "${NAMESPACE}" >> "${EBPF_LOGS_FILE}"
        return
    fi

    for pod in ${pods}; do
        {
            printf "\n===== Pod: %s =====\n" "${pod}"

            printf "\n--- init: kernel-header-installer ---\n"
            kubectl logs "${pod}" -c kernel-header-installer -n "${NAMESPACE}" 2>/dev/null \
                || printf "No logs (init container may have completed).\n"

            printf "\n--- container: nr-ebpf-agent (current) ---\n"
            kubectl logs "${pod}" -c nr-ebpf-agent -n "${NAMESPACE}" --tail=500 2>/dev/null \
                || printf "No current logs.\n"

            printf "\n--- container: nr-ebpf-agent (previous) ---\n"
            kubectl logs --previous "${pod}" -c nr-ebpf-agent -n "${NAMESPACE}" --tail=500 2>/dev/null \
                || printf "No previous logs.\n"
        } >> "${EBPF_LOGS_FILE}" 2>&1
    done
}

describe_ebpf_resources() {
    my_banner "Describing eBPF Agent Resources → $(basename "${EBPF_DESCRIBE_FILE}")"
    {
        printf "=== DaemonSet ===\n"
        kubectl describe daemonset nr-ebpf-agent -n "${NAMESPACE}" \
            || printf "nr-ebpf-agent DaemonSet not found.\n"

        printf "\n=== Service ===\n"
        kubectl describe service nr-ebpf-agent -n "${NAMESPACE}" 2>/dev/null \
            || printf "No nr-ebpf-agent Service found.\n"

        printf "\n=== ConfigMaps ===\n"
        kubectl get configmap -n "${NAMESPACE}" -l app=nr-ebpf-agent -o yaml 2>/dev/null \
            || printf "No nr-ebpf-agent ConfigMaps found.\n"

        printf "\n=== Pods ===\n"
        local pods
        pods=$(kubectl get pods -n "${NAMESPACE}" -l app=nr-ebpf-agent \
            --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)
        for pod in ${pods}; do
            printf "\n--- Pod: %s ---\n" "${pod}"
            kubectl describe pod "${pod}" -n "${NAMESPACE}"
        done
    } >> "${EBPF_DESCRIBE_FILE}" 2>&1
}

get_ebpf_helm_values() {
    my_banner "eBPF Helm Values for '${EBPF_RELEASE_NAME}' → $(basename "${EBPF_HELM_VALUES_FILE}")"
    helm get values --all -n "${NAMESPACE}" "${EBPF_RELEASE_NAME}" > "${EBPF_HELM_VALUES_FILE}" || {
        printf "Failed to retrieve Helm values for eBPF release '%s' in namespace '%s'.\n" \
            "${EBPF_RELEASE_NAME}" "${NAMESPACE}"
        printf "If deployed standalone: re-run with -E YOUR_RELEASE_NAME\n"
        printf "If deployed via nri-bundle: use -r YOUR_BUNDLE_RELEASE_NAME\n"
    }
}

gather_ebpf_rbac() {
    my_banner "eBPF Agent RBAC → $(basename "${EBPF_RBAC_FILE}")"
    {
        printf "=== ClusterRole: nr-ebpf-agent ===\n"
        kubectl get clusterrole nr-ebpf-agent -o yaml 2>/dev/null \
            || printf "ClusterRole 'nr-ebpf-agent' not found — agent may lack API access.\n"

        printf "\n=== ClusterRoleBinding: nr-ebpf-agent ===\n"
        kubectl get clusterrolebinding nr-ebpf-agent -o yaml 2>/dev/null \
            || printf "ClusterRoleBinding 'nr-ebpf-agent' not found — ServiceAccount may be unbound.\n"

        printf "\n=== ServiceAccount: nr-ebpf-agent ===\n"
        kubectl get serviceaccount nr-ebpf-agent -n "${NAMESPACE}" -o yaml 2>/dev/null \
            || printf "ServiceAccount 'nr-ebpf-agent' not found in namespace '%s'.\n" "${NAMESPACE}"
    } >> "${EBPF_RBAC_FILE}" 2>&1
}

gather_ebpf_scheduling() {
    my_banner "eBPF Agent Scheduling Analysis → $(basename "${EBPF_SCHEDULING_FILE}")"
    {
        printf "DaemonSet scheduling summary:\n"
        kubectl get daemonset nr-ebpf-agent -n "${NAMESPACE}" \
            -o jsonpath='Desired: {.status.desiredNumberScheduled}  Scheduled: {.status.currentNumberScheduled}  Ready: {.status.numberReady}  Available: {.status.numberAvailable}  Misscheduled: {.status.numberMisscheduled}{"\n"}' \
            || printf "nr-ebpf-agent DaemonSet not found.\n"

        printf "\nTotal node count: "
        kubectl get nodes --no-headers 2>/dev/null | wc -l || printf "unknown\n"
        printf "(desired should equal node count — mismatch means taints or nodeSelector is blocking scheduling)\n"

        printf "\nNode taints:\n"
        kubectl get nodes \
            -o jsonpath='{range .items[*]}Node: {.metadata.name}{"\n"}{range .spec.taints[*]}  Taint: {.key}={.value}:{.effect}{"\n"}{end}{end}' \
            || true

        printf "\nDaemonSet tolerations:\n"
        kubectl get daemonset nr-ebpf-agent -n "${NAMESPACE}" \
            -o jsonpath='{range .spec.template.spec.tolerations[*]}{.key}={.value}:{.effect}{"\n"}{end}' 2>/dev/null \
            || printf "No tolerations configured or DaemonSet not found.\n"

        printf "\nNamespace PSA labels (pod-security.kubernetes.io/enforce=restricted blocks privileged pods):\n"
        kubectl get namespace "${NAMESPACE}" --show-labels 2>/dev/null \
            || kubectl get namespace "${NAMESPACE}" -o jsonpath='{.metadata.labels}' 2>/dev/null \
            || true

        printf "\nPodSecurityPolicies matching nr-ebpf or privileged (pre-K8s 1.25):\n"
        kubectl get psp 2>/dev/null | grep -i -E 'nr-ebpf|privileged' \
            || printf "No matching PodSecurityPolicies found (PSP removed in K8s 1.25+).\n"
    } >> "${EBPF_SCHEDULING_FILE}" 2>&1
}

gather_ebpf_events() {
    my_banner "eBPF Agent Events → $(basename "${EBPF_EVENTS_FILE}")"
    {
        printf "Events for nr-ebpf-agent DaemonSet:\n"
        kubectl get events -n "${NAMESPACE}" \
            --field-selector involvedObject.name=nr-ebpf-agent \
            --sort-by='.lastTimestamp' 2>/dev/null \
            || printf "No events found for nr-ebpf-agent DaemonSet.\n"

        printf "\nEvents for nr-ebpf-agent pods:\n"
        local pods
        pods=$(kubectl get pods -n "${NAMESPACE}" -l app=nr-ebpf-agent \
            --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)
        if [[ -z "${pods}" ]]; then
            printf "No nr-ebpf-agent pods found.\n"
        else
            for pod in ${pods}; do
                printf "\n--- Pod: %s ---\n" "${pod}"
                kubectl get events -n "${NAMESPACE}" \
                    --field-selector "involvedObject.name=${pod}" \
                    --sort-by='.lastTimestamp' 2>/dev/null \
                    || printf "No events found.\n"
            done
        fi
    } >> "${EBPF_EVENTS_FILE}" 2>&1
}

scan_ebpf_log_patterns() {
    my_banner "eBPF Agent Log Pattern Scan → $(basename "${EBPF_LOG_PATTERNS_FILE}")"

    if [[ ! -s "${EBPF_LOGS_FILE}" ]]; then
        printf "No eBPF pod logs collected — skipping pattern scan.\n" >> "${EBPF_LOG_PATTERNS_FILE}"
        return
    fi

    {
        printf "Scanning collected eBPF pod logs for known error/warning patterns...\n"
        printf "(source: %s)\n\n" "$(basename "${EBPF_LOGS_FILE}")"

        local -a patterns=(
            "WARNING: Could not obtain kernel headers"
            "kernel-devel install failed"
            "linux-headers install failed"
            "BTF data is available"
            "Kernel headers not found"
            "Kernel headers successfully installed"
            "Failed to write kernel headers path"
            "OOM|OOMKilled|killed|out of memory"
            "permission denied|Permission denied"
            "failed to load|Failed to load"
            "unable to|Unable to"
            "ERROR:|error:"
            "Cannot|cannot"
            "no space left"
            "connection refused|Connection refused"
            "unauthorized|Unauthorized"
            "certificate|tls error|TLS"
            "probe failed|kprobe|uprobe"
            "rlimit|RLIMIT_MEMLOCK|locked memory"
        )

        local found_any=false
        for pattern in "${patterns[@]}"; do
            local matches
            matches=$(grep -i -E "${pattern}" "${EBPF_LOGS_FILE}" || true)
            if [[ -n "${matches}" ]]; then
                found_any=true
                printf "=== Pattern: %s ===\n%s\n\n" "${pattern}" "${matches}"
            fi
        done

        if ! "${found_any}"; then
            printf "No known error/warning patterns found in eBPF agent logs.\n"
        fi
    } >> "${EBPF_LOG_PATTERNS_FILE}" 2>&1
}

# ── Main ──────────────────────────────────────────────────────────────────────
my_banner "nrk8s-diag.sh"
printf "Namespace:         %s\n" "${NAMESPACE}"
printf "Helm Release:      %s\n" "${RELEASE_NAME}"
printf "eBPF Release:      %s\n" "${EBPF_RELEASE_NAME}"
printf "Timestamp:         %s\n" "${TIMESTAMP}"
printf "Kube diagnostics:  %s\n" "${RUN_KUBE}"
printf "Pixie diagnostics: %s\n" "${RUN_PIXIE}"
printf "eBPF diagnostics:  %s\n" "${RUN_EBPF}"

validate_namespace

if "${RUN_KUBE}"; then
    my_banner "Starting Kubernetes Diagnostics"
    check_newrelic_connectivity
    gather_cluster_info
    gather_crds
    gather_cluster_roles
    gather_workload_status
    describe_all_resources
    retrieve_pod_logs
    gather_namespace_events
    gather_network_policies
    get_helm_values
    get_helm_history
fi

if "${RUN_PIXIE}"; then
    my_banner "Starting Pixie Diagnostics"
    if is_px_cli_available; then
        get_pixie_agent_status
        # Include any px collect-logs output in the archive
        local_pixie_logs=$(find . -maxdepth 1 -name "pixie_logs*" -newer "${MAIN_LOG_FILE}" \
            -type f 2>/dev/null | head -1 || true)
        if [[ -n "${local_pixie_logs}" ]]; then
            cp "${local_pixie_logs}" "${OUTPUT_DIR}/"
        fi
    fi
    get_pixie_key_information
    get_pixie_node_information
    get_pixie_namespaced_resources
    get_pixie_deployment_logs
    get_pixie_pod_events
fi

if "${RUN_EBPF}"; then
    my_banner "Starting eBPF Agent Diagnostics"
    gather_ebpf_daemonset_status
    gather_ebpf_node_kernel_info
    gather_ebpf_pod_logs
    describe_ebpf_resources
    get_ebpf_helm_values
    gather_ebpf_rbac
    gather_ebpf_scheduling
    gather_ebpf_events
    scan_ebpf_log_patterns  # must run after gather_ebpf_pod_logs
fi

# ── Archive ───────────────────────────────────────────────────────────────────
my_banner "Creating Archive → ${ARCHIVE_FILE}"
(
    cd "${TEMP_DIR}"
    tar -czf "${ARCHIVE_FILE}" "${ARCHIVE_NAME}"
)
rm -rf "${TEMP_DIR}"

my_banner "Done"
printf "Archive:  %s\n" "${ARCHIVE_FILE}"
printf "Please attach this file to your New Relic support ticket.\n"
