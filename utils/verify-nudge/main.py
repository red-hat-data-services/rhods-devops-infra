import argparse
from packaging.version import Version
import os
# local packages
from util import util
from validator import validator



def get_rhoai_releases():
    """
    Retrieves and validates RHOAI release versions based on command-line arguments or 
    from a remote YAML file if no arguments are provided.

    If the `--releases` argument is passed, it parses the comma-separated list of releases,
    validates their format, and stores them in a dictionary. If the argument is not provided 
    or set to 'DEFAULT', it fetches the releases from a remote YAML file, validates the content, 
    and returns the parsed data.

    Returns:
        - dict: A dictionary containing the list of validated RHOAI release versions.

    Raises:
        - requests.exceptions.RequestException: If there is an issue while downloading 'release.yaml' from the URL.
        - ValueError: If validation fails for downloaded 'release.yaml' due to missing required field.
        - TypeError: If validation fails for downloaded 'release.yaml' due to incorrect data type.
        - Exception: For all other unexpected exceptions that may occur during the file operation process.
    
        The program will print an error message and exit with a status code of 1.
    """
    
    rhoai_releases = {}
    
    # Parsing RHOAI releases value from command-line
    parser = argparse.ArgumentParser()
    parser.add_argument('--releases', default='DEFAULT', required=False, help='Comma-separated list of releases to be verified for nudges.', dest='releases')
    args = parser.parse_args()

    
    # Use RHOAI release versions from command-line arguments, or fetch from URL if not provided.
    if args.releases and args.releases != 'DEFAULT':
        
        # Split the comma-separated string into a list and strip whitespaces
        releases_list = [release.strip().lower() for release in args.releases.split(',')]
        
        # Store the list in a dictionary
        rhoai_releases = {'releases': releases_list}
        
        # validate RHOAI release pattern
        for release in rhoai_releases['releases']:
            if not validator.validate_release_pattern(release):
                util.colored_print(f"ValueError: Invalid RHOAI release '{release}' found in the passed argument.", "red")
                exit(1)
    else:
        filename = "releases.yaml"
        url = "https://raw.githubusercontent.com/red-hat-data-services/rhoai-disconnected-install-helper/main/releases.yaml"
        
        file_path = util.download_file(filename, url)
        rhoai_releases = util.parse_yaml(file_path)
        validator.validate_releases_yaml(rhoai_releases)
        
    return rhoai_releases



def is_component_onboarded(release, onboarded_since):
    """
    Determines if a component was onboarded and nudging was enabled in the specified release version.

    This function compares the release version to the `onboarded_since` version. 
    If `onboarded_since` is provided, it checks if the release version is greater 
    than or equal to the onboarded version. If `onboarded_since` is not provided, 
    it assumes the component is onboarded.

    Args:
        - release (str): The release version string in the format 'rhoai-<version>'.
        - onboarded_since (str): The version string indicating when the component 
                               was onboarded, in the format 'rhoai-<version>'.

    Returns:
        - bool: True if the component is considered onboarded based on the release 
              version, False otherwise.
    """
    if onboarded_since:
        # Remove the 'rhoai-' prefix and compare versions
        release_version = Version(release.replace('rhoai-', ''))
        onboarded_version = Version(onboarded_since.replace('rhoai-', ''))
        return release_version >= onboarded_version
    else:
        return True

    
    
