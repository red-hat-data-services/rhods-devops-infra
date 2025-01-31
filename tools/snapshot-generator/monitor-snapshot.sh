#!/bin/bash
set -eo pipefail

# USAGE:
# ./monitor_snapshot.sh SNAPSHOT_NAME INTEGRATION_TEST_NAME OUTPUT_FILE_NAME

snapshot=$1
integration_test=$2
output_file=$3

echo waiting for snapshot creation...
kubectl wait --for create snapshot "$snapshot" --timeout=10m

echo "getting pipelinerun..."
pipelinerun=$(kubectl get pipelinerun -l "appstudio.openshift.io/snapshot=$snapshot,test.appstudio.openshift.io/scenario=$integration_test" --no-headers | awk '{print $1}')

echo "waiting for verify task to start..."
kubectl wait --for='jsonpath={.status.childReferences[?(@.pipelineTaskName=="verify")]}' pipelinerun "$pipelinerun" --timeout=10m
task_name=$(kubectl get pipelinerun "$pipelinerun"  -o jsonpath='{.status.childReferences[0].name}')
pod_name="${task_name}-pod"

echo "waiting for $pod_name to be created"
kubectl wait --for=create pod "$pod_name" --timeout=20m
echo "waiting for $pod_name to finish"
kubectl wait --for='jsonpath={.status.conditions[?(@.reason=="PodCompleted")].status}=True' pod "$pod_name" --timeout=60m


kubectl logs "$pod_name" step-report-json > $output_file
echo $pipelinerun


