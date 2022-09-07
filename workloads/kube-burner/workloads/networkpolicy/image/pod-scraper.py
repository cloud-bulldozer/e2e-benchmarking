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


def namespaced_name(namespace, name):
    if namespace:
        return "/".join([namespace, name])
    return name


def index_result(payload, retry_count=3):
    print(f"Indexing documents in {es_index}")
    while retry_count > 0:
        try:
            ssl_ctx = ssl.create_default_context()
            ssl_ctx.check_hostname = False
            ssl_ctx.verify_mode = ssl.CERT_NONE
            es = elasticsearch6.Elasticsearch([es_server], send_get_body_as="POST", ssl_context=ssl_ctx, use_ssl=True)
            es.index(index=es_index, body=payload, doc_type="json")
            retry_count = 0
        except Exception as e:
            print("Failed Indexing", e)
            print("Retrying again to index...")
            retry_count -= 1


def check_pods_are_running(namespaces):
    logging.info("Waiting for all pods to be in Running state in selected namespaces")
    timeout_start = time.time()
    while time.time() < timeout_start + timeout:
        statuses = set()
        for namespace in namespaces:
            pod_status = v1.list_namespaced_pod(namespace=namespace, pretty=True)
            for pod in pod_status.items:
                statuses.add(pod.status.phase)
        if len(statuses) == 1 and "Running" in statuses:
            logging.info("All pods are in Running state")
            break
        time.sleep(5)


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
    
    try:
        logging.info("Inspecting policies to find target namespaces & pods")
        api_response = netv1.list_namespaced_network_policy(
            curr_namespace, pretty="true"
        )
        mappings = []
        namespaces = []
        for netpol in range(len(api_response.items)):
            if os.environ.get("WORKLOAD") == "networkpolicy-case1":
                # for this case, we get the namespaces from the policies egress rules
                if api_response.items[netpol].spec.egress:
                    namespace = api_response.items[
                        netpol
                    ].spec.egress[0]._to[0].namespace_selector.match_labels[
                        "kubernetes.io/metadata.name"
                    ]
                    namespaces.append(namespace)
            elif os.environ.get("WORKLOAD") == "networkpolicy-case2":
                if api_response.items[netpol].spec.ingress:
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
                        mappings.append(destination)
                        namespaces = [curr_namespace]
            elif os.environ.get("WORKLOAD") == "networkpolicy-case3":
                if api_response.items[netpol].spec.ingress:
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
                        mappings.append(destination)
                        namespaces = [curr_namespace]

        if not namespaces:
            logging.info("No target namespaces where selected, exiting")
            return

        logging.info(f"Selected namespaces: {namespaces}")
        check_pods_are_running(namespaces)

        label_selectors = []
        if mappings:
            for destination_label in mappings:
                label_selector = "\n".join(f"{k}={v}" for k, v in destination_label.items())
                label_selectors.append(label_selector)
            logging.info(f"Selecting pods in target namespaces with each of label selectors: {label_selectors}")
        else:
            logging.info("Selecting all pods in target namespaces")
            label_selectors.append(None)
        
        dest_pods = {}
        for namespace in namespaces:
            for label_selector in label_selectors:
                ret = v1.list_namespaced_pod(
                        namespace, label_selector=label_selector, watch=False
                    )
                for pod in ret.items:
                    k = namespaced_name(pod.metadata.namespace, pod.metadata.name)
                    dest_pods[k] = pod

        logging.info("Attempting connectivity with all selected pods")

        for pod in dest_pods.values():
            count = 0.0
            start = timeit.default_timer()
            timeout_start = time.time()
            while time.time() < timeout_start + timeout:
                try:
                    logging.info(f"Trying to connect {pod.status.pod_ip}")
                    response = s.get(f"http://{pod.status.pod_ip}:8000", timeout=0.1)
                    logging.info(f"Connected to {pod.status.pod_ip}")
                    if response.status_code == 200:
                        break
                except requests.exceptions.HTTPError as errh:
                    logging.exception("Http Error")
                except requests.exceptions.ConnectionError as errc:
                    logging.exception("Connection Error")
                except requests.exceptions.Timeout as errt:
                    logging.exception("Timeout Error")
                except requests.exceptions.RequestException as err:
                    logging.exception("Request Error")
            end = timeit.default_timer()
            time_taken = end - start
            logging.info(
                f"Time taken to connect {pod.status.pod_ip} is {time_taken}s"
            )
            logging.info("                ***                 ")
            payload = {"timestamp": datetime.datetime.utcnow(), "uuid": label[-3], "connection_time": time_taken}
            index_result(payload)

        logging.info("Done connecting with all selected pods")

    except ApiException as e:
        print(
            "Exception when calling NetworkingV2Api->list_namespaced_network_policy: %s\n"
            % e
        )



if __name__ == "__main__":
    main()
