#!/bin/bash

# File containing the repository URL and the path
config_file="./Digest_verifier/repo_url.txt"

# Check if the configuration file exists
if [ ! -f "$config_file" ]; then
  echo "Error: Configuration file not found: $config_file"
  exit 1
fi

# Function to fetch the latest branch with a specific pattern.
fetch_latest_branch() {
  local repo_url="$1"
  local pattern="${2:-rhoai}"
  local branch
  branch=$(git ls-remote --heads "$repo_url" | grep "$pattern" | awk -F'/' '{print $NF}' | sort -V | tail -1)
  if [ -z "$branch" ]; then
    echo "No branch matching the pattern '$pattern' found."
    exit 1
  fi
  echo "$branch"
}

# Function to check SHAs and print results
extract_names_with_att_extension() {
  local name="$1"
  local repo_hash="$2"
  local pattern="$3"

  echo "Checking image: $name with repo SHA: $repo_hash and pattern: $pattern"

  if [ -z "$repo_hash" ]; then
    echo "Error: The $name image is referenced using floating tags. Exiting..."
    sha_mismatch_found=1
    return
  fi

  # Attempt to fetch Quay SHA for the given tag pattern
  echo "Attempting to fetch Quay SHA for tag: $name with pattern: $pattern"
  local quay_hash
  quay_hash=$(skopeo inspect docker://quay.io/modh/$name:$pattern | jq -r '.Digest' | cut -d':' -f2)

  if [ -z "$quay_hash" ]; then
    echo -e "\e[31mError: Quay SHA could not be fetched for tag: $name with pattern: $pattern\e[0m"
    sha_mismatch_found=1
    return
  fi

  if [ "$repo_hash" = "$quay_hash" ]; then
    echo -e "\e[32mRepository SHA ($repo_hash) matches Quay SHA ($quay_hash) for tag: $name with pattern: $pattern\e[0m"
  else
    echo -e "\e[31mRepository SHA ($repo_hash) does NOT match Quay SHA ($quay_hash) for tag: $name with pattern: $pattern\e[0m"
    sha_mismatch_found=1
  fi
}

# Main logic for processing the file and SHAs for each repository
process_repo() {
  local repo_url="$1"
  local file_path="$2"
  local branch_name="$3"

  echo "Attempting to clone the branch '$branch_name' from '$repo_url' into 'kserve' directory..."

  # Clone the specified branch of the repository
  git clone --depth 1 -b "$branch_name" "$repo_url" "kserve"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to clone branch '$branch_name' from '$repo_url'"
    return 1
  else
    echo "Successfully cloned the branch '$branch_name'."
  fi

  # Define the full path to the file you want to check in the cloned directory
  local full_path="kserve/$file_path"

  # Initialize a variable to keep track of SHA mismatches
  sha_mismatch_found=0

  if [ -f "$full_path" ]; then
    echo "File found: $full_path"
    local input
    input=$(<"$full_path")

    while IFS= read -r line; do
      local name
      local hash
      name=$(echo "$line" | cut -d'=' -f1)
      hash=$(echo "$line" | awk -F 'sha256:' '{print $2}')
      extract_names_with_att_extension "$name" "$hash" "$branch_name"
    done <<< "$input"
  else
    echo "File not found: $full_path"
  fi
}

# Function to fetch and display Quay SHA for repositories without a file path
fetch_quay_sha() {
  local repo_url="$1"
  local branch_name="$2"
  local tag_name=$(basename "$repo_url" .git)

  echo "Fetching Quay SHA for tag: $tag_name with pattern: $branch_name"
  local quay_sha
  quay_sha=$(skopeo inspect docker://quay.io/modh/$tag_name:$branch_name | jq -r '.Digest' | cut -d':' -f2)
  if [ -n "$quay_sha" ]; then
    echo -e "\e[32mSuccessfully fetched Quay SHA ($quay_sha) for tag: $tag_name with pattern: $branch_name\e[0m"
  else
    echo -e "\e[31mError: Quay SHA could not be fetched for tag: $tag_name with pattern: $branch_name\e[0m"
    sha_mismatch_found=1
    return 1
  fi
  return 0
}

# Initialize a variable to keep track of SHA mismatches
sha_mismatch_found=0

# Read the repository URLs and paths from the file
while IFS=';' read -r repo_url file_path; do
  echo "Processing repository: $repo_url with file path: $file_path"

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

  echo "Using branch: $branch_name"

  # Process each repository
  if [[ -z "$file_path" ]]; then
    fetch_quay_sha "$repo_url" "$branch_name"
  else
    process_repo "$repo_url" "$file_path" "$branch_name"
  fi
done < "$config_file"

# Check if the script should exit with an error
if [ "$sha_mismatch_found" -ne 0 ]; then
  echo "One or more SHA mismatches or fetching errors were found."
  exit 1
else
  echo "All SHA hashes match and were successfully fetched."
fi
