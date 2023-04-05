# kube-diag

A simple bash script to check the health of a New Relic enabled Kubernetes cluster.

The script runs standard Kubernetes commands in the newrelic namespace and creates an output file.
The output can be helpful in troubleshooting issues.


# Usage

```
kube-diag.sh <namespace>
```

Run from instance with access to cluster. The namespace will typically be either `px` or `newrelic`, depending on your installation.
```
curl -o kube-diag.sh -s https://raw.githubusercontent.com/newrelic-experimental/pixie-utilities/main/kube-diag/kube-diag.sh
chmod +x kube-diag.sh
./kube-diag.sh newrelic
```

# Output

A file named `kube_diag_<timestamp>.tar.gz`