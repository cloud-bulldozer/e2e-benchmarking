# Compare 

Be able to compare a current runs data with all previous runs data based on matching: 

* benchmark type
* Worker node type
* Master node type
* network type
* Platform
* Version 
* Only Successful jobs

## Enviornent variables set

* previous_version: Set to False by default, can compare with previous version 
* tolerancy_num: Set to 20 be default, meaning if current uuid is worse than aggregated data by 20%, Negative values mean uuid/current run is better 
* UUID: current UUID to use as comparison against

## Steps: 
* Get metadata of current run using enviornment variable UUID and matching data points above
* * Get data from: index=perf_scale_ci
* For all matching uuids get aggregated data points based on metrics specified in configs
* Combine current uuid data with aggregated comparison uuid data
* Generate percentage difference in those data points
* Based on tolerancy enviornment variable, decide to pass or fail each of the comparison points


## Output
<metrics_from_config_file>,<additionalColumns_from_config_file>,
<comparison_uuids>_value,<uuid>_value,% difference,result


Ingress example output
```
uuid - value_y: 833d28b4-23ad-481a-bbce-7d0735f14fef
comparison ids - value_x: ['perfscale-cpt-84173e88-bbe6-4e97-9a88-cde0b12b693b', 'f5544cff-b022-43b8-8918-965d987b6c44', 'CPT-d2581a63-b46b-48bc-a298-53cfee346bf7', 'e9cb2f03-4bdd-468d-9940-6dd7150f2cf3', '6297dffe-0987-4614-8858-2806926571a4', 'fda3af38-7181-4d03-ac38-e32a7d7e1dfb', '80ec50dd-6ef8-4b76-a614-3525cae5ebac', '96c6b369-cf90-409f-ba51-5f852665d89a']
,config.termination,sample,config.serverReplicas,config.connections,config.concurrency,total_avg_rps_x,total_avg_rps_y,difference,result
0,edge,1,45,200,18,91824.4242857143,93677.84999999999,2.0184452325219038,Pass
1,edge,2,45,200,18,92859.28428571428,97639.56999999998,5.147881281937794,Pass
2,http,1,45,200,18,137532.44142857144,143860.77000000002,4.6013351509616385,Pass
3,http,2,45,200,18,138334.88571428572,144228.68000000002,4.260526370685147,Pass
4,passthrough,1,45,200,18,212393.5,232025.31000000003,9.243131263433213,Pass
5,passthrough,2,45,200,18,215646.17142857146,261904.77000000002,21.45115689510435,Fail
6,reencrypt,1,45,200,18,77213.55428571429,82293.16,6.578645111309855,Pass
7,reencrypt,2,45,200,18,76440.35285714285,82400.04000000001,7.79651966546393,Pass
```


## How to Run

```
pip3 install -r utils/compare/requirements.txt
export UUID=<uuid>
export ES_USERNAME=<es_username>
export ES_PASSWORD=<es_password>

python3 utils/compare/read_files.py
```


### Optional BASELINE_UUID

If you know what uuid or set of uuids you want to compare to set the enviornment variable BASELINE_UUID with a comma separated string list

## Network Perf V2

Config file: "configs/k8s.json
Index = "k8s-netperf"

## Ingress Perf
index = "ingress-performance"
Config file: configs/ingress.json

## Kube Burner 

index = "ripsaw-kube-burner"

* configs/podlatency.json
* configs/crio.json
* configs/kubelet.json
* configs/etcd.json
* configs/master_node.json
* configs/worker_node.json*

## Defining new config

Each config is a json file consisting of 
* metrics: A list of dictionairies each contiaining a list of the key values you want to compare upon (can use regex on some values, depends on set up in elasticsearch). Multiple items in this list will still use the same below fields with every search in addition to the key/values set in the dictionary
* additionalColumns: List of keys that you want to have in your results table, this can be used for only combining certain metrics. For example. if I set "samples" in the additionalColumns the data wont combine/aggregate different samples, it'll give me separate rows for each different sample type 
* metric_of_interest: the main metric value you want to compare data with 
* divider: if you want to divide all metric of interests by a certain value
* type: avg or max; type of value you want the metric of interest to be



## Continue to add

* Comparison among self managed and managed
* Comparison with only 1 most recent result
* Be able to trend results over time 
* Fips, etcd, private (etcd) metric comparisons