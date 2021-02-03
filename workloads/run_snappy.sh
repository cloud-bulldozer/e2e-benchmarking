#!/usr/bin/env bash
export LC_ALL=en_US.utf-8
export LANG=en_US.utf-8
python3 -m pip install --user pipx
export PATH="${PATH}:$(python3 -c 'import site; print(site.USER_BASE)')/bin"
export SNAPPY_FILE_DIR=$2
pipx install git+https://github.com/openshift-scale/data-server-cli.git
snappy install

if [[ $? -ne 0 ]] ; then
  echo "Unable to backup data... Failed to install snappy!"
  exit 1
fi

export DATA_SERVER_URL=http://ec2-35-165-90-5.us-west-2.compute.amazonaws.com:7070
export DATA_SERVER_USERNAME=amit@redhat.com
export DATA_SERVER_PASSWORD=amit

export file_path=$1

set -x
snappy script-login
snappy post-file $file_path
set +x

if [[ $? -ne 0 ]] ; then
  echo "Unable to backup data - Failed to run Snappy!"
  exit 1
fi

deactivate
rm -rf venv