#!/bin/bash

# kube-diag.sh assists in troubleshooting Kubernetes clusters and New Relic Kubernetes integration inamespacetallationamespace.
# Based on pixie-diag.sh by pixie-diag authors (https://github.com/wreckedred/pixie-diag)

# check for namespace
if [ -z "$1" ]
  then
    echo "No namespace passed"
    echo "usage: kube-diag.sh <namespace>"
    exit 0
fi

# Timestamp
timestamp=$(date +"%Y%m%d%H%M%S")

# namespace variable
namespace=$1

# Create a log file
exec > >(tee -a "$PWD/kube_diag_$timestamp.log") 2>&1

# Check connectivity to New Relic endpoint
echo -e "\n*****************************************************\n"
echo -e "Checking connectivity to New Relic Endpoint\n"
echo -e "*****************************************************\n"

kubectl run -i --tty --rm kube-diag --image=curlimages/curl --restart=Never -- https://metric-api.newrelic.com -vvv

# Check HELM releases
echo -e "\n*****************************************************\n"
echo -e "Checking HELM releases\n"
echo -e "*****************************************************\n"

helm list -A -n $namespace

# Check System Info
echo -e "\n*****************************************************\n"
echo -e "Key Information\n"
echo -e "*****************************************************\n"

# Get Cluster name
cluster_name=$(kubectl config current-context)
echo "Cluster name: $cluster_name"

# Get kubectl version
echo "Kubectl version:"
kubectl version

# Detect K8s Cluster 'flavor'
kube_flavor=""
if kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "eks.amazonaws.com"
then
    kube_flavor="EKS"
elif kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "kubernetes.azure.com"
then
    kube_flavor="AKS"
elif kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "cloud.google.com"
then
    kube_flavor="GKE"
elif kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "minikube.k8s.io"
then
    kube_flavor="Minikube"
elif kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "container.oracle.com/managed=true"
then
    kube_flavor="OKE"
elif kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "node-role.kubernetes.io/master"
then
    if kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "beta.kubernetes.io/os=linux"
    then
        kube_flavor="Openamespacehift"
    fi
elif kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "kops.k8s.io"
then
    kube_flavor="kOps"
else
    kube_flavor="Self-hosted"
fi

echo "Kubernetes cluster flavor: $kube_flavor"

nodes=$(kubectl get nodes | awk '{print $1}' | tail -n +2)

# check node count
nodecount=$(kubectl get nodes --selector=kubernetes.io/hostname!=node_host_name | tail -n +2 | wc -l)
echo "Cluster has "$nodecount" nodes"

if [ $nodecount -gt 100 ]
  then
    echo "Node limit is greater than 100"
fi

# check node memory capacity
memory=$(kubectl get nodes -o jsonpath='{.items[0].status.capacity.memory}' | sed 's/Ki$//')
echo "Memory=$memory"
if [[ "$memory" -lt 7950912 ]]; then
echo "Node with less than 8 Gb of memory, got ${memory}."
fi

# Get basic pod, deployment, and daemonamespaceet information in the specified namespace
echo "Pods in namespace $namespace:"
kubectl get pods -o wide -n $namespace

echo "Deployments in namespace $namespace:"
kubectl get deployments -o wide -n $namespace

echo "Daemonamespaceets in namespace $namespace:"
kubectl get daemonamespaceets -o wide -n $namespace

# pods not running
podsnr=$(kubectl get pods -n newrelic | grep -v Running | tail -n +2 | awk '{print $1}')

# count of pods not running
podsnrc=$(printf '%s\n' $podsnr | wc -l)

if [ $podsnrc -gt 0 ]
  then
    echo "There are $podsnrc pods not running!"
    echo "These pods are not running"
    printf '%s\n' $podsnr
fi

echo -e "\n*****************************************************\n"
echo -e "Node Information\n"
echo -e "*****************************************************\n"

for node_name in $nodes
  do
    # Get K8s version and Kernel from nodes
    echo ""
    echo "System Info from $node_name"
    kubectl describe node $node_name | grep -i 'Kernel Version\|OS Image\|Operating System\|Architecture\|Container Runtime Version\|Kubelet Version'
    done

# Check Allocated resources Available/Conamespaceumed
echo -e "\n*****************************************************\n"
echo -e "Checking Allocated resources Available/Conamespaceumed\n"
echo -e "*****************************************************\n"

for node_name in $nodes
  do
    # Get Allocated resources from nodes
    echo ""
    echo "Node Allocated resources info from $node_name"
    kubectl describe node $node_name | grep "Allocated resources" -A 9
  done

# Get kubectl describe node output for 3 nodes
echo -e "\n*****************************************************\n"
echo -e "Collecting Node Detail (limited to 3 nodes)\n"
echo -e "*****************************************************\n"

nodedetailcounter=0
for node_name in $nodes
  do
    if [ $nodedetailcounter -lt 3 ]
    then
      # Get node detail from a sampling of nodes
      echo -e "\nCollecting node detail from $node_name"
      kubectl describe node $node_name
      let "nodedetailcounter+=1"
    else
      break
    fi
  done

