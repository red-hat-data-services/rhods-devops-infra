#!/bin/bash
export > /dev/null 2>&1


RBC_REPO=https://github.com/red-hat-data-services/RHOAI-Build-Config
BUILD_TYPE=ci
IMAGE_TYPE=fbc
QUAY_BASE_URL="docker://quay.io/rhoai"
FBC_QUAY_REPO="rhoai-fbc-fragment"
BUNDLE_QUAY_REPO="odh-operator-bundle"
TAG=
DIGEST=
SHOW_COMMITS=
SEARCH_PARAM=
IMAGE=
CONFIGURE=
UPDATE=
IMAGE_URI=
FULL_IMAGE_URI_WITH_DIGEST=
TEXT_OUTPUT=
if [[ -z $SKOPEO_TOKEN_FILE_PATH ]]; then SKOPEO_TOKEN_FILE_PATH=~/.ssh/.rhoai_quay_ro_token; fi

function help() {
  echo "Usage: tracer.sh [-h] [-v] [-c] [-s] [-n] [-b] [configure] [update]"
  echo "  -h, --help - Display this help message"
  echo "  -v, --rhoai-version - RHOAI version to get the build info for, valid formats are X.Y or rhoai-X.Y or vX.Y, optional, default value is latest RHOAI version"
  echo "  -d, --digest - Complete digest of the image to be provided as an input, optional, if rhoai-verson and digest both are provided then digest will take precedence"
  echo "  -c --show-commits - Show the commits info for all the components, by default only basic info is shown"
  echo "  -s --search - search to see if a particular code commit is in the build.  Use the format REPO_NAME/SHA, where REPO_NAME and SHA can both be partial matches"
  echo "  -n --nightly - Show the info of latest nightly build, by default the CI-build info is shown"
  echo "  -b --bundle - Show the info about operator bundle image, by default it will show the FBC image info"
  echo "  -i --image - Complete URI of the image to be provided as an input, optional, if image and digest both are provided then image will take precedence, it suppports all the image formats - :tag, @sha256:digest and :tag@sha256:digest"
  echo " configure - To configure the tracer and skopeo as needed"
  echo " update - To update the tracer to latest version available in the repo"
}


POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --help | -h)
        help
        exit
        ;;
        --rhoai-version | -v)
        TAG="$2"
        shift
        shift
        ;;
        --digest | -d)
        DIGEST="$2"
        shift
        shift
        ;;
        --nightly | -n)
        BUILD_TYPE=nightly
        shift
        ;;
        --show-commits | -c)
        SHOW_COMMITS=true
        shift
        ;;
        --search | -s)
        SEARCH_PARAM=$2
        shift
        shift
        ;;
        --bundle | -b)
        IMAGE_TYPE=bundle
        shift
        ;;
        --image | -i)
        IMAGE="$2"
        shift
        shift
        ;;
        configure)
        CONFIGURE=true
        shift
        ;;
        update)
        UPDATE=true
        shift
        ;;
        *)
        echo -n "Invalid arguments, please check the usage doc"
        help
        exit 1
        ;;
    esac
done


if [[ $CONFIGURE == "true" ]]
then
  auth=$(cat $SKOPEO_TOKEN_FILE_PATH | base64 -d)
  IFS=':' read -a parts <<< "$auth"
  skopeo login -u "${parts[0]}" -p "${parts[1]}" quay.io/rhoai
  exit
fi

if [[ $UPDATE == "true" ]]
then
  git_url=git@github.com:red-hat-data-services/rhods-devops-infra.git
  current_script_path=$(realpath $0)
  current_dir=$(dirname "${current_script_path}")
  temp=$(mktemp -d)
  cd $temp
  git config --global init.defaultBranch main
  git init
  git remote add origin $git_url
  git config core.sparseCheckout true
  git config core.sparseCheckoutCone false
  echo "tools/tracer" >> .git/info/sparse-checkout
  git fetch --depth=1 origin main
  git checkout main
  cp tools/tracer/tracer.sh "${current_script_path}"
  echo "Tracer is updated successfully!"
  cd $current_dir
  rm -rf $temp
  exit
