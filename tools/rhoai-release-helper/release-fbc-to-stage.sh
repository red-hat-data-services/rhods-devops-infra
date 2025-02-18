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

IFS='.' read -a parts <<< "$rhoai_version"
micro_version=${parts[2]}

if [[ $image_uri == LATEST_NIGHTLY ]]; then image_uri=docker://${FBC_QUAY_REPO}:${release_branch}-nightly; fi
if [[ "$image_uri" != docker* ]]; then image_uri="docker://${image_uri}"; fi

META=$(skopeo inspect "${image_uri}")
DIGEST=$(echo $META | jq -r .Digest)
image_uri=${FBC_QUAY_REPO}@${DIGEST}
RBC_RELEASE_BRANCH_COMMIT=$(echo $META | jq -r '.Labels | ."git.commit"')
SHORT_COMMIT=${RBC_RELEASE_BRANCH_COMMIT::8}

echo "RBC_RELEASE_BRANCH_COMMIT = ${RBC_RELEASE_BRANCH_COMMIT}"
echo "Pushing the FBC to stage for nightly - ${image_uri}"
echo "starting to create the artifacts corresponding to the sourcecode at ${RBC_URL}/tree/${RBC_RELEASE_BRANCH_COMMIT}"

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
release_fbc_dir=${release_artifacts_dir}/release-fbc
release_fbc_addon_dir=${release_artifacts_dir}/release-fbc-addon
snapshot_fbc_dir=${release_artifacts_dir}/snapshot-fbc

mkdir -p ${release_fbc_dir}
mkdir -p ${release_fbc_addon_dir}
mkdir -p ${snapshot_fbc_dir}

# Function to delete the directories if an error occurs. This is to prevent the creation of duplicate manifests during re-runs.
cleanup() {
    echo "*****************************************************************************************"
    echo "Error occurred at line $1".
    echo "Failed Command: $BASH_COMMAND"
    echo "*****************************************************************************************"
    echo "Initializing Cleanup..."
    set -x
    rm -rf "${workspace}"
    rm -rf "${release_fbc_dir}"
    rm -rf "${release_fbc_addon_dir}"
    rm -rf "${snapshot_fbc_dir}"
    set +x
    echo "Cleanup successful!"
}

# Set trap to call cleanup on script exit, but only if the exit code is non-zero
trap 'if [ $? -ne 0 ]; then cleanup $LINENO; fi' EXIT

template_dir=templates/stage

RBC_RELEASE_DIR=${workspace}/RBC_${release_branch}_main
mkdir -p ${RBC_RELEASE_DIR}
cd ${RBC_RELEASE_DIR}
git config --global init.defaultBranch ${release_branch}
git init -q
git remote add origin $RBC_URL
git config core.sparseCheckout true
git config core.sparseCheckoutCone false
mkdir -p .git/info
echo "config/build-config.yaml" >> .git/info/sparse-checkout
git fetch -q --depth=1 origin ${release_branch}
git checkout -q ${release_branch}
#git clone -q ${RBC_URL} --branch ${release_branch} ${RBC_RELEASE_DIR}
BUILD_CONFIG_PATH=${RBC_RELEASE_DIR}/config/build-config.yaml
cd ${current_dir}


ocp_versions_array=()
while IFS= read -r version; do
  ocp_versions_array+=("$version")
done < <(yq eval '.config.supported-ocp-versions.release[]' $BUILD_CONFIG_PATH)

echo "*****************************************************************************************"
printf "Generating FBC Artifacts For OCP Versions: $(printf "\"%s\" " "${ocp_versions_array[@]}")\n"
echo "*****************************************************************************************"

first_ocp_version=$(echo ${ocp_versions_array[0]} | tr -d '\n')
fbc_application_tag=ocp-${first_ocp_version/v4/4}-${release_branch}


