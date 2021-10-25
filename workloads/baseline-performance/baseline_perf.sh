#!/usr/bin/env bash
set -e

source ./common.sh

start_time=`date +%s`
log "Sleeping for ${WATCH_TIME}M "
sleep ${WATCH_TIME}m 
end_time=`date +%s`
log "Running kube-burner index to measure  the performance of the cluster over the past ${WATCH_TIME}M"
  
curl -LsS ${KUBE_BURNER_RELEASE_URL} | tar xz

./kube-burner index -c baseline_perf.yml --uuid=${UUID} -u=${PROM_URL} --job-name baseline-performance-workload --token=${PROM_TOKEN} -m=metrics.yaml --start ${start_time} --end ${end_time}

log "Metrics stored at elasticsearch server $ES_SERVER on index $ES_INDEX with UUID $UUID and jobName `baseline-performance-workload`"