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
kubectl get pipelinerun -l "appstudio.openshift.io/snapshot=$snapshot,test.appstudio.openshift.io/scenario=$integration_test"
pipelinerun=$(kubectl get pipelinerun -l "appstudio.openshift.io/snapshot=$snapshot,test.appstudio.openshift.io/scenario=$integration_test" --no-headers | awk '{print $1}')

echo "waiting for verify task to start..."
kubectl wait --for='jsonpath={.status.childReferences[?(@.pipelineTaskName=="verify")]}' pipelinerun "$pipelinerun" --timeout=10m
task_name=$(kubectl get pipelinerun "$pipelinerun"  -o jsonpath='{.status.childReferences[0].name}')

pod_label="tekton.dev/taskRun=$task_name"
echo "waiting for pod with label $pod_label to be created"
# need this sleep 5 for some reason
sleep 5
kubectl wait --for=create pod -l "$pod_label" --timeout=20m
pod_name=$(kubectl get pod -l "$pod_label" --no-headers | awk '{print $1}')

# echo "waiting for pod to be ready"
# kubectl wait --for=condition=Ready pod "$pod_name" --timeout=60m
echo "waiting for container step-report-json in $pod_name to finish"
kubectl wait --for='jsonpath={.status.containerStatuses[?(@.name=="step-report-json")].state.terminated}' pod "$pod_name" --timeout=30m
kubectl logs "$pod_name" step-report-json | tee $output_file
echo $pipelinerun >> "$output_file"

exit 0

