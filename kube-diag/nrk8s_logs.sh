#!/bin/bash

function get_newrelic_resources_info() {
  local ns="$1"

  # Get the list of pods
  nrk8s_pods=$(kubectl get pods -n "$ns" -o jsonpath='{.items[*].metadata.name}')

  # Loop through the pods
  for pod in $nrk8s_pods; do
    echo -e "\n*****************************************************\n"
    echo -e "Describe and logs for pod: $pod\n"
    echo -e "*****************************************************\n"
    
    # Describe the pod
    kubectl describe pod "$pod" -n "$ns"

    # Get container names in the pod
    containers=$(kubectl get pods "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].name}')

    # Loop through the containers and print logs
    for container in $containers; do
      echo -e "\nLogs from container: $container\n"
      kubectl logs --tail=50 "$pod" -c "$container" -n "$ns"
    done

    echo -e "\n*****************************************************\n"
    echo -e "Events for pod: $pod\n"
    echo -e "*****************************************************\n"

    # Get events for the pod
    kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -i "$pod"
  done

  # Describe daemonsets
  echo -e "\n*****************************************************\n"
  echo -e "Describe daemonsets in namespace: $ns\n"
  echo -e "*****************************************************\n"
  kubectl describe daemonsets -n "$ns"

  # Describe deployments
  echo -e "\n*****************************************************\n"
  echo -e "Describe deployments in namespace: $ns\n"
  echo -e "*****************************************************\n"
  kubectl describe deployments -n "$ns"
}

# Check if the namespace argument is provided
if [ -z "$1" ]; then
  echo "No namespace passed"
  echo "usage: $0 <namespace>"
  exit 0
fi

namespace="$1"

# Create a log file
timestamp=$(date +"%Y%m%d%H%M%S")
logfile="nrk8s_$timestamp.log"
exec > >(tee -a "$logfile") 2>&1

# Call the function with the provided namespace
get_newrelic_resources_info "$namespace"

# Compress the log file
gzip -9 -c "$logfile" > "${logfile}.gzip"

echo -e "\n*****************************************************\n"
echo -e "File created = $logfile\n"
echo -e "File created = ${logfile}.gzip\n"
echo -e "*****************************************************\n"
