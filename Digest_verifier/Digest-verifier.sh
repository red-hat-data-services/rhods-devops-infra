#!/bin/bash

# File containing the repository URL and the path
config_file="./Digest_verifier/repo_url.txt"

# Check if the configuration file exists
if [ ! -f "$config_file" ]; then
  echo "Error: Configuration file not found: $config_file"
  exit 1
fi

# Read the repository URL and path from the file
read -r repo_url file_path < <(awk -F';' '{print $1, $2}' "$config_file")

# Validate that both the URL and the path have been read
if [[ -z "$repo_url" || -z "$file_path" ]]; then
  echo "Error: Repository URL or file path is missing in $config_file"
  exit 1
fi

# Function to fetch the latest branch with a specific pattern.
fetch_latest_branch() {
  local repo_url="$1"
  local pattern="${2:-rhoai}"
  local branch
  branch=$(git ls-remote --heads "$repo_url" | grep "$pattern" | awk -F'/' '{print $NF}' | sort -V | tail -1)
  if [ -z "$branch" ]; then
    echo "No branch matching the pattern '$pattern'."
    exit 1
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
  local name="$1"
  local repo_hash="$2"
  local pattern="$3"

  if [ -z "$repo_hash" ]; then
    echo "Error: The $name image is referenced using floating tags. Exiting..."
    exit 1
  fi

  # Remove sha256: prefix from the repo_hash if it exists
  repo_hash=${repo_hash#sha256:}

  # Attempt to fetch Quay SHA for the specified tag pattern
  echo "Attempting to fetch Quay SHA for tag: $name with pattern: $pattern"
  quay_output=$(skopeo inspect docker://quay.io/modh/$name:$pattern 2>&1)
  if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch Quay SHA for tag: $name with pattern: $pattern"
    echo "skopeo output: $quay_output"
    sha_mismatch_found=1
    return
  fi

  # Extract the SHA hash from the Quay output and remove sha256: prefix
  quay_hash=$(echo "$quay_output" | jq -r '.Digest' | sed 's/^sha256://')
  if [ -z "$quay_hash" ]; then
    echo "Error: Quay SHA could not be fetched for tag: $name with pattern: $pattern"
    sha_mismatch_found=1
    return
  fi

  # Compare repository and Quay SHAs
  if [ "$repo_hash" = "$quay_hash" ]; then
    echo -e "\e[32mRepository SHA ($repo_hash) matches Quay SHA ($quay_hash) for tag: $name with pattern: $pattern\e[0m"
  else
    echo -e "\e[31mRepository SHA ($repo_hash) does NOT match Quay SHA ($quay_hash) for tag: $name with pattern: $pattern\e[0m"
    sha_mismatch_found=1
  fi
}

# Main logic for processing the file and SHAs
main() {
  if [ -f "$full_path" ]; then
    echo "File found: $full_path"
    input=$(<"$full_path")

    while IFS= read -r line; do
      name=$(echo "$line" | cut -d'=' -f1)
      hash=$(echo "$line" | awk -F 'sha256:' '{print $2}')
      extract_names_with_att_extension "$name" "$hash" "$branch_name"
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