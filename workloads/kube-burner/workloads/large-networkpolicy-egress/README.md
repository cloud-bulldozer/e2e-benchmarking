
## large-networkpolicy-egress

With the help of [large-networkpolicy-egress] customer cases that combined with node-density-heavy, network policy and egress firewall

## How to run large-networkpolicy-egress tests?

The environmental variables and steps to kick off this test can be found [here](https://github.com/cloud-bulldozer/e2e-benchmarking/blob/master/workloads/kube-burner/README.md#kube-burner-e2e-benchmarks)

## What are the test cases that this workload can currently run?

### Case for large namespaces

- 2500 namespaces, ITERATION=2500, one namespace each ITERASTION, great than 50 worker node
- 30 pods in each namespace. One server pod, one client pod, one egress testing pod. specify POD_RPLICAS=10 for each type pod, default value of POD_RPLICAS is 10
- Default deny large-networkpolicy-egress is applied first that blocks traffic to any test namespace
- 100 network policies in each namespace that allows traffic from the same namespace and two other namespaces using namespace selectors,NETWORKPOLICY_RPLICAS=50, default value of NETWORKPOLICY_RPLICAS is 50
- 1 egress policy in each namespace, you can specified how many egress policy rule by EGRESS_FIREWALL_POLICY_TOTAL_NUM=80, it will create 80 rules for one policy. default value of EGRESS_FIREWALL_POLICY_TOTAL_NUM is 80
- WAIT_OVN_DB_SYNC_TIME used for specify the time that wait for OVN DB sync, the memory usage of ovn node pod will increase during the time.
### Case for small namespaces, 1 namespace per worker node

- 50 namespaces, ITERATION=50, one namespace each ITERASTION, recommend 50 worker node
- 210 pods in each namespace. One server pod, one client pod, one egress testing pod. specify POD_RPLICAS=70 for each type pod, default value of POD_RPLICAS is 10
- Default deny large-networkpolicy-egress is applied first that blocks traffic to any test namespace
- 1000 network policies in each namespace that allows traffic from the same namespace and two other namespaces using namespace selectors,NETWORKPOLICY_RPLICAS=500, default value of NETWORKPOLICY_RPLICAS is 50
- 1200 egress policy in each namespace, you can specified how many egress policy rule by EGRESS_FIREWALL_POLICY_TOTAL_NUM=1200, it will create 1200 rules for one policy. default value of EGRESS_FIREWALL_POLICY_TOTAL_NUM is 80
- WAIT_OVN_DB_SYNC_TIME used for specify the time that wait for OVN DB sync, the memory usage of ovn node pod will increase during the time.
## What is the Key Performance Indicator?

Time to enforce a large-networkpolicy-egress