def is_nudging_correct(release, config):
    """
    Verifies the integrity of nudge files by comparing the SHA values of images from 
    the nudged file against those in the Quay repository. Also checks if the image is 
    from the 'quay.io/modh' repository.

    Args:
        - release (str): The release version for which the nudge file should be verified.
        - config (dict): Configuration details including the name and URL paths necessary 
                         for downloading and verifying the nudged file.

    Returns:
        - bool: True if any mismatch between the SHAs is found, False otherwise.
    """
    nudged_file_paths = config.get('nudged-file-paths', [])
    
    # If multiple nudged files, Download all nugged files and merge their contents in a single file  
    nudged_filenames = []
    nudged_file_path = ""
    for path in nudged_file_paths:
        nudged_filename = f"{config.get('name')}-{release}-{os.path.basename(path)}"
        nudged_filenames.append(nudged_filename)
        nudged_file_url = util.get_nudged_file_download_url(config.get('repo-url'), path, release)
        nudged_file_path = util.download_file(filename=nudged_filename, url=nudged_file_url)
    
    if len(nudged_filenames) > 1:
        nudged_file_path = util.merge_files_content(nudged_filenames, f"{config.get('name')}-{release}-merged-params.env")
    
    # Parse nudged file
    params_env_list = util.parse_nudged_file(file_path=nudged_file_path)
    
    
    # Create an empty list to store component names
    component_names = []

    # Initialize an empty list to store component names
    component_names = []

    # Check if 'verify-components' exists in the config dictionary
    if 'verify-components' in config:
        # Extract component names from the 'verify-components' list
        for component in config['verify-components']:
            component_names.append(component['name'])

    # Boolean to check if any mismatch is found
    mismatch_found = False
    
    # Compare the SHAs and print the results
    for param in params_env_list:
        # colored_print(f"param  : {param}", "blue")
        
        # Extracting details from the nudged file
        component_name, image_name, image_sha = util.extract_nudge_details(component_names, nudged_filename, param)
        
        image_tag = release
        onboarded_since = ''
        if 'verify-components' in config:
            # Extract component names from the 'verify-components' list
            for component in config['verify-components']:
                if component_name == component['name']:
                    image_tag = component.get('image-tag', release)
                    onboarded_since = component.get('onboarded-since', '')
                    
        
        # Skip, if the component was not onboarded in the current release
        if not is_component_onboarded(release, onboarded_since):
            util.colored_print(f"'[{component_name}]' nudge started in release '{onboarded_since}'. Skipping nudge verification! ", "yellow")
            print()
            continue
            
            
        if image_name:
            if "quay.io/modh" in image_name:
                # Fetch sha from quay
                quay_sha = util.get_quay_image_sha(image_name, image_tag)

                if quay_sha != image_sha:
                    color = 'red'
                    mismatch_found = True
                else:
                    color = 'green'
                    
                util.colored_print(f"Component Name  : {component_name}", color)
                util.colored_print(f"Image Name      : {image_name}", color)
                util.colored_print(f"Image SHA       : {image_sha.split(':')[1]}", color)
                util.colored_print(f"Quay  SHA       : {quay_sha.split(':')[1]}", color)
                print()
            else:
                util.colored_print(f"ValueError: Invalid Image reference found in '{nudged_file_url}'.", "light_red")
                print()
                util.colored_print(f"Image '{image_name}' is not from 'modh' quay repo!", "red")
                exit(1)
            
    return mismatch_found





def main():
    
    # Use RHOAI release versions from command-line arguments, or fetch from URL if not provided.
    rhoai_releases = get_rhoai_releases()
    util.colored_print(text=f"\n[Debug] Releases: {rhoai_releases}\n", color="magenta")
    
    mismatch_found = False
    for release in rhoai_releases['releases']:
        
        configs = util.parse_yaml(file_path="config.yaml", release=release)
        for config in configs:
            
            util.colored_print("===================================================================================", "white")
            util.colored_print(text="Nudge Verification In Progress", color="white", isBold=True)
            util.colored_print(text=f"-> Repo      : {config.get('name')}", color="white")
            util.colored_print(text=f"-> Branch    : {release}", color="white")
            util.colored_print(text=f"-> Repo URL  : {config.get('repo-url')}", color="white")
            util.colored_print(text=f"-> File Path : {config.get('nudged-file-paths')}", color="white")
            util.colored_print("===================================================================================", "white")
            util.colored_print(text=f"\n[Debug] Config: '{config}' \n", color="magenta")
    
            if validator.validate_config_yaml(config):
                
                # Skip, if the component was not onboarded in the current release
                if not is_component_onboarded(release, config.get('onboarded-since', '')):
                    util.colored_print(f"'[{config.get('name')}]' nudge started in release '{config.get('onboarded-since')}'. Skipping nudge verification! ", "yellow")
                    print()
                    continue
                
                if is_nudging_correct(release, config):
                    mismatch_found = True

    if mismatch_found:
        util.colored_print("Mismatch Found. Sending Slack Notification! ", "red")
        exit(1)



if __name__ == '__main__':
    main()
