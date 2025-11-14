#!/bin/env bash

# nrk8s-diag.sh assists in troubleshooting Kubernetes clusters and New Relic Kubernetes integration installations.
# This is an enhanced version to gather more comprehensive diagnostic data.
# Exits immediately if a command exits with a non-zero status, treats unset variables as an error, and prevents errors in a pipeline from being masked.

set -euo pipefail
IFS=$'\n\t'

# Initialize variables
NAMESPACE=""
RELEASE_NAME="newrelic-bundle" # Default Helm release name
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
ARCHIVE_NAME="nrk8s_diag_$TIMESTAMP"
ARCHIVE_FILE="$PWD/${ARCHIVE_NAME}.tar.gz"

# Function to display usage
usage() {
    echo "Usage: $0 -n NAMESPACE [-r RELEASE_NAME]"
    echo "  -n NAMESPACE       (Required) The namespace where New Relic is installed."
    echo "  -r RELEASE_NAME    (Optional) The Helm release name. (Default: newrelic-bundle)"
    exit 1
}

# Parse command-line options
while getopts ":n:r:" opt; do
    case "${opt}" in
        n)
            NAMESPACE="${OPTARG}"
            ;;
        r)
            RELEASE_NAME="${OPTARG}"
            ;;
        *)
            usage
            ;;
    esac
done

# Check if namespace is provided
if [[ -z "${NAMESPACE}" ]]; then
    echo "Error: Namespace (-n) is required."
    usage
fi

# Create a temporary directory to store output files
TEMP_DIR=$(mktemp -d)
OUTPUT_DIR="$TEMP_DIR/$ARCHIVE_NAME"
mkdir -p "$OUTPUT_DIR"

# Define file paths within the output directory
MAIN_LOG_FILE="$OUTPUT_DIR/00_nrk8s_diag_$TIMESTAMP.log"
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

# Redirect script output to the main log file
exec > >(tee -a "$MAIN_LOG_FILE") 2>&1

# Start of Main Log File
echo -e "\n*****************************************************\n"
echo -e "Kubernetes Diagnostics for Namespace: ${NAMESPACE}"
echo -e "Helm Release: ${RELEASE_NAME}"
echo -e "Timestamp: ${TIMESTAMP}"
echo -e "*****************************************************\n"

# Function to check connectivity to New Relic endpoints
check_newrelic_connectivity() {
    echo -e "\n*****************************************************\n"
    echo -e "Checking connectivity to New Relic Endpoints"
    echo -e "*****************************************************\n"

    endpoints=(
        "https://metric-api.newrelic.com/stat/v1"
        "https://metric-api.eu.newrelic.com/stat/v1"
        "https://log-api.newrelic.com/log/v1"
        "https://log-api.eu.newrelic.com/log/v1"
    )

    for endpoint in "${endpoints[@]}"; do
        echo -e "\nChecking endpoint: $endpoint"
        # Run a temporary pod to check connectivity.
        # Use --timeout to avoid hanging, and capture http_code.
        HTTP_STATUS=$(kubectl run nr-diag-connectivity-$$ \
            --image=curlimages/curl \
            --rm \
            --restart=Never \
            --attach \
            --quiet \
            --command -- sh -c "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 $endpoint") || echo "Connectivity check pod failed"

        echo "Endpoint: $endpoint -> HTTP Status: $HTTP_STATUS"
    done
}

# Function to gather key cluster information
gather_cluster_info() {
    echo -e "\n*****************************************************\n"
    echo -e "Gathering Cluster Information"
    echo -e "Output will be saved to: $CLUSTER_INFO_FILE"
    echo -e "*****************************************************\n"

    {
        echo "Cluster Name: $(kubectl config current-context)"

        echo -e "\nKubectl Version:"
        kubectl version --client

        echo -e "\nKubernetes Version:"
        kubectl version --short || kubectl version

        echo -e "\nCluster Info:"
        kubectl cluster-info

        echo -e "\nCluster Nodes:"
        kubectl get nodes -o wide

        echo -e "\nNode Count: $(kubectl get nodes --no-headers | wc -l)"

        echo -e "\nNode Capacity:"
        kubectl get nodes -o jsonpath="{range .items[*]}Name: {.metadata.name}, CPU: {.status.capacity.cpu}, Memory: {.status.capacity.memory}\n{end}"

        echo -e "\nStorage Classes:"
        kubectl get storageclass

        echo -e "\nNode Resource Usage (Top Nodes):"
        kubectl top nodes || echo "Metrics (top) not available. Is the metrics-server running?"

    } >> "$CLUSTER_INFO_FILE" 2>&1
}

