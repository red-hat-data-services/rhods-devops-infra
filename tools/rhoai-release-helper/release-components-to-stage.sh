#!/bin/bash
#Prerequisites
# yq
# ~/.ssh/.quay_devops_application_token

# Exit on error
set -eo pipefail

release_branch=rhoai-2.18
rhoai_version=2.18.0
hyphenized_rhoai_version=v2-18

#image_uri=LATEST_NIGHTLY
image_uri="http://quay.io/rhoai/rhoai-fbc-fragment:rhoai-2.18@sha256:a032bf4e60d7400c38ea85740f8b447810574459135df5686afdb4830b2ef66f"

# replaces https:// and tag if they are present
image_uri=$(echo $image_uri | sed -E 's|^https?://||' | sed 's/:.*@/@/')

FBC_QUAY_REPO=quay.io/rhoai/rhoai-fbc-fragment
RBC_URL=https://github.com/red-hat-data-services/RHOAI-Build-Config


if [[ $image_uri == LATEST_NIGHTLY ]]; then image_uri=docker://${FBC_QUAY_REPO}:${release_branch}-nightly; fi
if [[ "$image_uri" != docker* ]]; then image_uri="docker://${image_uri}"; fi

META=$(skopeo inspect "${image_uri}" --override-arch amd64 --override-os linux)
DIGEST=$(echo $META | jq -r .Digest)
image_uri=${FBC_QUAY_REPO}@${DIGEST}
RBC_RELEASE_BRANCH_COMMIT=$(echo $META | jq -r '.Labels | ."git.commit"')
SHORT_COMMIT=${RBC_RELEASE_BRANCH_COMMIT::8}

echo "RBC_RELEASE_BRANCH_COMMIT = ${RBC_RELEASE_BRANCH_COMMIT}"
echo "Pushing the components to stage for nightly - ${image_uri}"
echo "starting to create the artifacts corresponding to the sourcecode at ${RBC_URL}/tree/${RBC_RELEASE_BRANCH_COMMIT}"
#


component_application=rhoai-${hyphenized_rhoai_version}

fbc_application_prefix=rhoai-fbc-fragment-ocp-

RHOAI_QUAY_API_TOKEN=$(cat ~/.ssh/.quay_devops_application_token)

current_dir=$(pwd)
#workspace=/tmp/tmp.68Vts9xj27
#epoch=1732618870

workspace=$(mktemp -d)
echo "workspace=${workspace}"

epoch=$(date +%s)
release_artifacts_dir=stage-release-${SHORT_COMMIT}
release_components_dir=${release_artifacts_dir}/release-components
snapshot_components_dir=${release_artifacts_dir}/snapshot-components

mkdir -p ${release_components_dir}
mkdir -p ${snapshot_components_dir}

# Function to delete the directories if an error occurs. This is to prevent the creation of duplicate manifests during re-runs.
cleanup() {
    echo "*****************************************************************************************"
    echo "Error occurred at line $1".
    echo "Failed Command: $BASH_COMMAND"
    echo "*****************************************************************************************"
    echo "Initializing Cleanup..."
    set -x
    rm -rf "${workspace}"
    rm -rf "${release_components_dir}"
    rm -rf "${snapshot_components_dir}"
    set +x
    echo "Cleanup successfull."
}

# Set trap to call cleanup on script exit, but only if the exit code is non-zero
trap 'if [ $? -ne 0 ]; then cleanup $LINENO; fi' EXIT

template_dir=templates/stage

#RBC_RELEASE_BRANCH_COMMIT=7da42450e089babe0dc31f182e78152c349f201a


RBC_RELEASE_DIR=${workspace}/RBC_${release_branch}_commit
V417_CATALOG_YAML_PATH=catalog/v4.17/rhods-operator/catalog.yaml
mkdir -p ${RBC_RELEASE_DIR}
cd ${RBC_RELEASE_DIR}
git config --global init.defaultBranch ${release_branch}
git init -q
git remote add origin $RBC_URL
git config core.sparseCheckout true
git config core.sparseCheckoutCone false
mkdir -p .git/info
echo "${V417_CATALOG_YAML_PATH}" >> .git/info/sparse-checkout
git fetch -q --depth=1 origin ${RBC_RELEASE_BRANCH_COMMIT}
git checkout -q ${RBC_RELEASE_BRANCH_COMMIT}
CATALOG_YAML_PATH=${RBC_RELEASE_DIR}/${V417_CATALOG_YAML_PATH}
cd ${current_dir}

