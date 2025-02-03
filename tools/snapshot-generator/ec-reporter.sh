#!/bin/bash

set -eo pipefail

# this script is intended to run in a tekton task. 
# Run it directly from the directory it is in, as it depends on other files in here.
# Required environment varaiables:

# K8S_SA_TOKEN - k8s service account that can create, update, patch snapshots
# SLACK_TOKEN - oauth token for slack
# SLACK_CHANNEL - channel id to send message
# RHOAI_QUAY_API_TOKEN 
# VERSION - the rhoai version in x.y.z form
# KUBERNETES_SERVICE_HOST - should be set automatically by k8s
# KUBERNETES_SERVICE_PORT_HTTPS - should be set automatically by k8s


source ./ubi9-minimal-install.sh

kubectl config set-credentials snapshot-sa --token=$K8S_SA_TOKEN
kubectl config set-cluster default --server=https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT_HTTPS --certificate-authority="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
kubectl config set-context snapshot --user=snapshot-sa --cluster=default
kubectl config use-context snapshot

APPLICATION=$(echo $VERSION | awk -F '.' '{print "rhoai-v" $1 "-" $2 }')
# generate snapshots
# requires RHOAI_QUAY_API_TOKEN env var to be set
bash ./make-nightly-snapshots.sh "$VERSION"


for MODE in components fbc; do
  MESSAGE=
  if [ "$MODE" = fbc ]; then
    ec_test="$APPLICATION-fbc-rhoai-prod-enterprise-contract"
    snapshot_folder="nightly-snapshots/snapshot-fbc"
  else
    ec_test="$APPLICATION-registry-rhoai-prod-enterprise-contract"
    snapshot_folder="nightly-snapshots/snapshot-components"
  fi

  # apply and mark snapshot so that the EC gets run against it
  kubectl apply -f $snapshot_folder
  snapshot_name=$(kubectl get -f $snapshot_folder --no-headers | awk '{print $1}')
  echo kubectl label snapshot "$snapshot_name" "test.appstudio.openshift.io/run=$ec_test"
  kubectl label snapshot "$snapshot_name" "test.appstudio.openshift.io/run=$ec_test"

  # monitor pipelinerun 
  ec_results_file=./$MODE-results.json 
  monitor_snapshot_output=./monitor-$MODE-snapshot-output.txt
  bash ./monitor-snapshot.sh "$snapshot_name" "$ec_test" "$monitor_snapshot_output" 

  echo "processing log output"

  PIPELINE_NAME=$(cat "$monitor_snapshot_output" | tail -n 1 )
  cat $monitor_snapshot_output | tail -n 2 | head -n 1 > "$ec_results_file"

  WEB_URL="https://konflux.apps.stone-prod-p02.hjvn.p1.openshiftapps.com/application-pipeline/workspaces/rhoai/applications/$APPLICATION" 

  # create formatted yaml file to send to slack
  echo "Selecting violations out of ec results file"
  cat "$ec_results_file" | jq '[.components[] | select(.violations)] | map({name, containerImage, violations: [.violations[] | {msg} + (.metadata | {description, solution})]}) ' | tee "./$MODE-ec-results-slack.json"
  echo "converting to yaml"
  cat "./$MODE-ec-results-slack.json" | yq -P | tee "./$MODE-ec-results-slack.yaml"

  # create inital slack message
  echo "parsing results for slack message"
  num_errors=$(cat "$ec_results_file"| jq '[.components[].violations | length] | add')
  num_warnings=$(cat "$ec_results_file" | jq '[.components[].warnings | length] | add')
  num_error_components=$(cat "$ec_results_file" | jq '[.components[] | select(.violations) | .name] | length')
  num_warning_components=$(cat "$ec_results_file" | jq '[.components[] | select(.warnings) | .name] | length')

  MESSAGE="EC validation test $ec_test for $APPLICATION (<$WEB_URL/pipelineruns/$PIPELINE_NAME|$PIPELINE_NAME>) had $num_errors errors across $num_error_components components and $num_warnings warnings across $num_warning_components components"

  echo $MESSAGE

  echo "sending slack message with file attachment"
  bash ../send-slack-message/send-slack-message.sh -v -c "$SLACK_CHANNEL" -m "$MESSAGE" -f "./$MODE-ec-results-slack.yaml" 
done
