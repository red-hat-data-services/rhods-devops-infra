#!/bin/bash

if ! python --version > /dev/null 2>&1; then 
  echo "Python binary not found. Did you remember to set up a virtual environment?"
  exit 1
fi

if ! yq --version > /dev/null 2>&1; then
  echo "yq binary not found"
  exit 1
fi

KUBE_CLUSTER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
if ! echo "$KUBE_CLUSTER" | grep 'stone-prod-p02' > /dev/null; then
  echo "kubectl cluster url does not match 'stone-prod-2':"
  echo "  $KUBE_CLUSTER"
  echo "Are you sure you are using the correct kubeconfig and/or kubectl context?"
  exit 1
fi
