#!/bin/bash

export OUTPUT_DIR=/root
export PROMETHEUS_CAPTURE=true                          # Captures prometheus database when enabled
export PROMETHEUS_CAPTURE_TYPE=full                     # Options available: wal or full, wal captures the write ahead log while full captures the entire prometheus DB
export OPENSHIFT_MUST_GATHER=true                       # Captures must-gather when enabled
export STORAGE_MODE=                                    # Stores the tar balls on the local filesystem when empty, other options available are pbench and snappy server
export SNAPPY_FILE_DIR=                                 # Directory path where to store data in snappy server
