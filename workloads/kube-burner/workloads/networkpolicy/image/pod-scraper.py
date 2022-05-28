import ssl
import time
from kubernetes import client, config
from kubernetes.client.rest import ApiException
from pprint import pprint
import datetime
from dateutil.tz import tzlocal
import requests
from requests.adapters import HTTPAdapter, Retry
import logging
import timeit
import os
import elasticsearch6


def index_result(payload, retry_count=3):
    print(f"Indexing documents in {es_index}")
    while retry_count > 0:
        try:
            ssl_ctx = ssl.create_default_context()
            ssl_ctx.check_hostname = False
            ssl_ctx.verify_mode = ssl.CERT_NONE
            es = elasticsearch6.Elasticsearch([es_server])
            es.index(index=es_index, body=payload, doc_type="json")
            retry_count = 0
        except Exception as e:
            print("Failed Indexing", e)
            print("Retrying again to index...")
            retry_count -= 1


def check_pods_are_running():
    logging.info("Waiting for all pods to be in Running state")
    timeout_start = time.time()
    while time.time() < timeout_start + timeout:
        statuses = set()
        pod_status = v1.list_namespaced_pod(namespace=curr_namespace, pretty=True)
        for pod in pod_status.items:
            statuses.add(pod.status.phase)
        if len(statuses) == 1 and "Running" in statuses:
            logging.info("All pods are in Running state")
            break


def main():
    global es_server, es_index, timeout, v1, curr_namespace
    es_server = os.getenv("ES_SERVER")
    es_index = os.getenv("ES_INDEX_NETPOL")

    timeout = 300

    s = requests.Session()
    retries = Retry(total=1, backoff_factor=0, status_forcelist=[502, 503, 504])

    config.load_incluster_config()
    v1 = client.CoreV1Api()
    netv1 = client.NetworkingV1Api()

    with open("/var/run/secrets/kubernetes.io/serviceaccount/namespace") as ns:
        curr_namespace = ns.read()
    with open("/etc/podinfo/labels") as l:
        pod_labels = l.read()
    label = []
    pod_labels = pod_labels.split()
    for labels in range(len(pod_labels)):
        pod_labels1 = pod_labels[labels].split("=")
        label1 = pod_labels1[1]
        label1 = label1.strip('"')
        label.append(label1)

    logging.basicConfig(
        format="%(asctime)s %(levelname)-8s %(message)s",
        level=logging.INFO,
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    
    check_pods_are_running()
    
    try:
        api_response = netv1.list_namespaced_network_policy(
            curr_namespace, pretty="true"
        )
        mapping = []
        for netpol in range(len(api_response.items)):
            if api_response.items[netpol].spec.ingress is not None:
                if os.environ.get("WORKLOAD") == "networkpolicy-case3":
                    source = (
                        api_response.items[netpol]
                        .spec.ingress[0]
                        ._from[0]
                        .pod_selector.match_expressions[0]
                        .values
                    )
                    if label[-1] not in source and label[-2] not in source:
                        destination = api_response.items[
                            netpol
                        ].spec.pod_selector.match_labels
                        mapping.append(destination)
                else:
                    source = (
                        api_response.items[netpol]
                        .spec.ingress[0]
                        ._from[0]
                        .pod_selector.match_labels
                    )
                    if label[-1] in source.values() or label[-2] in source.values():
                        destination = api_response.items[
                            netpol
                        ].spec.pod_selector.match_labels
                        mapping.append(destination)
        for destination_label in mapping:
            label_selector = "\n".join(f"{k}={v}" for k, v in destination_label.items())
            ret = v1.list_namespaced_pod(
                curr_namespace, label_selector=label_selector, watch=False
            )
            for dest_pods in ret.items:
                count = 0.0
                start = timeit.default_timer()
                timeout_start = time.time()
                while time.time() < timeout_start + timeout:
                    try:
                        logging.info(f"Trying to connect {dest_pods.status.pod_ip}")
                        response = s.get(f"http://{dest_pods.status.pod_ip}:8000", timeout=0.1)
                        logging.info(f"Connected to {dest_pods.status.pod_ip}")
                        if response.status_code == 200:
                            break
                    except requests.exceptions.HTTPError as errh:
                        print("Http Error:", errh)
                    except requests.exceptions.ConnectionError as errc:
                        logging.warning("Trying again")
                    except requests.exceptions.Timeout as errt:
                        print("Timeout Error:", errt)
                    except requests.exceptions.RequestException as err:
                        print("Something Else", err)
                end = timeit.default_timer()
                time_taken = end - start
                logging.info(
                    f"Time taken to connect {dest_pods.status.pod_ip} is {time_taken}s"
                )
                logging.info("                ***                 ")
                payload = {"uuid": label[-3], "connection_time": time_taken}
                index_result(payload)

    except ApiException as e:
        print(
            "Exception when calling NetworkingV2Api->list_namespaced_network_policy: %s\n"
            % e
        )



if __name__ == "__main__":
    main()
