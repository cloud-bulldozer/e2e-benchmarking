#!/usr/bin/env python3

import os
import datetime
import subprocess
import elasticsearch
import csv
import numpy
import argparse
import json
import ssl
import urllib3

urllib3.disable_warnings()

# Environment vars
es_server = os.getenv("ES_SERVER")
es_index = os.getenv("ES_INDEX")
uuid = os.getenv("UUID")
host_network = os.getenv("HOST_NETWORK", "")
number_of_routers = os.getenv("NUMBER_OF_ROUTERS", "")
cluster_id = os.getenv("CLUSTER_ID", "")
cluster_name = os.getenv("CLUSTER_NAME", "")
openshift_version = os.getenv("OPENSHIFT_VERSION", "")
kubernetes_version = os.getenv("KUBERNETES_VERSION", "")
network_type = os.getenv("CLUSTER_NETWORK_TYPE", "")
platform_status = os.getenv("PLATFORM_STATUS", "{}")


def index_result(payload, retry_count=3):
    print(f"Indexing documents in {es_index}")
    while retry_count > 0:
        try:
            ssl_ctx = ssl.create_default_context()
            ssl_ctx.check_hostname = False
            ssl_ctx.verify_mode = ssl.CERT_NONE
            es = elasticsearch.Elasticsearch([es_server], send_get_body_as='POST',
                                             ssl_context=ssl_ctx, use_ssl=True)
            es.index(index=es_index, body=payload)
            retry_count = 0
        except Exception as e:
            print("Failed Indexing - \n" + str(e.message))
            print("Retrying again to index...")
            retry_count -= 1


def run_mb(mb_config, runtime, output):
    result_codes = {}
    latency_list = []
    cmd = f"mb -i {mb_config} -d {runtime} -o {output}"
    print(f"Executing '{cmd}'")
    result = subprocess.run(cmd,
                            shell=True,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                            timeout=int(runtime) * 5)
    if result.returncode:
        print("mb execution error:")
        print(result.stderr.decode("utf-8"))
        exit(1)
    results_csv = csv.reader(open(output))
    for hit in results_csv:
        if hit[2] not in result_codes:
            result_codes[hit[2]] = 0
        result_codes[hit[2]] += 1
        # Record latency of 'SUCCESS' 200 OK response only
        if hit[2] == "200":
            latency_list.append(int(hit[1]))
    if latency_list:
        p95_latency = numpy.percentile(latency_list, 95)
        p99_latency = numpy.percentile(latency_list, 99)
        avg_latency = numpy.average(latency_list)
        return result_codes, p95_latency, p99_latency, avg_latency
    else:
        print("Warning: Empty latency result list, returning 0")
        return result_codes, 0, 0, 0

def get_cluster_platform():
    platform = "N/A"
    try:
        platform_status_json = json.loads(platform_status)
    except json.decoder.JSONDecodeError:
        print("Warning: error decoding", platform_status)
        return platform
    if "type" in platform_status_json:
        platform = platform_status_json["type"]
        if platform == "AWS":
            if "aws" in platform_status_json:
                aws_data = platform_status_json["aws"]
                if "resourceTags" in aws_data:
                    for tag in aws_data["resourceTags"]:
                        if tag["key"] == "red-hat-clustertype":
                            platform = tag["value"].upper()
    return platform

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mb-config", required=True)
    parser.add_argument("--termination", required=True)
    parser.add_argument("--runtime", required=True, type=int)
    parser.add_argument("--output", required=True)
    parser.add_argument("--sample", required=True)
    args = parser.parse_args()
    mb_config = json.load(open(args.mb_config, "r"))
    timestamp = datetime.datetime.utcnow()
    result_codes, p95_latency, p99_latency, avg_latency = run_mb(args.mb_config, args.runtime, args.output)
    requests_per_second = result_codes.get("200", 0) / args.runtime
    payload = {"termination": args.termination,
               "test_type": args.termination,
               "uuid": uuid,
               "cluster.id": cluster_id,
               "cluster.name": cluster_name,
               "cluster.ocp_version": openshift_version,
               "cluster.kubernetes_version": kubernetes_version,
               "cluster.sdn": network_type,
               "cluster.platform": get_cluster_platform(),
               "requests_per_second": int(requests_per_second),
               "avg_latency": int(avg_latency),
               "latency_95pctl": int(p95_latency),
               "latency_99pctl": int(p99_latency),
               "host_network": host_network,
               "sample": args.sample,
               "runtime": args.runtime,
               "routes": len(mb_config),
               "conn_per_targetroute": mb_config[0]["clients"],
               "keepalive": mb_config[0]["keep-alive-requests"],
               "tls_reuse": mb_config[0]["tls-session-reuse"],
               "number_of_routers": number_of_routers}
    payload.update(result_codes)
    print("Workload finished, results:")
    print(json.dumps(payload, indent=4))
    if es_server != "":
        payload["timestamp"] = timestamp
        index_result(payload)


if __name__ == '__main__':
    exit(main())