#Get all Kubernetes resources in namespace

echo -e "\n*****************************************************\n"
echo -e "Check all Kubernetes resources in namespace\n"
echo -e "*****************************************************\n"

# Get all api-resources in namespace
for i in $(kubectl api-resources --verbs=list -o name | grep -v "events.events.k8s.io" | grep -v "events" | sort | uniq);
do
  echo -e "\nResource:" $i;
  # An array of important namespace resources
  array=("configmaps" "rolebindings.rbac.authorization.k8s.io" "endpoints" "secrets" "networkpolicies" "serviceaccounts" "pods" "endpointslices" "deployments.apps" "horizontalpodautoscalers" "ingresses" "networkpolicies")
  str=$'resources\n=================='
  echo -e "\n $namespace $str"
  kubectl -n $namespace get --ignore-not-found ${i};
done

nr_deployments=$(kubectl get deployments -n $namespace | awk '{print $1}' | tail -n +2)

function get_newrelic_resources_info() {
  local namespace="$1"

  # Get the list of pods
  nrk8s_pods=$(kubectl get pods -n "$namespace" -o jsonpath='{.items[*].metadata.name}')

  # Loop through the pods
  for pod in $nrk8s_pods; do
    echo -e "\n*****************************************************\n"
    echo -e "Describe and logs for pod: $pod\n"
    echo -e "*****************************************************\n"

    # Describe the pod
    kubectl describe pod "$pod" -n "$namespace"

    # Get container names in the pod
    containers=$(kubectl get pods "$pod" -n "$namespace" -o jsonpath='{.spec.containers[*].name}')

    # Loop through the containers and print logs
    for container in $containers; do
      echo -e "\nLogs from container: $container\n"
      kubectl logs --tail=50 "$pod" -c "$container" -n "$namespace"
    done

    echo -e "\n*****************************************************\n"
    echo -e "Events for pod: $pod\n"
    echo -e "*****************************************************\n"

    # Get events for the pod
    kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -i "$pod"
  done

  # Describe daemonamespaceets
  echo -e "\n*****************************************************\n"
  echo -e "Describe daemonamespaceets in namespace: $namespace\n"
  echo -e "*****************************************************\n"
  kubectl describe daemonamespaceets -n "$namespace"

  # Describe deployments
  echo -e "\n*****************************************************\n"
  echo -e "Describe deployments in namespace: $namespace\n"
  echo -e "*****************************************************\n"
  kubectl describe deployments -n "$namespace"
}

for deployment_name in $nr_deployments
  do
    # Get logs from deployments
    if [[ $deployment_name =~ ^.*nri-kube-events.*$ ]];
    then
      echo -e "\n*****************************************************\n"
      echo -e "Logs from $deployment_name container: kube-events\n"
      echo -e "*****************************************************\n"
      kubectl logs --tail=50 deployments/$deployment_name -c kube-events -n $namespace
      echo -e "\n*****************************************************\n"
      echo -e "Logs from $deployment_name container: forwarder\n"
      echo -e "*****************************************************\n"
      kubectl logs --tail=50 deployments/$deployment_name -c forwarder -n $namespace
    else
      namespace=$namespace

      echo -e "\n*****************************************************\n"
      echo -e "Logs from $deployment_name\n"
      echo -e "*****************************************************\n"
      kubectl logs --tail=50 deployments/$deployment_name -n $namespace
    fi
  done

echo -e "\n*****************************************************\n"
echo -e "Checking pod events\n"
echo -e "*****************************************************\n"

pods=$(kubectl get pods -n $namespace | awk '{print $1}' | tail -n +2)

for pod_name in $pods
  do
    # Get events from pods in New Relic namespace
    echo ""
    echo "Events from pod name $pod_name"
    kubectl get events --all-namespaces --sort-by='.lastTimestamp'  | grep -i $pod_name
    done

echo -e "\n*****************************************************\n"
echo -e "Checking ReplicaSets in namespace $namespace\n"
echo -e "*****************************************************\n"

kubectl get replicasets -n $namespace

echo -e "\n*****************************************************\n"
echo -e "Checking resource quotas in namespace $namespace\n"
echo -e "*****************************************************\n"

kubectl get resourcequota -n $namespace

echo -e "\n*****************************************************\n"
echo -e "Checking services in namespace $namespace\n"
echo -e "*****************************************************\n"

kubectl get services -n $namespace

echo -e "\n*****************************************************\n"
echo -e "Checking stateful sets in namespace $namespace\n"
echo -e "*****************************************************\n"

kubectl get statefulsets -n $namespace

echo -e "\n*****************************************************\n"
echo -e "Checking persistent volumes and claims in namespace $namespace\n"
echo -e "*****************************************************\n"

kubectl get pv,pvc -n $namespace

gzip -9 -c kube_diag_$timestamp.log > kube_diag_$timestamp.log.gzip

echo -e "\n*****************************************************\n"
echo -e "File created = kube_diag_<timestamp>.log\n"
echo -e "File created = kube_diag_<timestamp>.log.gzip\n"
echo -e "*****************************************************\n"
echo "End kube-diag"
