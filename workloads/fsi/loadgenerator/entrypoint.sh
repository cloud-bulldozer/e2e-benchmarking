#!/bin/sh
echo "Delaying start for 90s..."
sleep 90

locust --host=http://${FRONTEND_ADDR} \
       --loglevel "${LOG_LEVEL}" \
       --headless \
       --users="${USERS:-100}" \
       --run-time 1m \
       --print-stats \
       --csv=/tmp/locust-results

echo "Running indexing.py..."
python /app/indexing.py

echo "Sleeping for 1 hour..."
sleep 3600
