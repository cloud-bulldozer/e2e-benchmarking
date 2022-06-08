#!/usr/bin/env bash
set -x

source env.sh
source ../../utils/common.sh
source ../../utils/benchmark-operator.sh

openshift_login

export_defaults() {
  export UUID=$(uuidgen)
  # create_clusters endpoint needs OsdCcsAdmin user's key.
  # Only 2 keys are allowed at a time
  echo "Create new OSD access key.."
  keys=`aws iam list-access-keys --user-name OsdCcsAdmin --output json  | jq -r '.AccessKeyMetadata[].AccessKeyId' | wc -l`
  if [[ $keys == 2 ]]; then
    exit 1
  fi
  export ADMIN_KEY=$(aws iam create-access-key --user-name OsdCcsAdmin --output json)
  export AWS_ACCESS_KEY=$(echo $ADMIN_KEY | jq -r '.AccessKey.AccessKeyId')
  export AWS_ACCESS_SECRET=$(echo $ADMIN_KEY | jq -r '.AccessKey.SecretAccessKey')
  sleep 60
  aws iam get-user --output json | jq -r .User.UserName
}

deploy_operator() {
  deploy_benchmark_operator ${OPERATOR_REPO} ${OPERATOR_BRANCH}
}

prepare_tests() {
  # declare tests with their options as a dict. Later in this function, each test variable used with the help of reference
  declare -A list_clusters=( ["rate"]="${LIST_CLUSTERS_RATE}" ["duration"]="${LIST_CLUSTERS_DURATION}" )
  declare -A self_access_token=( ["rate"]="${SELF_ACCESS_TOKEN_RATE}" ["duration"]="${SELF_ACCESS_TOKEN_DURATION}" )
  declare -A list_subscriptions=( ["rate"]="${LIST_SUBSCRIPTIONS_RATE}" ["duration"]="${LIST_SUBSCRIPTIONS_DURATION}" )
  declare -A access_review=( ["rate"]="${ACCESS_REVIEW_RATE}" ["duration"]="${ACCESS_REVIEW_DURATION}" )
  declare -A register_new_cluster=( ["rate"]="${REGISTER_NEW_CLUSTER_RATE}" ["duration"]="${REGISTER_NEW_CLUSTER_DURATION}" )
  declare -A register_existing_cluster=( ["rate"]="${REGISTER_EXISTING_CLUSTER_RATE}" ["duration"]="${REGISTER_EXISTING_CLUSTER_DURATION}" )
  declare -A create_cluster=( ["rate"]="${CREATE_CLUSTER_RATE}" ["duration"]="${CREATE_CLUSTER_DURATION}" )
  declare -A get_current_account=( ["rate"]="${GET_CURRENT_ACCOUNT_RATE}" ["duration"]="${GET_CURRENT_ACCOUNT_DURATION}" )
  declare -A quota_cost=( ["rate"]="${QUOTA_COST_RATE}" ["duration"]="${QUOTA_COST_DURATION}" )
  declare -A resource_review=( ["rate"]="${RESOURCE_REVIEW_RATE}" ["duration"]="${RESOURCE_REVIEW_DURATION}" )
  declare -A cluster_authorizations=( ["rate"]="${CLUSTER_AUTHORIZATIONS_RATE}" ["duration"]="${CLUSTER_AUTHORIZATIONS_DURATION}" )
  declare -A self_terms_review=( ["rate"]="${SELF_TERMS_RATE}" ["duration"]="${SELF_TERMS_DURATION}" )
  declare -A certificates=( ["rate"]="${CERTIFICATES_RATE}" ["duration"]="${CERTIFICATES_DURATION}" )

  # convert tests string to test array, for example, "list-clusters  list-subscriptions" => ("list-cluster", "list-subscriptions")
  IFS=', ' read -r -a testarr <<< "$TESTS"
  declare -a tests_dict=(${testarr[@]})

  # create shell variable TESTS_DICT with yaml dict content, like below
  #   list-clusters:
  #     rate: 20
  #   list-subscriptions:
  export TESTS_DICT=`
  for test in "${tests_dict[@]}"; do
    echo "        $test:"
    # test names will have "-" operator between words. But we can't declare shell variables with "-" operator.
    declare -n p="${test/-/_}"  # now p is a reference to a variable "$test"
    for attr in "${!p[@]}"; do
      if [[ ! -z "${p[$attr]}" ]]; then
        echo "          $attr: ${p[$attr]}"
      fi
    done
  done`
}

export_defaults
deploy_operator