RBC_RELEASE_DIR=${workspace}/RBC_${release_branch}_commit
V417_CATALOG_YAML_PATH=catalog/v4.17/rhods-operator/catalog.yaml
CATALOG_YAML_PATH=${RBC_RELEASE_DIR}/${V417_CATALOG_YAML_PATH}

RHOAI_KONFLUX_COMPONENTS_DETAILS_FILE_PATH=${workspace}/konflux_components.txt

echo "*****************************************************************************************"
echo "                   Generating Release Artifacts For Components                           "
echo "*****************************************************************************************"
echo
echo ">> Fetching Components details for konflux application '${component_application}'"
echo "-----------------------------------------------------------------------------------------"
kubectl get components -o=jsonpath="{range .items[?(@.spec.application=='${component_application}')]}{@.metadata.name}{'\t'}{@.spec.containerImage}{'\n'}{end}" > ${RHOAI_KONFLUX_COMPONENTS_DETAILS_FILE_PATH}
cat ${RHOAI_KONFLUX_COMPONENTS_DETAILS_FILE_PATH}
echo

echo ">> Invoking Release Processor with below arguments"
echo "-----------------------------------------------------------------------------------------"
echo "--catalog-yaml-path ${CATALOG_YAML_PATH}"
echo "--konflux-components-details-file-path ${RHOAI_KONFLUX_COMPONENTS_DETAILS_FILE_PATH}"
echo "--rhoai-version ${rhoai_version}"
echo "--rhoai-application ${component_application}"
echo "--epoch ${epoch} --output-dir"
echo "--output-dir ${release_artifacts_dir}"
echo "--template-dir ${template_dir}"
echo "--rbc-release-commit ${RBC_RELEASE_BRANCH_COMMIT}"
echo "-----------------------------------------------------------------------------------------"
RHOAI_QUAY_API_TOKEN=${RHOAI_QUAY_API_TOKEN} python release_processor.py --operation generate-release-artifacts --catalog-yaml-path ${CATALOG_YAML_PATH} --konflux-components-details-file-path ${RHOAI_KONFLUX_COMPONENTS_DETAILS_FILE_PATH} --rhoai-version ${rhoai_version} --rhoai-application ${component_application} --epoch ${epoch} --output-dir ${release_artifacts_dir} --template-dir ${template_dir} --rbc-release-commit ${RBC_RELEASE_BRANCH_COMMIT}
echo
echo ">> Artifacts Generated Successfully!"
echo

confirm_message="Please verify that you have done the following:
- all internal components are green
- all external components are green
- all nudges are verified
- testops has run smoke tests on nightly
Do you want to initiate push to staging? (y/n): "

# After the release artifacts are generated, prompt for confirmation
read -p "$confirm_message"  user_input


if [[ "$user_input" == "y" || "$user_input" == "Y" ]]; then
    echo
    echo "*****************************************************************************************"
    echo " Creating the required resources for the release..."
    echo "*****************************************************************************************"
    echo
    cd ${release_artifacts_dir}

    #Create components snapshot
    oc apply -f snapshot-components

    sleep 5
    #Start components release
    oc apply -f release-components

    sleep 10
    echo "All required resources have been successfully created. Release Pipelines have been triggered."
    echo -en "1. Please watch following pipelinerun until green \n2. Run the FBC push to stage for image ${image_uri}\n"
    oc get pipelinerun -n rhtap-releng-tenant -l appstudio.openshift.io/snapshot=${component_application}-${epoch}

else
    echo "Aborting push to staging..."
fi

# cleanup workspace before exiting
rm -rf "${workspace}"
