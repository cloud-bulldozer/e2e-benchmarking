
## Networkpolicy 

With the help of [networkpolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/) object we can control traffic flow at the IP address or port level in Kubernetes

## How to run networkpolicy tests?

The environmental variables and steps to kick off this test can be found [here](https://github.com/cloud-bulldozer/e2e-benchmarking/blob/master/workloads/kube-burner/README.md#kube-burner-e2e-benchmarks)

## What are the test cases that this workload can currently run?

A networkpolicy can come in various shapes and sizes. Allow traffic from a specific namespace, Deny traffic from a specific pod IP, Deny all traffic, ...
Hence we have come up with a few test cases which try to cover most of them. They are as follows.

### Case 1

- 500 namespaces
- 20 pods in each namespace. Each pod acts as a server and a client
- Default deny networkpolicy is applied first that blocks traffic to any test namespace
- 3 network policies in each namespace that allows traffic from the same namespace and two other namespaces using namespace selectors

### Case 2

- 5 namespaces
- 100 pods in each namespace. Each pod acts as a server and a client
- Each pod with 2 labels and each label shared is by 5 pods
- Default deny networkpolicy is applied first
- Then for each unique label in a namespace we have a networkpolicy with that label as a podSelector which allows traffic from pods with some other randomly selected label. This translates to 40 networkpolicies/namespace

### Case 3

- 5 namespaces
- 20 pods in each namespace. Each pod acts as a server and a client
- Each pod with 2 labels and each label shared is by 5 pods
- Default deny networkpolicy is applied first
- Then for each unique label in a namespace we have a networkpolicy with that label as a podSelector which allows traffic from pods which *don't* have some other randomly-selected label. This translates to 20 networkpolicies/namespace

## What is the Key Performance Indicator?

Time to enforce a networkpolicy