# Function to gather New Relic related CRDs
gather_crds() {
    echo -e "\n*****************************************************\n"
    echo -e "Gathering New Relic Custom Resource Definitions (CRDs)"
    echo -e "Output will be saved to: $CRD_FILE"
    echo -e "*****************************************************\n"

    {
        echo -e "Listing CRDs matching 'newrelic' or 'nri':\n"
        kubectl get crds | grep -i -E 'newrelic|nri' || echo "No New Relic CRDs found."
    } >> "$CRD_FILE" 2>&1
}

# Function to gather New Relic related ClusterRoles and ClusterRoleBindings
gather_cluster_roles() {
    echo -e "\n*****************************************************\n"
    echo -e "Gathering New Relic ClusterRoles and ClusterRoleBindings"
    echo -e "Output will be saved to: $CLUSTER_ROLE_FILE"
    echo -e "*****************************************************\n"

    {
        echo -e "Listing ClusterRoles matching 'newrelic' or 'nri':\n"
        kubectl get clusterrole -o wide | grep -i -E 'newrelic|nri' || echo "No New Relic ClusterRoles found."

        echo -e "\nListing ClusterRoleBindings matching 'newrelic' or 'nri':\n"
        kubectl get clusterrolebinding -o wide | grep -i -E 'newrelic|nri' || echo "No New Relic ClusterRoleBindings found."
    } >> "$CLUSTER_ROLE_FILE" 2>&1
}

# Function to gather workload status (Pods, Deployments, DaemonSets, etc.)
gather_workload_status() {
    echo -e "\n*****************************************************\n"
    echo -e "Gathering Workload Status for Namespace '${NAMESPACE}'"
    echo -e "Output will be saved to: $WORKLOAD_STATUS_FILE"
    echo -e "*****************************************************\n"

    {
        echo -e "Listing Deployments, DaemonSets, StatefulSets, Jobs:\n"
        kubectl get deployment,daemonset,statefulset,job,cronjob -n "$NAMESPACE" -o wide

        echo -e "\nListing Pods (All):"
        kubectl get pods -n "$NAMESPACE" -o wide

        echo -e "\nListing Pods with non-Running/Succeeded status:"
        kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running,status.phase!=Succeeded || echo "All pods are Running or Succeeded."

        echo -e "\nPod Resource Usage (Top Pods):"
        kubectl top pods -n "$NAMESPACE" || echo "Metrics (top) not available for pods in this namespace."

    } >> "$WORKLOAD_STATUS_FILE" 2>&1
}

