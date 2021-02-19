#!/usr/bin/env bash

usage(){
  echo "Wrong invocation, correct syntax:"
  echo "$0 -c <CLIENTS> -n <NAMESPACE> -p <PATH> -k <KEEP_ALIVE_REQUESTS> -s <SCHEME> -t <TLS_REUSE>"
  exit 1
}

while getopts c:n:p:k:u:s:t:h flag; do
  case ${flag} in
    c) CLIENTS=${OPTARG};;
    n) NAMESPACE=${OPTARG};;
    k) KEEP_ALIVE_REQUESTS=${OPTARG};;
    p) URL_PATH=${OPTARG};;
    s) SCHEME=${OPTARG};;
    t) TLS_REUSE=${OPTARG};;
    *) usage;;
    ?) usage;;
  esac
done

if [[ ${SCHEME} == "https" ]]; then
  PORT=443
else
  PORT=80
fi

first=true
(echo "["
while read n r s p t w; do
  if [[ ${first} == "true" ]]; then
      echo "{"
      first=false
  else
      echo ",{"
  fi
  echo '"scheme": "'${SCHEME}'",
    "tls-session-reuse": '${TLS_REUSE}',
    "host": "'${n}'",
    "port": '${PORT}',
    "method": "GET",
    "path": "'${URL_PATH}'",
    "delay": {
      "min": 0,
      "max":0 
    },
    "keep-alive-requests": '${KEEP_ALIVE_REQUESTS}',
    "clients": '${CLIENTS}'
  }'
done <<< $(oc get route -n ${NAMESPACE} --no-headers | awk '{print $2}')
echo "]") | python -m json.tool
