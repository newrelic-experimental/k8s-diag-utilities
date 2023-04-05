# pixie-diag

A simple bash script that checks the health of a Pixie-enabled cluster.

The script runs standard Kubernetes commands in the namespace that Pixie is installed in and creates an output file.

# Optional

If you have the `px` CLI installed, make sure you are authenticated by running:

```
px auth login
px run px/cluster
```

You should see output from the cluster when running the `px run px/cluster` command.  This helps 

# Usage

Run from a terminal with `kubectl` access to cluster. The namespace will typically be either `px` or `newrelic`, depending on your installation.
```
curl -o pixie-diag.sh -s https://raw.githubusercontent.com/newrelic-experimental/pixie-utilities/main/pixie-diag/pixie-diag.sh
chmod +x pixie-diag.sh
./pixie-diag.sh newrelic
```

# Output

A file named `pixie_diag_<timestamp>.tar.gz`
