#!/bin/bash

export OUTPUT_DIR=/root
# Captures prometheus database when enabled
export PROMETHEUS_CAPTURE=true
# Options available: wal or full, wal captures the write ahead log while full captures the entire prometheus DB
export PROMETHEUS_CAPTURE_TYPE=full
# Captures must-gather when enabled
export OPENSHIFT_MUST_GATHER=true
# Stores the tar balls on the local filesystem when empty, other options available are pbench and snappy server
export STORAGE_MODE=