fi

if [[ -z $TAG ]]; then TAG=$(git ls-remote --heads $RBC_REPO | grep 'rhoai' | awk -F'/' '{print $NF}' | sort -V | tail -1); fi
if [[ -z $IMAGE ]]
then
  IMAGE_TYPE=$(echo $IMAGE_TYPE | tr '[a-z]' '[A-Z]')
  BUILD_TYPE=$(echo $BUILD_TYPE | tr '[a-z]' '[A-Z]')
  IMAGE_MANIFEST=
  QUAY_REPO=

  if [[ -n $DIGEST ]]
  then
    if [[ "$DIGEST" != sha256* ]]; then DIGEST="sha256:${DIGEST}"; fi
    IMAGE_MANIFEST="@$DIGEST"
  elif [[ -n $TAG ]]
  then
    #TAG=$(echo $TAG | tr '[a-z]' '[A-Z]')
    if [[ "$TAG" == v* ]]; then TAG=$(echo $TAG | tr -d 'v'); fi
    if [[ "$TAG" != rhoai* ]]; then TAG="rhoai-${TAG}"; fi
    if [[ "$BUILD_TYPE" == "NIGHTLY" ]]; then TAG="${TAG}-nightly"; fi
    IMAGE_MANIFEST=":$TAG"
  fi
  if [[ $IMAGE_TYPE == "FBC" ]]; then QUAY_REPO=$FBC_QUAY_REPO; elif [[ $IMAGE_TYPE == "BUNDLE" ]]; then QUAY_REPO=$BUNDLE_QUAY_REPO; fi

  IMAGE_URI="${QUAY_BASE_URL}/${QUAY_REPO}${IMAGE_MANIFEST}"
  FULL_IMAGE_URI_WITH_DIGEST="${QUAY_BASE_URL}/${QUAY_REPO}"


