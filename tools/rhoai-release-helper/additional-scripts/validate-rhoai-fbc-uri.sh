#!/bin/bash

# format-uri-for-skopeo.sh should be in the same dir as this file
PATH="$PATH:$(dirname $0)"
URI=$(format-uri-for-skopeo.sh "$1")

echo "Validating properties of $URI..."

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
  echo "Detected image type: multiarch"
else
  IMAGE_TYPE=single
  echo "Detected image type: single arch"
fi

AMD64_META=$(skopeo inspect --no-tags "${URI}" --override-arch amd64 --override-os linux)

version=$(echo $AMD64_META | jq -r '.Labels.version' | sed 's/^v//')

echo "Detected version from image: $version"

version_major=$( echo "$version" | awk -F '.' '{print $1}')
version_minor=$( echo "$version" | awk -F '.' '{print $2}')

START_MULTI="2.18"
START_MULTI_MAJOR=$( echo "$START_MULTI" | awk -F '.' '{print $1}')
START_MULTI_MINOR=$( echo "$START_MULTI" | awk -F '.' '{print $2}')

AFTER_MULTI_TRANSITION=

if [[ ( "$version_major" -ge "$START_MULTI_MAJOR" ) && ( "$version_minor" -ge "$START_MULTI_MINOR" ) ]]; then
  echo "Version $version should be multi arch because it is on or after $START_MULTI"
  AFTER_MULTI_TRANSITION="true"
else
  echo "Version $version should be single arch because it is before $START_MULTI "
  AFTER_MULTI_TRANSITION="false"
fi

if [[ ( "$AFTER_MULTI_TRANSITION" == "true" && "$IMAGE_TYPE" == "single" ) || ( "$AFTER_MULTI_TRANSITION" == "false" && "$IMAGE_TYPE" == "multi" ) ]]; then
  echo "Error: Multi-arch incompatibility detected"
  exit 1
fi 

if [[ "$IMAGE_TYPE" == "single" ]]; then
  echo "No issues found"
  exit 0
fi

digests=$(echo "$META" | jq -r '.manifests[].digest') 
RELEASE_BRANCH_COMMIT=
for digest in $digests; do
  arch=$(echo "$META" | jq -r --arg X "$digest" '.manifests[] | select(.digest==$X) | .platform.architecture')

  arch_uri="$(echo "$DIGEST_URI" | sed 's/@sha.*/@/')$digest"
  arch_release_branch_commit=$(skopeo inspect --no-tags "$arch_uri" | jq -r '.Labels | ."git.commit"')

  echo -e "Variant $arch metadata has commit:\t$arch_release_branch_commit"

  if [ -z "$RELEASE_BRANCH_COMMIT" ]; then
    RELEASE_BRANCH_COMMIT=$arch_release_branch_commit
  elif [[ "$RELEASE_BRANCH_COMMIT" != "$arch_release_branch_commit" ]]; then
    echo "Error: Release branch commits are not consistent between arches"
    exit 1
  fi
done

echo "No issues found"
