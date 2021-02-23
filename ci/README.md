
## CI command to run all tests:
```
$ ./ci/run_ci.sh 
```
## CI command to run selected tests: 
```
$ ./ci/run_ci.sh workload1:script_name workload2:script_name2 eg:(./ci/run_ci.sh kube-burner:run_nodedensity_test_fromgit.sh)
```
## Environment variables

### KUBECONFIG_PATH
Default: `$HOME/.kube/config`
Path to the kubeconfig to get access to the OpenShift cluster.
