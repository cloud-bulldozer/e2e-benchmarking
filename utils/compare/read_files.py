import graph
import json 
import os
from pathlib import Path
import sys
import os

def read_config_file(file_name):
    with open(os.path.dirname(os.path.realpath(__file__))+ "/" + file_name, "r") as f: 
        read_str = f.read()
        return json.loads(read_str)


data_func = "mean"
previous_version = os.getenv("previous_version", False)
tolerancy_num = os.getenv("tolerancy", 20)
time_frame = os.getenv("TIME_RANGE", "2 w")

# burner filter - keys + metric of interest
uuid=os.getenv("UUID",None)
if uuid is None:
    print("Please set UUID env variable")
    sys.exit(1)
uuid = uuid.strip()
meta = graph.get_metadata(uuid)
if not meta: 
    print(f"Could not find metadata in perf_scae_ci index with uuid {uuid}")
    sys.exit(1)
baseline_uuids=os.getenv("BASELINE_UUID", "")

# can add as many config files here as data points collected
if meta["benchmark"] == "k8s-netperf" :
    index = "k8s-netperf"
    k8s_json = read_config_file("configs/k8s.json")
    metrics = [k8s_json]
elif meta["benchmark"] == "ingress-perf" :
    index = "ingress-performance"
    ingress_json = read_config_file("configs/ingress.json")
    metrics = [ingress_json]
else:
    index = "ripsaw-kube-burner"

    latency_json = read_config_file("configs/podlatency.json")
    crio_json = read_config_file("configs/crio.json")
    kubelet_json = read_config_file("configs/kubelet.json")
    etcd_json = read_config_file("configs/etcd.json")
    master_json = read_config_file("configs/master_node.json")
    worker_agg_json = read_config_file("configs/worker_node.json")
    metrics = [latency_json, crio_json,etcd_json, kubelet_json,master_json]


# need to get file list
if len(baseline_uuids) > 0:
    ids=baseline_uuids.split(',')
else:
    ids=graph.get_match_runs(meta, True, previous_version, time_frame)
if uuid in ids:
    ids.remove(uuid)
if len(ids) < 1:
    print("No matching data for given configuration")
else:
    file_path_name = f"/tmp/{meta['benchmark']}-{uuid}/comparison.csv"
    if os.path.isfile(file_path_name):
        os.remove(file_path_name)
    filepath = Path(file_path_name)
    filepath.parent.mkdir(parents=True, exist_ok=True)

    write_uuid_to_csv(filepath)
    for metric in metrics:   
        data_func = metric['type']
        divider = metric['divider']
        metric_of_interest = metric['metric_of_interest']
        if "additionalColumns" in metric.keys(): 
            additional_columns = metric['additionalColumns']
        else:
            additional_columns = []

        for single_metric in metric['metrics']:
            find_metrics = single_metric

            oMetrics, nMetrics,columns = graph.process_all_data(metric_of_interest, find_metrics, uuid, ids, data_func, index, divider, additional_columns)
            # get pass fail
            returned_metrics = graph.generate_pass_fail(oMetrics, nMetrics, columns, tolerancy_num)
            print('str type' + str(type(returned_metrics)))
            if len(returned_metrics) > 0:
                returned_metrics.to_csv(filepath,mode="a", index=False)
    with open(file_path_name, "r") as f:
        final_csv_str = f.read()
        print('file path name' + str(file_path_name))
        print("final csv: \n" + str(final_csv_str))
    
    # get fail in any file, fail comparison
    if "Fail" in final_csv_str:
        sys.exit(1)
    
