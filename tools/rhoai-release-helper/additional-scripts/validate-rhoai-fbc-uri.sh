#!/bin/bash

# format-uri-for-skopeo.sh should be in the same dir as this file
PATH="$PATH:$(dirname $0)"
URI=$(format-uri-for-skopeo.sh "$1")

echo "Validating $URI"

# all versions on or after $START_MULTI should be multi arch
START_MULTI="2.18"

META=$(skopeo inspect --no-tags "${URI}" --raw)

# when pulling multi arch image raw, it has 
# .mediaType == "application/vnd.oci.image.index.v1+json"
# and has a .manifests array with notable properties [.digest, .platform.architecture, .platform.os]

MEDIA_TYPE=$(echo "$META" | jq -r '.mediaType') 
INPUT_DIGEST=$(skopeo manifest-digest <(echo -n "$META"))

# due to format-uri-for-skopeo.sh, $URI is guaranteed to have a tag or a SHA digest, but not both
BASE_URI=$(echo "$URI" | sed -E 's|docker://(.*)[:@]?.*|\1|')
DIGEST_URI=docker://${BASE_URI}@${INPUT_DIGEST}


IMAGE_TYPE=
if [[ "$MEDIA_TYPE" == "application/vnd.oci.image.index.v1+json" ]]; then
  IMAGE_TYPE=multi
else
  IMAGE_TYPE=single
fi

AMD64_META=$(skopeo inspect --no-tags "${URI}" --override-arch amd64 --override-os linux)

version=$(echo $AMD64_META | jq -r '.Labels.version' | sed 's/^v//')

echo "Detected version '$version' and type '${IMAGE_TYPE}-arch' from image"

version_major=$( echo "$version" | awk -F '.' '{print $1}')
version_minor=$( echo "$version" | awk -F '.' '{print $2}')

START_MULTI_MAJOR=$( echo "$START_MULTI" | awk -F '.' '{print $1}')
START_MULTI_MINOR=$( echo "$START_MULTI" | awk -F '.' '{print $2}')

AFTER_MULTI_TRANSITION=

if [[ ( "$version_major" -ge "$START_MULTI_MAJOR" ) && ( "$version_minor" -ge "$START_MULTI_MINOR" ) ]]; then
  AFTER_MULTI_TRANSITION="true"
else
  AFTER_MULTI_TRANSITION="false"
fi

if [[ ( "$AFTER_MULTI_TRANSITION" == "true" && "$IMAGE_TYPE" == "single" ) || ( "$AFTER_MULTI_TRANSITION" == "false" && "$IMAGE_TYPE" == "multi" ) ]]; then
  echo "Error: Multi-arch incompatibility detected."
  echo "  All versions on or after $START_MULTI should be multi arch"
  exit 1
fi 

if [[ "$IMAGE_TYPE" == "single" ]]; then
  echo "No issues found with $URI"
  exit 0
fi

digests=$(echo "$META" | jq -r '.manifests[].digest') 
RELEASE_BRANCH_COMMIT=
for digest in $digests; do

  arch_uri="$(echo "$DIGEST_URI" | sed 's/@sha.*/@/')$digest"
  arch_release_branch_commit=$(skopeo inspect --no-tags "$arch_uri" | jq -r '.Labels | ."git.commit"')


  if [ -z "$RELEASE_BRANCH_COMMIT" ]; then
    RELEASE_BRANCH_COMMIT=$arch_release_branch_commit
  elif [[ "$RELEASE_BRANCH_COMMIT" != "$arch_release_branch_commit" ]]; then
    echo "Error: Release branch commits are not consistent between arches"
    echo "$META" | jq '.manifests'
    exit 1
  fi
done

echo "No issues found with $URI"
