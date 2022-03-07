#!/bin/bash

set -o pipefail
set -eu


export NO_OF_INSTALLS="${NO_OF_INSTALLS:=5}"
export PLATFORM="${PLATFORM}"

if [ $PLATFORM == 'aws' ]
then
    source trigger_scale_ci_deploy.sh $PLATFORM $NO_OF_INSTALLS
elif [ $PLATFORM == 'gcp' ]
then
    source trigger_scale_ci_deploy.sh $PLATFORM $NO_OF_INSTALLS
if [ $PLATFORM == 'azure' ]
then
    source trigger_scale_ci_deploy.sh $PLATFORM $NO_OF_INSTALLS
fi



