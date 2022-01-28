#!/bin/bash
while true; do
  readycount=$(oc get mcp worker-rt --no-headers | awk '{print $7}')
  echo $readycount
  sleep 30
done
