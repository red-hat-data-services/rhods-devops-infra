#!/bin/bash

# Path to the file containing the repository URL
REPO_URL_FILE="Digest_verifier/repo_url.txt"

# Check if the repository URL file exists
if [ ! -f "$REPO_URL_FILE" ]; then
  echo "Error: Repository URL file not found: $REPO_URL_FILE"
  exit 1
fi

# Read the repository URL from the file
REPO_URL=$(cat "$REPO_URL_FILE")

# Check if a branch name was provided as an argument
if [ $# -eq 1 ]; then
  BRANCH_NAME="$1"
  if [ "$BRANCH_NAME" = "latest" ]; then
    # Fetch the latest branch name matching 'rhoai' from the remote repository
    BRANCH_NAME=$(git ls-remote --heads $REPO_URL | grep 'rhoai' | awk -F'/' '{print $NF}' | sort -V | tail -1)
    if [ -z "$BRANCH_NAME" ]; then
      echo "Error: Unable to determine the latest branch name."
      exit 1
    fi
  fi
else
  # Default to the latest 'rhoai' branch if no argument is provided
  BRANCH_NAME=$(git ls-remote --heads $REPO_URL | grep 'rhoai' | awk -F'/' '{print $NF}' | sort -V | tail -1)
  if [ -z "$BRANCH_NAME" ]; then
    echo "Error: Unable to determine the latest branch name."
    exit 1
  fi
fi

echo "Attempting to clone the branch '$BRANCH_NAME' from '$REPO_URL' into 'kserve' directory..."

# Clone the specified branch of the repository
git clone --depth 1 -b "$BRANCH_NAME" "$REPO_URL" "kserve"
if [ $? -ne 0 ]; then
  echo "Error: Failed to clone branch '$BRANCH_NAME' from '$REPO_URL'"
  exit 1
else
  echo "Successfully cloned the branch '$BRANCH_NAME'."
fi


# Define the path to the file you want to check in the cloned directory
FILE_PATH="kserve/config/overlays/odh/params.env"

# Initialize a variable to keep track of SHA mismatches
sha_mismatch_found=0

# Function to check SHAs and print results
extract_names_with_sbom_extension() {
 local tag="$1"
 local hash="$2"

 json_response=$(curl -s https://quay.io/api/v1/repository/modh/$tag/tag/ | jq -r '.tags | .[:3] | map(select(.name | endswith(".sbom"))) | .[].name')
 local names_part=$(echo "$json_response" | sed 's/^sha256-\(.*\)\.sbom$/\1/')
 echo "$names_part"

 if [ "$hash" = "$names_part" ]; then
     # Print in green if equal
     echo "$tag"
     echo -e "\e[32m$hash\e[0m matches \e[32m$names_part\e[0m"
 else
     # Print in red if not equal
     echo "$tag"
     echo -e "\e[31m$hash\e[0m does not match \e[31m$names_part\e[0m"
     sha_mismatch_found=1
 fi
}

# Main logic for processing the file and SHAs
main() {
 if [ -f "$FILE_PATH" ]; then
     echo "File found: $FILE_PATH"
     local input=$(<"$FILE_PATH")

     while IFS= read -r line; do
         local name=$(echo "$line" | cut -d'=' -f1)
         local hash=$(echo "$line" | awk -F 'sha256:' '{print $2}')
         extract_names_with_sbom_extension $name $hash
     done <<< "$input"
 else
     echo "File not found: $FILE_PATH"
 fi

 # Check if any SHA mismatches were found
 if [ "$sha_mismatch_found" -ne 0 ]; then
     echo "One or more SHA mismatches were found."
     exit 1
 else
     echo "All SHA hashes match."
 fi
}

# Execute the main logic
main