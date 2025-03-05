#!/bin/bash

set -eo pipefail

# this script is intended to run in a tekton task. 
# Run it directly from the directory it is in, as it depends on other files in here.
# Required environment varaiables:

# K8S_SA_TOKEN - k8s service account that can create, update, patch snapshots
# SLACK_TOKEN - oauth token for slack
# SLACK_CHANNEL - channel id to send message
# RHOAI_QUAY_API_TOKEN 
# SNAPSHOT_TARGET - Either the release branch in "rhoai-x.y" form, OR a full quay URL
# KUBERNETES_SERVICE_HOST - should be set automatically by k8s
# KUBERNETES_SERVICE_PORT_HTTPS - should be set automatically by k8s
# KUBERNETES_CA - if running from a pod on the same cluster, can set to /var/run/secrets/kubernetes.io/serviceaccount/ca.crt

echo "$KUBERNETES_CA" > ./ca.crt
kubectl config set-credentials snapshot-sa --token=$K8S_SA_TOKEN
kubectl config set-cluster default --server=https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT_HTTPS --certificate-authority=./ca.crt

kubectl config set-context snapshot --user=snapshot-sa --cluster=default
kubectl config use-context snapshot


if echo $SNAPSHOT_TARGET | grep -o quay; then
  IMAGE_URI=$SNAPSHOT_TARGET
else
  IMAGE_URI="quay.io/rhoai/rhoai-fbc-fragment:${SNAPSHOT_TARGET}-nightly"
fi

# generate snapshots
# requires RHOAI_QUAY_API_TOKEN env var to be set
bash ./make-nightly-snapshots.sh "$IMAGE_URI"

APPLICATION=$(yq '.spec.application' nightly-snapshots/snapshot-components/*yaml| head -n 1)

MODES="components fbc"

for MODE in $MODES; do
  MESSAGE=
  if [ "$MODE" = fbc ]; then
    conforma_test="conforma-fbc-rhoai-prod-${APPLICATION/rhoai-/}"
    snapshot_folder="nightly-snapshots/snapshot-fbc"
  else
    conforma_test="conforma-registry-rhoai-prod-${APPLICATION/rhoai-/}"
    snapshot_folder="nightly-snapshots/snapshot-components"
  fi
  ls nightly-snapshots/*
  # apply and mark snapshot so that the conforma gets run against it
  kubectl apply -f $snapshot_folder
  snapshot_name=$(kubectl get -f $snapshot_folder --no-headers | awk '{print $1}')
  echo kubectl label snapshot "$snapshot_name" "test.appstudio.openshift.io/run=$conforma_test"
  kubectl label snapshot "$snapshot_name" "test.appstudio.openshift.io/run=$conforma_test"
  
  # monitor pipelinerun 
  conforma_results_file=./$MODE-conforma-results.json 
  monitor_snapshot_output=./monitor-$MODE-snapshot-output.txt
  bash ./monitor-snapshot.sh "$snapshot_name" "$conforma_test" "$monitor_snapshot_output" 

  echo "processing log output"

  PIPELINE_NAME=$(cat "$monitor_snapshot_output" | tail -n 1 )
  cat $monitor_snapshot_output | tail -n 2 | head -n 1 | jq  > "$conforma_results_file"

  WEB_URL="https://konflux.apps.stone-prod-p02.hjvn.p1.openshiftapps.com/application-pipeline/workspaces/rhoai/applications/$APPLICATION" 
  
  # create formatted yaml file to send to slack
  echo "Selecting violations out of conforma results file"
  python parse-conforma-for-slack.py "$conforma_results_file" | tee "./$MODE-conforma-results-slack.json" | yq -P > "./$MODE-conforma-results-slack.yaml"

  # create inital slack message
  echo "parsing results for slack message"

  num_alerts=$(cat "./$MODE-conforma-results-slack.json" | jq '[.[][][]] | length')
  num_alert_components=$(cat "./$MODE-conforma-results-slack.json" | jq '[.[] | keys[]] | unique | length')
  num_errors=$(cat "$conforma_results_file"| jq '[.components[].violations | length] | add')
  num_imminent_warnings=$(( $num_alerts - $num_errors ))
  num_warnings=$(cat "$conforma_results_file" | jq '[.components[].warnings | length] | add')
  num_other_warnings=$(( $num_warnings - $num_imminent_warnings ))
  
  conforma_policy=$(kubectl get integrationtestscenario "$conforma_test" -o jsonpath='{@.spec.params[?(@.name=="POLICY_CONFIGURATION")].value}')

  MESSAGE=$(cat <<EOF
*$APPLICATION Conforma Validation Test Results ($MODE)*
Policy Name: *$conforma_policy*
Snapshot: <$WEB_URL/snapshots/$snapshot_name|$snapshot_name>
Pipeline Run: <$WEB_URL/pipelineruns/$PIPELINE_NAME|$PIPELINE_NAME>
Errors: *$num_errors errors* and *$num_imminent_warnings imminent warnings* across $num_alert_components components
Warnings: $num_other_warnings other warnings
EOF
)
  echo "$MESSAGE"

  echo "sending slack message with file attachment"
  bash ../send-slack-message/send-slack-message.sh -v -c "$SLACK_CHANNEL" -m "$MESSAGE"  -f "./$MODE-conforma-results-slack.yaml" -f "$conforma_results_file"
done
