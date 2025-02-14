#!/bin/bash
#Prerequisites
# jq
set -eo pipefail

function help {
cat <<EOF
RHOAI_QUAY_API_TOKEN=TOKEN_PATH ./generate-nightly-override-snapshot.sh IMAGE_URI
  TOKEN_PATH - path to the quay API token
  IMAGE_URI - the image URI for which you want to generate a snapshot
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

# used gsed for MacOS
if [[ "$(uname)" == "Darwin" ]]; then
  if ! command -v gsed &>/dev/null; then
      echo "gsed is not installed. Please install it using 'brew install gnu-sed'."
      exit 1
  fi
  sed_command="gsed"
else
  sed_command="sed"
fi

image_uri=$1

if [ -z "$image_uri" ]; then
  echo "Please specify an image URI to make snapshots from."
  help
  exit 1
fi



FBC_QUAY_REPO=quay.io/rhoai/rhoai-fbc-fragment
RBC_URL=https://github.com/red-hat-data-services/RHOAI-Build-Config

# image_uri=docker://${FBC_QUAY_REPO}:${release_branch}-nightly
# removing leading https:// or http://
image_uri=$(echo "$image_uri" | sed -E 's|^https?://||')
# removing tag from URI if both tag and shasum are present
image_uri=$(echo "$image_uri" | sed 's/:.*@/@/')
skopeo login -u '$oauthtoken' -p "$RHOAI_QUAY_API_TOKEN" quay.io/rhoai
META=$(skopeo inspect --no-tags "docker://${image_uri}")

# example: 2.17.0
rhoai_version=$(echo "$META" | jq -r '.Labels.version' | sed 's/v//')
# example: rhoai-2.17
release_branch=$(echo "$rhoai_version" |  awk -F '.' '{ print "rhoai-" $1 "." $2}')
# example: v2-17
hyphenized_rhoai_version=$(echo "$rhoai_version" | awk -F '.' '{ print "v" $1 "-" $2}')

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

# generate component snapshot
CATALOG_YAML_PATH=${RBC_RELEASE_DIR}/${V417_CATALOG_YAML_PATH}

RHOAI_KONFLUX_COMPONENTS_DETAILS_FILE_PATH=${workspace}/konflux_components.txt

kubectl get components -o=jsonpath="{range .items[?(@.spec.application=='${component_application}')]}{@.metadata.name}{'\t'}{@.status.lastPromotedImage}{'\n'}{end}" | tee ${RHOAI_KONFLUX_COMPONENTS_DETAILS_FILE_PATH}


release_processor_path="../rhoai-release-helper/release_processor.py"
RHOAI_QUAY_API_TOKEN=${RHOAI_QUAY_API_TOKEN} python "$release_processor_path" --operation generate-snapshots --catalog-yaml-path ${CATALOG_YAML_PATH} --konflux-components-details-file-path ${RHOAI_KONFLUX_COMPONENTS_DETAILS_FILE_PATH} --rhoai-version ${rhoai_version} --rhoai-application ${component_application} --epoch ${epoch} --output-dir ${output_dir} --template-dir ${template_dir} --rbc-release-commit ${RBC_RELEASE_BRANCH_COMMIT}

# generate FBC snapshot
ocp_version="v4.17"
fbc_application_suffix=${ocp_version/v4./4}
fbc_component_name=rhoai-fbc-fragment-${hyphenized_rhoai_version}
fbc_application_tag=${release_branch}-nightly
echo "fbc_component_name=${fbc_component_name}"
echo "fbc_application_tag=${fbc_application_tag}"

image_uri=docker://${FBC_QUAY_REPO}:${fbc_application_tag}
META=$(skopeo inspect --no-tags "${image_uri}")
DIGEST=$(echo $META | jq -r .Digest)
FULL_IMAGE_URI_WITH_DIGEST="${FBC_QUAY_REPO}@${DIGEST}"
echo "FBCF-${ocp_version} - ${FULL_IMAGE_URI_WITH_DIGEST}"
GIT_URL=$(echo $META | jq -r '.Labels | ."git.url"')
GIT_COMMIT=$(echo $META | jq -r '.Labels | ."git.commit"')


echo "Generating FBC Snapshots..."
fbc_snapshot_yaml_path=${snapshot_fbc_dir}/snapshot-fbc-stage-ocp-${fbc_application_suffix}-${component_application}-${epoch}.yaml
cp ${template_dir}/fbc_snapshot.yaml ${fbc_snapshot_yaml_path}
${sed_command} -i "s/{{fbc_component}}/${fbc_component_name}/g" ${fbc_snapshot_yaml_path}
${sed_command} -i "s/{{rhoai_application}}/${component_application}/g" ${fbc_snapshot_yaml_path}
${sed_command} -i "s/{{ocp-version}}/ocp-${fbc_application_suffix}/g" ${fbc_snapshot_yaml_path}
${sed_command} -i "s/{{epoch}}/${epoch}/g" ${fbc_snapshot_yaml_path}
${sed_command} -i "s/{{fbc_fragment_image}}/${FULL_IMAGE_URI_WITH_DIGEST//\//\\/}/g" ${fbc_snapshot_yaml_path}
${sed_command} -i "s/{{git_url}}/${GIT_URL//\//\\/}/g" ${fbc_snapshot_yaml_path}
${sed_command} -i "s/{{git_commit}}/${GIT_COMMIT}/g" ${fbc_snapshot_yaml_path}
${sed_command} -i "s/{{rbc_release_commit}}/${RBC_RELEASE_BRANCH_COMMIT}/g" ${fbc_snapshot_yaml_path}
echo "FBC Snapshots Generated Successfuly at ${fbc_snapshot_yaml_path}"





