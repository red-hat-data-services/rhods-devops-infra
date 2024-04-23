#!/bin/bash

# File containing the repository URL and the path
config_file="./Digest_verifier/repo_url.txt"

# Check if the configuration file exists
if [ ! -f "$config_file" ]; then
  echo "Error: Configuration file not found: $config_file"
  exit 1
fi

# Read the repository URL and path from the file
read -r repo_url file_path < <(cat "$config_file" | awk -F';' '{print $1, $2}')

# Validate that both the URL and the path have been read
if [[ -z "$repo_url" || -z "$file_path" ]]; then
  echo "Error: Repository URL or file path is missing in $config_file"
  exit 1
fi

# Function to fetch the latest branch with a specific pattern, or default to master if not found
fetch_latest_branch() {
  local repo_url="$1"
  local pattern="${2:-rhoai}"
  local branch=$(git ls-remote --heads "$repo_url" | grep "$pattern" | awk -F'/' '{print $NF}' | sort -V | tail -1)
  if [ -z "$branch" ]; then
    echo "No branch matching the pattern '$pattern' found. Defaulting to 'master'."
    branch="master"
  fi
  echo "$branch"
}

# Determine the branch name based on input argument
if [ $# -eq 1 ]; then
  if [ "$1" = "latest" ]; then
    branch_name=$(fetch_latest_branch "$repo_url")
  else
    branch_name="$1"
  fi
else
  branch_name=$(fetch_latest_branch "$repo_url")
fi

echo "Attempting to clone the branch '$branch_name' from '$repo_url' into 'kserve' directory..."

# Clone the specified branch of the repository
git clone --depth 1 -b "$branch_name" "$repo_url" "kserve"
if [ $? -ne 0 ]; then
  echo "Error: Failed to clone branch '$branch_name' from '$repo_url'"
  exit 1
else
  echo "Successfully cloned the branch '$branch_name'."
fi

# Define the full path to the file you want to check in the cloned directory
full_path="kserve/$file_path"

# Initialize a variable to keep track of SHA mismatches
sha_mismatch_found=0

# Function to check SHAs and print results
extract_names_with_att_extension() {
 local tag="$1"
 local repo_hash="$2"

  if [ -z "$hash" ]; then
    echo "Error: The $name image is referenced using floating tags. Exiting..."
    exit 1
 fi

 json_response=$(curl -s https://quay.io/api/v1/repository/modh/$tag/tag/ | jq -r '.tags | .[:3] | map(select(.name | endswith(".att"))) | .[].name')
 local quay_hash=$(echo "$json_response" | sed 's/^sha256-\(.*\)\.att$/\1/')

 if [ "$repo_hash" = "$quay_hash" ]; then
     echo -e "\e[32mRepository SHA ($repo_hash) matches Quay SHA ($quay_hash) for tag: $tag\e[0m"
 else
     echo -e "\e[31mRepository SHA ($repo_hash) does NOT match Quay SHA ($quay_hash) for tag: $tag\e[0m"
     sha_mismatch_found=1
 fi
}

# Main logic for processing the file and SHAs
main() {
 if [ -f "$full_path" ]; then
     echo "File found: $full_path"
     local input=$(<"$full_path")

     while IFS= read -r line; do
         local name=$(echo "$line" | cut -d'=' -f1)
         local hash=$(echo "$line" | awk -F 'sha256:' '{print $2}')
         extract_names_with_att_extension "$name" "$hash"
     done <<< "$input"
 else
     echo "File not found: $full_path"
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