else
  IMAGE_URI=${IMAGE/http:\/\//}
  IMAGE_URI=$(echo $IMAGE_URI | sed -e 's/:rhoai-2.*@/@/g')
  if [[ "$IMAGE_URI" != docker* ]]; then IMAGE_URI="docker://${IMAGE_URI}"; fi
  FULL_IMAGE_URI_WITH_DIGEST=$IMAGE_URI
fi

if [[ -n $IMAGE_URI ]]
then
  META=$(skopeo inspect "${IMAGE_URI}")
  NAME=$(echo $META | jq -r .Name)
  IFS='/' read -a parts <<< "$NAME"
  CURRENT_COMPONENT="${parts[2]}"
  DIGEST=$(echo $META | jq -r .Digest)

  labels=$(echo $META | jq .Labels)

  FULL_IMAGE_URI_WITH_DIGEST="${NAME}@${DIGEST}"
  BUILD_DATE=$(echo $labels | jq -r '."build-date"')
  VERSION=$(echo $labels | jq -r '."version"')

  TEXT_OUTPUT="${TEXT_OUTPUT}Image-URI ${FULL_IMAGE_URI_WITH_DIGEST}\n"
  TEXT_OUTPUT="${TEXT_OUTPUT}Build-Date ${BUILD_DATE}\n"
  TEXT_OUTPUT="${TEXT_OUTPUT}RHOAI-Version ${VERSION}\n"

  if [[ "$SHOW_COMMITS" == "true" ]]
  then
    declare -a COMPONENTS=()
    while read -r key;
    do
      if [[ "$key" == *git.url ]]
      then
        if [[ $key == "git.url" ]]; then component="${CURRENT_COMPONENT}"; else component="${key/.git.url/}"; fi
        COMPONENTS+=($component)
      fi
      #echo $key=$(echo $labels | jq  --arg key "$key" -r '"\(.[$key])"')
    done < <(echo $labels | jq -r "keys[]")

    for component in "${COMPONENTS[@]}"
    do
      if [[ $component != "${CURRENT_COMPONENT}" ]]; then url_key="$component.git.url"; commit_key="$component.git.commit"; else url_key="git.url"; commit_key="git.commit"; fi
      URL=$(echo $labels | jq  --arg url_key "$url_key" -r '"\(.[$url_key])"')
      COMMIT=$(echo $labels | jq  --arg commit_key "$commit_key" -r '"\(.[$commit_key])"')

      TEXT_OUTPUT="${TEXT_OUTPUT}${component} ${URL}/tree/${COMMIT}\n"
    done
  fi
  echo -e "$TEXT_OUTPUT" | column -t

  
  if [[ -n $SEARCH_PARAM ]] 
  then
    
    SEARCH_REPO=$(echo $SEARCH_PARAM | grep -o '^.*/' | sed 's|/$||' )
    SEARCH_SHA=$(echo $SEARCH_PARAM | sed 's|^.*/||' | awk '{print tolower($0)}')
    COMPONENTS=$( echo $labels | jq -r 'keys[] | select(test(".*\\.git\\.url"))' |  sed 's/\.git\.url//' )
    FOUND_RESULT=false
    FOUND_MATCHING_REPO=false
    QUERIES=
    REPOS=
    for component in $COMPONENTS
    do  
      url_key="$component.git.url"; commit_key="$component.git.commit";
      
      URL=$(echo $labels | jq  --arg url_key "$url_key" -r '"\(.[$url_key])"')
      ORG_REPO=$( echo $URL | sed 's|^https://[^/]*/||' | sed 's/.git$//' )
      COMMIT=$(echo $labels | jq  --arg commit_key "$commit_key" -r '"\(.[$commit_key])"')
      if [[ $ORG_REPO =~ $SEARCH_REPO ]] 
      then
        FOUND_MATCHING_REPO=true
      else
        continue
      fi 
 
      API_URL="https://api.github.com/repos/${ORG_REPO}/commits?sha=${COMMIT}&per_page=100"
      if [[ -n $(echo "$QUERIES" |  grep "$API_URL" ) ]]
      then
        # echo "skipped $API_URL" 
        continue
      fi  
      QUERIES+=" $API_URL"
      REPOS+="\n$ORG_REPO"  
      API_RESPONSE=$(curl -s ${API_URL} )
      SEARCH_RESULT=$( echo $API_RESPONSE | jq --arg x "$SEARCH_SHA" -r '.[] | select(.sha | test($x))')
      if [[ $? -ne 0 ]]
      then
        echo "error with github API call"
        echo "component: $component"
        echo "repo: $URL"
        echo "error message:"
        echo $API_RESPONSE
        exit 1
      fi
      
      if [[ -n $SEARCH_RESULT ]] 
      then
        echo -e "\nFound commit SHA matching '$SEARCH_SHA' in $ORG_REPO:\n" 
        cat <<EOF | column -t -s '%' 
----
component% $component
source% ${URL}/tree/${COMMIT}
----
commit% $( echo $SEARCH_RESULT | jq -r '.html_url')
date% $( echo $SEARCH_RESULT | jq -r '.commit.author.date' )
author% $( echo $SEARCH_RESULT | jq -r '.commit.author.name' )
EOF
        echo "message: "
        echo "$SEARCH_RESULT" | jq -r '.commit.message' 
        echo "----"
        FOUND_RESULT=true
      fi
    done 
    if [[ "$FOUND_MATCHING_REPO" == "false" ]]
    then
			echo "Did not find any components with a source repo matching '$SEARCH_REPO'"
    elif [[ "$FOUND_RESULT" == "false" ]]
    then
      echo -e "\nCommit SHA search term $SEARCH_PARAM was not found in the latest 100 commits of the following repos: "
      echo -e "$REPOS"
    fi
  fi

else
  echo "Image is not found"
fi
