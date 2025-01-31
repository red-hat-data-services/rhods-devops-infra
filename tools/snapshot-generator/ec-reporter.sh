#!/bin/bash

set -eo pipefail

# this script is intended to run in a tekton task. 
# Run it directly from the directory it is in, as it depends on other files in here.
# Required environment varaiables:

# K8S_SA_TOKEN - k8s service account that can create, update, patch snapshots
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
ec_component_test="$APPLICATION-registry-rhoai-prod-enterprise-contract"
ec_fbc_test="$APPLICATION-fbc-rhoai-prod-enterprise-contract"
# generate component snapshot
# requires RHOAI_QUAY_API_TOKEN env var to be set
bash make-nightly-snapshots.sh "$VERSION"

# apply and mark snapshot so that the EC gets run against it
kubectl apply -f nightly-snapshots/snapshot-components
snapshot_name=$(kubectl get -f nightly-snapshots/snapshot-components --no-headers | awk '{print $1}')
echo kubectl label snapshot "$snapshot_name" "test.appstudio.openshift.io/run=$ec_component_test"
kubectl label snapshot "$snapshot_name" "test.appstudio.openshift.io/run=$ec_component_test"

# monitor pipelinerun 
components_results_file=./components_results.json 
bash ./monitor-snapshot.sh "$snapshot_name" "$ec_component_test" "$components_results_file" | tee ./monitor-snapshot-output.txt

PIPELINE_NAME=$(cat ./monitor-snapshot-output.txt | tail -n 1)
WEB_URL="https://konflux.apps.stone-prod-p02.hjvn.p1.openshiftapps.com/application-pipeline/workspaces/rhoai/applications/$APPLICATION" 

# create formatted yaml file to send to slack
cat "$components_results_file" | jq '[.components[] | select(.violations)] | map({name, containerImage, violations: [.violations[] | {msg} + (.metadata | {description, solution})]}) ' | yq -P > "${HOME}/component-results-slack.yaml"

# create inital slack message
num_errors=$(cat "$components_results_file"| jq '[.components[].violations | length] | add')
num_warnings=$(cat "$components_results_file" | jq '[.components[].warnings | length] | add')
num_error_components=$(cat "$components_results_file" | jq '[.components[] | select(.violations) | .name] | length')

MESSAGE="EC validation test $ec_component_test for $APPLICATION (<$WEB_URL/pipelineruns/$PIPELINE_NAME|$PIPELINE_NAME>) had $num_errors errors and $num_warnings warnings across $num_error_components components"

echo $MESSAGE

