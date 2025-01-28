#!/bin/bash
#Prerequisites
# jq

function help {
cat <<EOF
RHOAI_QUAY_API_TOKEN=TOKEN_PATH ./generate-nightly-override-snapshot.sh RHOAI_VERSION
  TOKEN_PATH - path to the quay API token
  RHOAI_VERSION - the full version of the nightly you want to generate, in the form X.Y.Z. (example: 2.17.0)
EOF
}

if [ "$1" = "-h" -o "$1" = "--help" ]; then
  help
  exit 0
fi

if [ -z "$RHOAI_QUAY_API_TOKEN" ]; then
  echo "Please set the environment variable RHOAI_QUAY_API_TOKEN"
  help
  exit 1
fi

# example: 2.17.0
rhoai_version=$1
shift

output_file=
if [ "$1" = "-o" ]; then
 output_file=$2 
fi

if [ -z "$rhoai_version" ]; then
  echo "Please indicate which RHOAI version for the snapshot"
  help
  exit 1
fi

# rhoai-2.17
release_branch=$(echo "$rhoai_version" | awk -F '.' '{ print "rhoai-" $1 "." $2}')
# v2-17
hyphenized_rhoai_version=$(echo "$rhoai_version" | awk -F '.' '{ print "v" $1 "-" $2}')


FBC_QUAY_REPO=quay.io/rhoai/rhoai-fbc-fragment
RBC_URL=https://github.com/red-hat-data-services/RHOAI-Build-Config

image_uri=docker://${FBC_QUAY_REPO}:${release_branch}-nightly

skopeo login -u '$oauthtoken' -p "$RHOAI_QUAY_API_TOKEN" quay.io/rhoai
META=$(skopeo inspect --no-tags "${image_uri}")
DIGEST=$(echo $META | jq -r .Digest)
image_uri=${FBC_QUAY_REPO}@${DIGEST}
RBC_RELEASE_BRANCH_COMMIT=$(echo $META | jq -r '.Labels | ."git.commit"')
SHORT_COMMIT=${RBC_RELEASE_BRANCH_COMMIT::8}

echo "RBC_RELEASE_BRANCH_COMMIT = ${RBC_RELEASE_BRANCH_COMMIT}"
echo "Generating override snapshot for nightly - ${image_uri}"
echo "starting to create the artifacts corresponding to the sourcecode at ${RBC_URL}/tree/${RBC_RELEASE_BRANCH_COMMIT}"
#

component_application=rhoai-${hyphenized_rhoai_version}

echo "component application: $component_application"
fbc_application_prefix=rhoai-fbc-fragment-ocp-


current_dir=$(pwd)
#workspace=/tmp/tmp.68Vts9xj27
#epoch=1732618870

workspace=$(mktemp -d)
echo "workspace=${workspace}"

epoch=$(date +%s)
output_dir=nightly-snapshots
snapshot_components_dir=${output_dir}/snapshot-components
snapshot_fbc_dir=${output_dir}/snapshot-fbc

mkdir -p ${snapshot_components_dir}
mkdir -p ${snapshot_fbc_dir}

template_dir=templates/stage

RBC_RELEASE_DIR=${workspace}/RBC_${release_branch}_commit
V417_CATALOG_YAML_PATH=catalog/v4.17/rhods-operator/catalog.yaml
mkdir -p ${RBC_RELEASE_DIR}
cd ${RBC_RELEASE_DIR}

git config --global init.defaultBranch ${release_branch}
git init -q
git remote add origin $RBC_URL
git config core.sparseCheckout true
git config core.sparseCheckoutClone false
mkdir -p .git/info
echo "${V417_CATALOG_YAML_PATH}" >> .git/info/sparse-checkout
echo "config/build-config.yaml" >> .git/info/sparse-checkout
git fetch -q --depth=1 origin ${RBC_RELEASE_BRANCH_COMMIT}
git checkout -q ${RBC_RELEASE_BRANCH_COMMIT}
CATALOG_YAML_PATH=${RBC_RELEASE_DIR}/${V417_CATALOG_YAML_PATH}
BUILD_CONFIG_PATH=${RBC_RELEASE_DIR}/config/build-config.yaml
cd ${current_dir}

CATALOG_YAML_PATH=${RBC_RELEASE_DIR}/${V417_CATALOG_YAML_PATH}

RHOAI_KONFLUX_COMPONENTS_DETAILS_FILE_PATH=${workspace}/konflux_components.txt

kubectl get components -o=jsonpath="{range .items[?(@.spec.application=='${component_application}')]}{@.metadata.name}{'\t'}{@.spec.containerImage}{'\n'}{end}" > ${RHOAI_KONFLUX_COMPONENTS_DETAILS_FILE_PATH}


RHOAI_QUAY_API_TOKEN=${RHOAI_QUAY_API_TOKEN} python release_processor.py --operation generate-snapshots --catalog-yaml-path ${CATALOG_YAML_PATH} --konflux-components-details-file-path ${RHOAI_KONFLUX_COMPONENTS_DETAILS_FILE_PATH} --rhoai-version ${rhoai_version} --rhoai-application ${component_application} --epoch ${epoch} --output-dir ${output_dir} --template-dir ${template_dir} --rbc-release-commit ${RBC_RELEASE_BRANCH_COMMIT}

cp ${snapshot_components_dir}/snapshot-components-stage-${component_application}-$epoch.yaml $output_file