# Function to describe all resources in the namespace, excluding 'events'
describe_all_resources() {
    echo -e "\n*****************************************************\n"
    echo -e "Describing All Resources in Namespace '${NAMESPACE}' (excluding 'events')"
    echo -e "Output will be saved to: $DESCRIBE_LOG_FILE"
    echo -e "*****************************************************\n"

    {
        echo -e "Describing All Resources in Namespace '${NAMESPACE}' (excluding 'events')\n"

        # Get all namespaced resource types, excluding 'events'
        resource_types=$(kubectl api-resources --namespaced=true -o name | grep -v "^events$" | sort | uniq)

        for resource in $resource_types; do
            echo -e "\nProcessing Resource Type: $resource"
            names=$(kubectl get "$resource" -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name") || continue

            if [[ -z "$names" ]]; then
                echo "No resources of type '$resource' found."
                continue
            fi

            for name in $names; do
                echo -e "\nDescribing $resource/$name in Namespace '$NAMESPACE'"
                kubectl describe "$resource" "$name" -n "$NAMESPACE"
            done
        done
    } >> "$DESCRIBE_LOG_FILE" 2>&1
}

# Function to retrieve logs for all pods and containers in the namespace
retrieve_pod_logs() {
    echo -e "\n*****************************************************\n"
    echo -e "Retrieving Logs for All Pods in Namespace '${NAMESPACE}'"
    echo -e "Output will be saved to: $POD_LOGS_FILE"
    echo -e "*****************************************************\n"

    {
        echo -e "Retrieving Logs for All Pods in Namespace '${NAMESPACE}'\n"
        pods=$(kubectl get pods -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name")

        if [[ -z "$pods" ]]; then
            echo "No pods found in namespace '$NAMESPACE'."
            return
        fi

        for pod in $pods; do
            # Get all containers (including init containers) in the current pod
            containers=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{range .spec.initContainers[*]}{.name} {end}{range .spec.containers[*]}{.name} {end}')
            IFS=' ' read -r -a container_array <<< "$containers"

            for container in "${container_array[@]}"; do
                echo -e "\n====================================================="
                echo -e "Fetching CURRENT Logs: Pod '$pod', Container '$container'"
                echo -e "====================================================="
                kubectl logs "$pod" -c "$container" -n "$NAMESPACE" --tail=1000 || echo "No CURRENT logs found for $pod/$container."

                echo -e "\n====================================================="
                echo -e "Fetching PREVIOUS Logs: Pod '$pod', Container '$container'"
                echo -e "====================================================="
                kubectl logs --previous "$pod" -c "$container" -n "$NAMESPACE" --tail=1000 || echo "No PREVIOUS logs found for $pod/$container (this is normal if it hasn't restarted)."
            done
        done
    } >> "$POD_LOGS_FILE" 2>&1
}

# Function to gather events for the namespace
gather_namespace_events() {
    echo -e "\n*****************************************************\n"
    echo -e "Gathering Events for Namespace '${NAMESPACE}'"
    echo -e "Output will be saved to: $EVENTS_FILE"
    echo -e "*****************************************************\n"

    {
        echo -e "Gathering all events in namespace '${NAMESPACE}', sorted by last timestamp:\n"
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp'
    } >> "$EVENTS_FILE" 2>&1
}

# Function to gather NetworkPolicies in the namespace
gather_network_policies() {
    echo -e "\n*****************************************************\n"
    echo -e "Gathering NetworkPolicies in Namespace '${NAMESPACE}'"
    echo -e "Output will be saved to: $NETPOL_FILE"
    echo -e "*****************************************************\n"

    {
        echo -e "Gathering NetworkPolicies (in YAML format) in namespace '${NAMESPACE}':\n"
        kubectl get networkpolicy -n "$NAMESPACE" -o yaml || echo "No NetworkPolicies found or error retrieving them."
    } >> "$NETPOL_FILE" 2>&1
}

# Function to get Helm values and save to a file
get_helm_values() {
    echo -e "\n*****************************************************\n"
    echo -e "Retrieving Helm values for release '${RELEASE_NAME}' in namespace '${NAMESPACE}'"
    echo -e "Output will be saved to: $HELM_VALUES_FILE"
    echo -e "*****************************************************\n"

    helm get values --all -n "$NAMESPACE" "$RELEASE_NAME" > "$HELM_VALUES_FILE" || {
        echo "Failed to retrieve Helm values. Please ensure Helm is installed and the release '${RELEASE_NAME}' exists in namespace '${NAMESPACE}'."
        echo "If your release name is different, please re-run with: -r YOUR_RELEASE_NAME"
    }
}

# Function to get Helm history
get_helm_history() {
    echo -e "\n*****************************************************\n"
    echo -e "Retrieving Helm history for release '${RELEASE_NAME}' in namespace '${NAMESPACE}'"
    echo -e "Output will be saved to: $HELM_HISTORY_FILE"
    echo -e "*****************************************************\n"

    helm history -n "$NAMESPACE" "$RELEASE_NAME" > "$HELM_HISTORY_FILE" || {
        echo "Failed to retrieve Helm history for release '${RELEASE_NAME}'."
    }
}

# Main Execution Flow
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

# Combine all files into one compressed archive
echo -e "\n*****************************************************\n"
echo -e "Creating compressed archive of diagnostic files."
echo -e "Archive File: $ARCHIVE_FILE"
echo -e "*****************************************************\n"

# Change to the temporary directory to avoid including full paths
(
    cd "$TEMP_DIR"
    tar -czf "$ARCHIVE_FILE" "$ARCHIVE_NAME"
)

# Clean up temporary directory
rm -rf "$TEMP_DIR"

echo -e "\n*****************************************************\n"
echo -e "Diagnostic archive has been created:"
echo -e "$ARCHIVE_FILE"
echo -e "Please upload this file to your New Relic support ticket."
echo -e "*****************************************************\n"
echo "End of nrk8s-diag"