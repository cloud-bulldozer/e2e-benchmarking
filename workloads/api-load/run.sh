#!/usr/bin/env bash
set -x

source ./common.sh

CR=api-load-crd.yaml

log "###############################################"
log "api-load tests: ${TESTS}"
log "###############################################"

prepare_tests

start_time=`date +%s`
run_workload ${CR}
end_time=`date +%s`


curl -LsS ${KUBE_BURNER_RELEASE_URL} | tar xz

export KUBE_ES_INDEX=ocm-uhc-acct-mngr
log "Running kube-burner index to scrap metrics from UHC account manager service from ${start_time} to ${end_time} and push to ES"
./kube-burner index -c kube-burner-config.yaml --uuid=${UUID} -u=${PROM_URL} --job-name ocm-api-load --token=${PROM_TOKEN} -m=metrics_acct_mgmr.yaml --start ${start_time} --end ${end_time}
log "UHC account manager Metrics stored at elasticsearch server $ES_SERVER on index $KUBE_ES_INDEX with UUID $UUID and jobName: ocm-api-load"

log "Running kube-burner index to scrap metrics from UHC clusters service from ${start_time} to ${end_time} and push to ES"
export KUBE_ES_INDEX=ocm-uhc-clusters-service
./kube-burner index -c kube-burner-config.yaml --uuid=${UUID} -u=${PROM_URL} --job-name ocm-api-load --token=${PROM_TOKEN} -m=metrics_clusters_service.yaml --start ${start_time} --end ${end_time}
log "UHC clusters service metrics stored at elasticsearch server $ES_SERVER on index $KUBE_ES_INDEX with UUID $UUID and jobName: ocm-api-load"

aws iam delete-access-key --user-name OsdCcsAdmin --access-key-id $AWS_ACCESS_KEY || true

log "Finished workload ${0}"
