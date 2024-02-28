
## large-networkpolicy-egress

With the help of [large-networkpolicy-egress] customer use cases, the test case combined with node-density-heavy, network policy and egress firewall test scenario. To simulate large scale workload in zero-trust OCP cluster, the network traffic of egress and ingress denied by default. 

## How to run large-networkpolicy-egress tests?

The environmental variables and steps to kick off this test can be found [here](https://github.com/cloud-bulldozer/e2e-benchmarking/blob/master/workloads/kube-burner/README.md#kube-burner-e2e-benchmarks)

## What are the test cases that this workload can currently run?

### Recommend settings for large namespaces

- The ITERATION set to 2000. One namespace is created for each ITERATION. For large namespace scenario,  The worker node of testing cluster is great than or equal to 100 worker nodes.
- The POD_RPLICAS=3, It will creae 3 X POD_RPLICAS Pods in each namespace. 9 pods will create in each namespace when POD_RPLICAS=3. One server pod postgres-x that run PostgreSQL DB. One client pod, the client pod perfapp-x will inject data into PostgreSQL DB continuously. one egress testing pod egress-firewall-x, it will continously ping external website and cross namespace. 
- The NETWORKPOLICY_RPLICAS=10, It will create 2 X NETWORKPOLICY_RPLICAS network policies created each namespace. in this scenario, 20 network policies in each namespace that allows traffic from the same namespace and across two namespaces using namespace selectors.
- The EGRESS_FIREWALL_POLICY_TOTAL_NUM=60, It will create 1 egress policy in each namespace, 60 egress firewall rule will be created on each egress policy. 
- The WAIT_OVN_DB_SYNC_TIME=10800, wait for 3 hours. WAIT_OVN_DB_SYNC_TIME used for specify the time that wait for OVN DB sync after creating large scale pods, network policies and egress firewall, the memory usage of ovn node pod will continueously increase during the time, to make sure the memory resource get stable. then the script will re-create some new pod/networkpolicy/egress firewall rules, then check if slow sync issue happen. 

###  Recommend settings for large namespaces small namespaces, 1 namespace per worker node
- The ITERATION set to 100. One namespace is created for each ITERATION. For small namespace scenario,  The worker node of testing cluster is 100 worker nodes. Total 100 namespace. 
- The POD_RPLICAS=50, It will creae 3 X POD_RPLICAS Pods in each namespace. 150 pods will create in each namespace when POD_RPLICAS=150. One server pod postgres-x that run PostgreSQL DB. One client pod, the client pod perfapp-x will inject data into PostgreSQL DB continuously. one egress testing pod egress-firewall-x, it will continously ping external website and cross namespace.
- The NETWORKPOLICY_RPLICAS=150, It will create 2 X NETWORKPOLICY_RPLICAS network policies created each namespace. in this scenario, 300 network policies in each namespace that allows traffic from the same namespace and across two namespaces using namespace selectors.  Total 30000 networkpolicy created.
- The EGRESS_FIREWALL_POLICY_TOTAL_NUM=1200, It will create 1 egress policy in each namespace, 1200 egress firewall rule will be created on each egress policy. Total 120k egress firewall rules created.
- The WAIT_OVN_DB_SYNC_TIME=10800, wait for 3 hours. WAIT_OVN_DB_SYNC_TIME used for specify the time that wait for OVN DB sync after creating large scale pods, network policies and egress firewall, the memory usage of ovn node pod will continueously increase during the time, to make sure the memory resource get stable. then the script will re-create some new pod/networkpolicy/egress firewall rules, then check if slow sync issue happen. 

### Default value of above VARIABLE, can be find in env.sh
POD_RPLICAS=40
NETWORKPOLICY_RPLICAS=75
EGRESS_FIREWALL_POLICY_TOTAL_NUM=80
WAIT_OVN_DB_SYNC_TIME=5400