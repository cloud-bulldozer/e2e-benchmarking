#!/usr/bin/env bash
export PBENCH_SERVER=''
export GSHEET_KEY=
export GSHEET_KEY_LOCATION=''
export ES_SERVER=''
export ES_PORT=
export EMAIL_ID_FOR_RESULTS_SHEET=''
export COMPARE=false
export BASELINE_ROUTER_UUID=''
export BASESLINE_CLOUD_NAME=''

#HTTP benchmarks specific parameters:
export HTTP_TEST_SUFFIX='smoke-test'
export HTTP_TEST_APP_PROJECTS=10                                           
export HTTP_TEST_APP_TEMPLATES=10                                       # 10 for small scale test and 50 for large scale test
export HTTP_TEST_ROUTE_TERMINATION=''                                   # http, edge, passthrough, reencrypt and mix
export HTTP_TEST_SMOKE_TEST=true

