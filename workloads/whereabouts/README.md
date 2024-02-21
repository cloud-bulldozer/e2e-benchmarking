# Whereabouts Testing

The `./run.sh` script is just a small wrapper on top of kube-burner to be used as entrypoint of some of its flags. The supported workloads are described in the [kube-burner OCP wrapper docs](https://kube-burner.github.io/kube-burner-ocp/latest/).

This repo is based on the kube-burner node-density test, it has a pod annotation to configure secondary interface that is addressed by the multus ipam.

[Here is a link to the 4.14 openshift docs](https://docs.openshift.com/container-platform/4.14/networking/multiple_networks/configuring-additional-network.html#nw-multus-creating-whereabouts-reconciler-daemon-set_configuring-additional-network)

This test is configured to fill up a `/21` ip allocation. It does that by creating 341 namespaces with 6 pods per namespace for a total of 2046 pods. At 250 pods per node a cluster should have at least 9 nodes capable of hosting pods.

A note that since this test is based on node-density, the config file uses the same name as the test so that kube-burner will use the local file over the known defaults. This is most accurately described as node-densit-with-net-attach-def.



## To run the test
```shell
$ ./run.sh 
```

## Environment variables

This wrapper supports some variables to tweak some basic parameters of the workloads:

- **ES_SERVER**: Defines the ElasticSearch/OpenSearch endpoint. By default it points the development instance. Indexing can be disabled with `export ES_SERVER=""`.
- **ES_INDEX**: Defines the ElasticSearch/OpenSearch index name. By default `ripsaw-kube-burner`
- **QPS** and **BURST**: Defines client-go QPS and BURST parameters for kube-burner. 20 by default
- **GC**: Garbage collect created namespaces. true by default
- **EXTRA_FLAGS**: Extra flags that will be appended to the underlying kube-burner-ocp command, by default empty.
- **ITERATIONS**: how many 6 pods namespaces to create

### Using the EXTRA_FLAGS variable
**This variable has not been tested in this repo, runner beware**

All the flags that can be appeneded through the `EXTRA_FLAGS` variable can be found in the [kube-burner-ocp docs](https://kube-burner.github.io/kube-burner-ocp/latest/)
For example, we can tweak the churning behaviour of the cluster-density workload with:

```shell
$ export EXTRA_FLAGS="--churn-duration=1d --churn-percent=5 --churn-delay=5m"
$ ITERATIONS=500 WORKLOAD=cluster-density-v2 ./run.sh
```

Or increase the benchmark timeout (by default 3h):

```shell
$ EXTRA_FLAGS="--timeout=5h" ITERATIONS=500 WORKLOAD=cluster-density-v2 ./run.sh
```


### Cluster-density and cluster-density-v2

- **ITERATIONS**: ~Defines the number of iterations of the workload to run. No default value~ see above, iterations is initially configured at 341
- **CHURN**: Enables workload churning. Workload churning is enabled by default with `churn-duration=1h`, `churn-delay=2m` and `churn-percent=10`. These parameters can be tuned through the `EXTRA_FLAGS` variable as noted previously.

## HyperShift
This code has not been tested on hypershift but the code to run that test has not been removed so it might be posible.