for ocp_version in "${ocp_versions_array[@]}"; do
  fbc_application_suffix=${ocp_version/v4./4}
  fbc_application_name=${fbc_application_prefix}${fbc_application_suffix}
  fbc_application_tag=ocp-${ocp_version/v4/4}-${release_branch}
  echo "fbc_application_name=${fbc_application_name}"
  echo "fbc_application_tag=${fbc_application_tag}"

  image_uri=docker://${FBC_QUAY_REPO}:${fbc_application_tag}
  META=$(skopeo inspect "${image_uri}")
  DIGEST=$(echo $META | jq -r .Digest)
  FULL_IMAGE_URI_WITH_DIGEST="${FBC_QUAY_REPO}@${DIGEST}"
  echo "FBCF-${ocp_version} - ${FULL_IMAGE_URI_WITH_DIGEST}"
  RBC_CURRENT_COMMIT=$(echo $META | jq -r '.Labels | ."rbc-release-branch.commit"')
  GIT_URL=$(echo $META | jq -r '.Labels | ."git.url"')
  GIT_COMMIT=$(echo $META | jq -r '.Labels | ."git.commit"')

  if [[ ${RBC_CURRENT_COMMIT} != ${RBC_RELEASE_BRANCH_COMMIT} ]]
  then
    echo "Stage FBC images are out of sync, it might be because push-to-stage is in progress, please try after sometime or contact the DevOps team.."
    exit 1
  fi

  echo "Generating FBC Release CRs..."
  fbc_release_yaml_path=${release_fbc_dir}/release-fbc-stage-ocp-${fbc_application_suffix}-${component_application}-${epoch}.yaml
  cp ${template_dir}/release-fbc-stage.yaml ${fbc_release_yaml_path}
  ${sed_command} -i "s/{{fbc_application}}/${fbc_application_name}/g" ${fbc_release_yaml_path}
  ${sed_command} -i "s/{{epoch}}/${epoch}/g" ${fbc_release_yaml_path}
  ${sed_command} -i "s/{{ocp-version}}/ocp-${fbc_application_suffix}/g" ${fbc_release_yaml_path}
  ${sed_command} -i "s/{{hyphenized-rhoai-version}}/${hyphenized_rhoai_version}/g" ${fbc_release_yaml_path}
  ${sed_command} -i "s/{{rbc_release_commit}}/${RBC_RELEASE_BRANCH_COMMIT}/g" ${fbc_release_yaml_path}
  echo "FBC Release CRs Generated Successfuly at ${fbc_release_yaml_path}"

  #addon FBC release will be created only for minor versions
  if [[ "${fbc_application_suffix}" == "416" ]] && [[ $micro_version -eq 0 ]]
  then
    echo ">> [Add-on FBC] Generating Addon FBC Release CRs..."
    fbc_addon_release_yaml_path=${release_fbc_addon_dir}/release-fbc-addon-stage-ocp-${fbc_application_suffix}-${component_application}-${epoch}.yaml
    cp ${template_dir}/release-fbc-addon-stage.yaml ${fbc_addon_release_yaml_path}
    ${sed_command} -i "s/{{fbc_application}}/${fbc_application_name}/g" ${fbc_addon_release_yaml_path}
    ${sed_command} -i "s/{{epoch}}/${epoch}/g" ${fbc_addon_release_yaml_path}
    ${sed_command} -i "s/{{ocp-version}}/ocp-${fbc_application_suffix}/g" ${fbc_addon_release_yaml_path}
    ${sed_command} -i "s/{{hyphenized-rhoai-version}}/${hyphenized_rhoai_version}/g" ${fbc_addon_release_yaml_path}
    ${sed_command} -i "s/{{rbc_release_commit}}/${RBC_RELEASE_BRANCH_COMMIT}/g" ${fbc_addon_release_yaml_path}
    echo "Addon FBC Release CR Generated Successfuly at ${fbc_addon_release_yaml_path}"
  fi

  echo "Generating FBC Snapshots..."
  fbc_snapshot_yaml_path=${snapshot_fbc_dir}/snapshot-fbc-stage-ocp-${fbc_application_suffix}-${component_application}-${epoch}.yaml
  cp ${template_dir}/fbc_snapshot.yaml ${fbc_snapshot_yaml_path}
  ${sed_command} -i "s/{{fbc_application}}/${fbc_application_name}/g" ${fbc_snapshot_yaml_path}
  ${sed_command} -i "s/{{ocp-version}}/ocp-${fbc_application_suffix}/g" ${fbc_snapshot_yaml_path}
  ${sed_command} -i "s/{{epoch}}/${epoch}/g" ${fbc_snapshot_yaml_path}
  ${sed_command} -i "s/{{fbc_fragment_image}}/${FULL_IMAGE_URI_WITH_DIGEST//\//\\/}/g" ${fbc_snapshot_yaml_path}
  ${sed_command} -i "s/{{git_url}}/${GIT_URL//\//\\/}/g" ${fbc_snapshot_yaml_path}
  ${sed_command} -i "s/{{git_commit}}/${GIT_COMMIT}/g" ${fbc_snapshot_yaml_path}
  ${sed_command} -i "s/{{rbc_release_commit}}/${RBC_RELEASE_BRANCH_COMMIT}/g" ${fbc_snapshot_yaml_path}
  echo "FBC Snapshots Generated Successfuly at ${fbc_snapshot_yaml_path}"
  echo

done

echo
echo ">> Artifacts Generated Successfully! All FBC images tag are matching!"
echo

confirm_message="Please verify that you have done the following:
- all FBC Fragment pipelines are green
- all EC tests are green for FBCF stage builds
Do you want to initiate push to staging? (y/n): "

# After the release artifacts are generated, prompt for confirmation
read -p "$confirm_message" user_input


if [[ "$user_input" == "y" || "$user_input" == "Y" ]]; then

    echo "*****************************************************************************************"
    echo " Creating the required resources for the release..."
    echo "*****************************************************************************************"
    echo
    #RBC_RELEASE_BRANCH_COMMIT=7da42450e089babe0dc31f182e78152c349f201a
    cd ${release_artifacts_dir}

    #Create all the FBC snapshots for onprem
    oc apply -f snapshot-fbc

    #Start all the FBC releases for onprem
    oc apply -f release-fbc

    #Start addon FBC release
    oc apply -f release-fbc-addon

    sleep 10
    echo
    echo ">> All required resources have been successfully created. Release Pipelines have been triggered."
    echo ">> Please ensure following pipelines are green:"
    for ocp_version in "${ocp_versions_array[@]}"; do
      fbc_application_suffix=${ocp_version/v4./4}
      fbc_application_name=${fbc_application_prefix}${fbc_application_suffix}
      echo "${fbc_application_name}"
      oc get pipelinerun -n rhtap-releng-tenant -l appstudio.openshift.io/snapshot=${fbc_application_name}-${epoch}
    done

else
    echo "Aborting push to staging..."
fi

# cleanup workspace before exiting
rm -rf "${workspace}"
