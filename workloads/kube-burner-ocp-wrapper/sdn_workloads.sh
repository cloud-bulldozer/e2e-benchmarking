#!/usr/bin/env bash
set -x

source ./aws_instance.sh

export AWS_HTTP_SERVER_PORT=9111
export USER_DATA_SCRIPT="/tmp/user-data.sh"

bgp_user_data(){
	# Check if KUBECONFIG is set
	if [ -z "$KUBECONFIG" ]; then
		echo "KUBECONFIG environment variable is not set."
		exit 1
	fi

	# Check if the file exists
	if [ ! -f "$KUBECONFIG" ]; then
		echo "Kubeconfig file not found: $KUBECONFIG"
		exit 1
	fi

	# Read the content into a variable
	KUBECONFIG_CONTENT=$(< "$KUBECONFIG")

	# configure external FRR
	CONFIG_VTYSH_CMDS=$(cat <<'VTYSH_CMDS_DELIMITER'
configure terminal
router bgp 64512
redistribute static
redistribute connected
end
write
VTYSH_CMDS_DELIMITER
)

    # Create the user-data script
    cat <<EOF > $USER_DATA_SCRIPT
#!/bin/bash
set -x

echo "root:temppass" | sudo chpasswd
sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo systemctl restart sshd

sudo dnf install curl git make binutils bison gcc glibc-devel golang podman jq -y
mkdir -p /root/.kube/

# Write the kubeconfig file
cat <<KCFG > /root/.kube/config
$KUBECONFIG_CONTENT
KCFG

chmod 666 /root/.kube/config
export KUBECONFIG=/root/.kube/config

cd /tmp
curl -sSL https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux-amd64-rhel8.tar.gz | tar -xvzf -
mv oc /usr/local/bin/
mv kubectl /usr/local/bin/

mkdir -p /tmp/gocache
export GOCACHE=/tmp/gocache
cd /tmp
git clone -b ovnk-bgp https://github.com/jcaamano/frr-k8s
cd frr-k8s/hack/demo/
./demo.sh
sleep 30
oc apply -f configs/receive_all.yaml

echo "${CONFIG_VTYSH_CMDS}" | sudo podman exec -i frr vtysh

mkdir -p /tmp/code
cd /tmp/code
#curl --fail --retry 8 --retry-all-errors -sS -L "${KUBE_BURNER_URL}" | tar -xzC "${KUBE_DIR}/" kube-burner-ocp
git clone -b temp_test https://github.com/venkataanil/kube-burner-ocp
cd /tmp/code/kube-burner-ocp
mkdir -p /tmp/gocache
export GOCACHE=/tmp/gocache
export GOMODCACHE='/root/go/pkg/mod'
make clean; make build
cp ./bin/amd64/kube-burner-ocp ${KUBE_DIR}/
echo $COMMAND

cd /tmp
$COMMAND
echo "\$?" > kube_burner_exit.txt
mkdir results
cp kube-burner-ocp-$UUID.log kube_burner_exit.txt results/
cd results
python3 -m http.server $AWS_HTTP_SERVER_PORT &
EOF
}

egressip_user_data(){
	cat <<EOF > $USER_DATA_SCRIPT
#!/bin/bash
sudo dnf install podman -y
for port in {9002..9020}; do
    podman run --network=host -d -e LISTEN_PORT=\$port quay.io/cloud-bulldozer/nginxecho:latest
done
EOF
}

run_bgp_workload() {
    oc patch Network.operator.openshift.io cluster --type=merge -p='{"spec":{"additionalRoutingCapabilities": {"providers": ["FRR"]}, "defaultNetwork":{"ovnKubernetesConfig":{"routeAdvertisements":"Enabled"}}}}'
	sleep 300

	export COMMAND="$cmd --iterations=${ITERATIONS} --gc=false"
	bgp_user_data

	# Set BGP session TCP port
	export TCP_PORTS="179"

	# BGP workload will run as part of init-config user data 
    	get_aws_instance
	sleep 120


	# Retrieve kube burner status from aws instance using sleep pod
	SLEEP_POD="sleep"
	oc run "$SLEEP_POD" -n default --image=registry.access.redhat.com/ubi8/ubi -- /bin/bash -c 'sleep infinity'
	oc wait --for=condition=Ready pod/"$SLEEP_POD" -n default --timeout=120s

	while true; do
	    oc exec "$SLEEP_POD" -n default -- curl -s -o "/tmp/kube_burner_exit.txt" "http://$AWS_INSTANCE_IP:$AWS_HTTP_SERVER_PORT/kube_burner_exit.txt"
		if [[ $? -ne 0 ]]; then
		    sleep 60
			continue
		fi
	    oc exec "$SLEEP_POD" -n default -- curl -s -o "/tmp/kube-burner-ocp-$UUID.log" "http://$AWS_INSTANCE_IP:$AWS_HTTP_SERVER_PORT/kube-burner-ocp-$UUID.log"
		oc cp default/"$SLEEP_POD":/tmp/kube_burner_exit.txt kube_burner_exit.txt
		oc cp default/"$SLEEP_POD":/tmp/kube-burner-ocp-$UUID.log kube-burner-ocp-$UUID.log
		break
	done
	oc delete pod "$SLEEP_POD" -n default

	exit_code=$(cat kube_burner_exit.txt)

}

run_egressip_workload() {
    # label all worker nodes for assigning egress IPs
    for n in $(oc get node -l node-role.kubernetes.io/worker,node-role.kubernetes.io/infra!=,node-role.kubernetes.io/workload!= -o jsonpath="{.items[*].metadata.name}"); do
        oc label nodes $n k8s.ovn.org/egress-assignable=""
    done

    egressip_user_data
	get_aws_instance
	ITERATIONS=${ITERATIONS:?}
	cmd+=" --iterations=${ITERATIONS} --external-server-ip=${AWS_INSTANCE_IP}"
	$cmd
	exit_code=$?
}

run_sdn_workload() {
	install_oc_cli
	configure_aws

	if [[ ${WORKLOAD} == "udn-bgp" ]]; then
		run_bgp_workload
	elif [[ ${WORKLOAD} == "egressip" ]]; then  
		run_egressip_workload
	fi

	export JOB_END=${JOB_END:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")};
    	cleanup_aws_instance
	(exit $exit_code)
}
