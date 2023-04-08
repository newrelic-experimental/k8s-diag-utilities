#!/bin/bash

# kube-diag.sh assists in troubleshooting Kubernetes clusters and New Relic Kubernetes integration installations.
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
CLUSTER_NAME=$(kubectl config current-context)
echo "Cluster name: $CLUSTER_NAME"

# Get kubectl version
echo "Kubectl version:"
kubectl version

# Detect K8s Cluster 'flavor'
KUBE_FLAVOR=""
if kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "eks.amazonaws.com"
then
    KUBE_FLAVOR="EKS"
elif kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "kubernetes.azure.com"
then
    KUBE_FLAVOR="AKS"
elif kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "cloud.google.com"
then
    KUBE_FLAVOR="GKE"
elif kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "minikube.k8s.io"
then
    KUBE_FLAVOR="Minikube"
elif kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "container.oracle.com/managed=true"
then
    KUBE_FLAVOR="OKE"
elif kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "node-role.kubernetes.io/master"
then
    if kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "beta.kubernetes.io/os=linux"
    then
        KUBE_FLAVOR="OpenShift"
    fi
elif kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "kops.k8s.io"
then
    KUBE_FLAVOR="kOps"
else
    KUBE_FLAVOR="Self-hosted"
fi

echo "Kubernetes cluster flavor: $KUBE_FLAVOR"

nodes=$(kubectl get nodes | awk '{print $1}' | tail -n +2)

# check node count
nodecount=$(kubectl get nodes --selector=kubernetes.io/hostname!=node_host_name | tail -n +2 | wc -l)
echo "Cluster has "$nodecount" nodes"

if [ $nodecount -gt 100 ]
  then
    echo "Node limit is greater than 100"
fi

# check node memory capacity
MEMORY=$(kubectl get nodes -o jsonpath='{.items[0].status.capacity.memory}' | sed 's/Ki$//')
echo "MEMORY=$MEMORY"
if [[ "$MEMORY" -lt 7950912 ]]; then
echo "Node with less than 8 Gb of memory, got ${MEMORY}."
fi

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

# Check Allocated resources Available/Consumed
echo -e "\n*****************************************************\n"
echo -e "Checking Allocated resources Available/Consumed\n"
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
      ns=$namespace
      
      echo -e "\n*****************************************************\n"
      echo -e "Logs from $deployment_name\n"
      echo -e "*****************************************************\n"
      kubectl logs --tail=50 deployments/$deployment_name -n $ns
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

gzip -9 -c kube_diag_$timestamp.log > kube_diag_$timestamp.log.gzip

echo -e "\n*****************************************************\n"
echo -e "File created = kube_diag_<timestamp>.log\n"
echo -e "File created = kube_diag_<timestamp>.log.gzip\n"
echo -e "*****************************************************\n"
echo "End kube-diag"
