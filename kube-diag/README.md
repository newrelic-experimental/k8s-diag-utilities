# kube-diag

A simple bash script to check the health of a New Relic enabled Kubernetes cluster.

The script runs standard Kubernetes commands in the newrelic namespace and creates an output file.
The output can be helpful in troubleshooting issues.


# Usage

```
kube-diag.sh <namespace>
```

Run from instance with access to cluster. This is typically the system where you run `kubectl` or `helm` commands. The referenced namespace will typically be `newrelic`, but you may need to update it if you've installed to a different namespace.
```
curl -o kube-diag.sh -s https://raw.githubusercontent.com/newrelic-experimental/k8s-diag-utilities/main/kube-diag/kube-diag.sh
chmod +x kube-diag.sh
./kube-diag.sh newrelic
```

# Output

A file named `kube_diag_<timestamp>.tar.gz`
