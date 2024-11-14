import argparse
import os
import subprocess
import requests
import validator
import yaml
from distutils.version import LooseVersion


def colored_print(text, color, isBold=False):
    """
    Prints a message in a specified color with optional bold formatting.

    Args:
        - text (str): The text to print.
        - color (str): The color of the text. E.g., 'red', 'light_red', 'green', etc.
        - isBold (bool): If True, makes the text bold. Default is False.
    """
    colors = {
        'light_black': '30',
        'light_red': '31',
        'light_green': '32',
        'light_yellow': '33',
        'light_blue': '34',
        'light_magenta': '35',
        'light_cyan': '36',
        'light_white': '37',
        'black': '90',
        'red': '91',
        'green': '92',
        'yellow': '93',
        'blue': '94',
        'magenta': '95',
        'cyan': '96',
        'white': '97'
    }
    
    color_code = colors.get(color, '37')  # Default to white if color not found
    bold_code = '1' if isBold else '0'
    
    print(f"\033[{bold_code};{color_code}m{text}\033[0m")
    
    

def download_file(filename, url):
    """
    Downloads a file from a specified URL and saves it to a 'downloads' directory in the current working directory.

    Args:
        - filename (str): The name of the file to be saved.
        - url (str): The URL from which to download the file.

    Returns:
        - str: The full path to the downloaded file in the 'downloads' directory.

    Raises:
        - requests.exceptions.RequestException: Raised for errors related to the HTTP request, such as connection issues or invalid URLs.
        - Exception: Catches all other unexpected exceptions that may occur during the file operation process.
    
        The program will print an error message and exit with a status code of 1.
    """
    try:
        # Define the path for the downloads directory in the current directory
        downloads_dir = os.path.join(os.getcwd(), "downloads")
        
        # Create the downloads directory if it doesn't exist
        if not os.path.exists(downloads_dir):
            os.makedirs(downloads_dir)
            
        # Define the full path for the file in the downloads directory
        file_path = os.path.join(downloads_dir, filename)
            
        # Download the file
        response = requests.get(url)

        # Raises an HTTPError if the HTTP request was unsuccessful
        response.raise_for_status()

        # Write the content of the URL in local file 'release.yaml'
        with open(file_path, "wb") as file:
            file.write(response.content)
            
        return file_path

    except (requests.exceptions.RequestException, Exception) as e:
        colored_print(f"An unexpected error occurred while downloading '{filename}' from url '{url}'.", "light_red")
        print()
        colored_print(e, "red")
        exit(1)


  
def remove_file(filename):
    """
    Deletes the specified file from the file system.

    Args:
        - filename (str): The path to the file that needs to be deleted.

    Raises: 
        - OSError: Raised if there is a file system-related error while attempting to delete the file.
        - Exception: Catches all other unexpected exceptions that may occur during the file deletion process.
        
        The program will print an error message and exit with a status code of 1.
    """
    try:
        os.remove(filename)
    except OSError as e:
        colored_print(f"File system error while deleting file '{filename}'.", "light_red")
        print()
        colored_print(e, "red")
        exit(1)
    except Exception as e:
        colored_print(f"An unexpected error occurred while deleting file '{filename}'.", "light_red")
        print()
        colored_print(e, "red")
        exit(1)




def parse_yaml(file_path):
    """
    Parses a YAML file and returns its content as a Python dictionary.

    Args:
        - file_path (str): The path to the YAML file to be parsed.

    Returns:
        - dict: The content of the YAML file as a dictionary.

    Raises:
        - yaml.YAMLError: Raised if there is an error specific to parsing the YAML content.
        - FileNotFoundError: Raised if the specified file is not found.
        - Exception: Catches all other exceptions that may occur during file processing.
        
        The program will print an error message and exit with a status code of 1.
    """
    try:
        # Open and parse the YAML file
        with open(file_path) as file:
            return yaml.safe_load(file)

    except yaml.YAMLError as e:
        colored_print(f"YAML error occured while parsing '{file_path}'.", "light_red")
        print()
        colored_print(e, "red")
        exit(1)
    except FileNotFoundError as e:
        colored_print(f"Unable to parse '{file_path}'. File not found!", "light_red")
        print()
        colored_print(e, "red")
        exit(1)
    except Exception as e:
        colored_print(f"An unexpected error occurred while parsing '{file_path}'.", "light_red")
        print()
        colored_print(e, "red")
        exit(1)


def parse_nudged_file(file_path):
    """
    Reads a nudged file and stores each line in a list. 
    
    Args:
      - file_path (str): The path to the file to be read.
    
    Returns:
      - list: A list containing the lines of the file.
    
    Raises:
      - Exception: If the file is empty or doesn't exist, the program will print an error message 
                    and exit with a status code of 1.
    """
    # Initialize an empty list to store the lines
    params_list = []

    try:
        if os.path.isfile(file_path):

            # Read the file and store each line in the list
            with open(file_path, 'r') as file:
                for line in file:
                    # Strip leading and trailing white spaces
                    stripped_line = line.strip()
                    # Only add non-empty lines to the list
                    if stripped_line:
                        params_list.append(stripped_line)
        else:
            raise Exception(f"Error: The file '{file_path}' does not exist.")


        # Check if the list is empty and raise an exception if it is
        if not params_list:
            raise Exception(f"Error: The file '{file_path}' is empty.")
        
        return params_list
        
    except Exception as e:
        colored_print(f"An error occured while reading the nudged file '{file_path}'", "light_red")
        print()
        colored_print(e, "red")
        exit(1)



def extract_nudge_details(config, nudged_filename, params_env):
    """
    Extracts component name, image name, and image SHA digest from a given environment parameter string.

    Args:
        - config (dict): A dictionary representing a single configuration item in config.yaml.
        - nudged_filename (str): The name of the file which gets nudged.
        - params_env (str): Environment parameter string in the format 'COMPONENT_NAME=image_reference'.

    Returns:
        - tuple: A tuple containing:
            - component_name (str): The name of the component extracted from 'params_env'.
            - image_name (str): The name of the image (without the registry and SHA256 digest).
            - image_sha (str): The SHA256 digest of the image.

    Raises:
        - Exception: If an error occurs during the extraction process, the program will print an error message 
                    and exit with a status code of 1.
    """
    # Initialize variables to empty strings
    component_name = image = image_name = image_sha = image_tag = ""

    try:
        # Extract component name from params_env
        component_name = params_env.split('=')[0]
        # Check if the component is in verify-components
        verify_components = config.get("verify-components", [])
        # Check if component is in verify-components, handling new dictionary structure
        component_in_verify = any(
            comp.get("name") == component_name for comp in verify_components
        )
        component_info = next((comp for comp in verify_components if comp.get("name") == component_name), None)

        if not verify_components or component_in_verify:
            # Extract image details if component exists
            image = params_env.split('=')[1]
            if '@sha256' in image:
                image_name = image.split('@')[0]
                image_sha = image.split('@')[1]
            else:
                raise Exception("Error: The Image reference doesn't have SHA Digest.")

           
            if component_info:
                onboarded_since = component_info.get("onboarded-since")
                image_tag = component_info.get("image-tag")
                print(f"Component: {component_name}, Onboarded Since: {onboarded_since}, Image Tag: {image_tag}")

        else:
            colored_print(f"'{component_name}' is not in verify-components list. Skipping nudge verification!", "yellow")
            print()

        return component_name, image_name, image_sha, image_tag

    except Exception as e:
        colored_print(f"Invalid '{nudged_filename}': Unable to extract SHA Digest from '{params_env}'.", "light_red")
        print()
        colored_print(e, "red")
        exit(1)

        


def get_quay_image_sha_using_skopeo(image_name, tag):
    """
    Retrieves the SHA digest of a specific image tag from Quay.io using the Skopeo tool.

    Args:
        - image_name (str): The name of the image repository, including the full path (e.g., quay.io/namespace/repository).
        - tag (str): The specific tag of the image for which the SHA digest is required.

    Returns:
        - str: The SHA digest of the specified image tag.

    Raises:
        - subprocess.CalledProcessError: If an error occurs during the execution of the Skopeo, the program will print an error message 
                    and exit with a status code of 1.
    """

    command = f"skopeo inspect docker://{image_name}:{tag} | jq -r '.Digest' | cut -d':' -f2"
    print(command)
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, shell=True, check=True
        )
        return result.stdout.strip()  # Remove any leading/trailing whitespace
    except (subprocess.CalledProcessError, Exception) as e:
        colored_print(f"An unexpected error occurred while executing command: '{command}'", "light_red")
        print()
        colored_print(e, "red")
        exit(1)



def get_quay_image_sha(image_name, image_tag):
    """
    Retrieves the SHA digest of a specific image tag from a Quay.io repository.

    Args:
        - image_name (str): The name of the image repository in Quay.io. This should include the full path including the 'quay.io/' prefix.
        - image_tag (str): The specific tag of the image for which the SHA digest is required.

    Returns:
        - str: The SHA digest of the specified image tag if found.

    Raises:
        - Exception: 
              - If the 'QUAY_API_TOKEN' environment variable is not set or empty, 
              - if the tag is not found in the repository, 
              - if there is an unexpected JSON structure in the API response.
              
            The program will print an error message and exit with a status code of 1.
    """
    try:
        image_name=image_name.replace('quay.io/', '')
        url = f"https://quay.io/api/v1/repository/{image_name}/tag/?specificTag={image_tag}"
        quay_api_token = os.getenv('QUAY_API_TOKEN')
        
        if quay_api_token in [None, '']:
            raise Exception("Error: Environment variable 'QUAY_API_TOKEN' is not set or is empty.")
        
        headers = {
            "Authorization": f"Bearer {quay_api_token}"
        }

        response = requests.get(url, headers=headers)
        response.raise_for_status()
    
        tags = response.json()
        
        # Adjust based on the actual structure of the JSON response
        if isinstance(tags, dict):
            tag_list = tags.get('tags', [])
        else:
            raise Exception("Error: Unexpected JSON response structure")

        
        for tag in tag_list:
            if tag.get('name') == image_tag:
                return tag.get('manifest_digest')
        
        raise Exception(f"Error: Tag '{image_tag}' not found in repository '{image_name}'")

    except (requests.exceptions.RequestException, Exception) as e:
        colored_print(f"An error occured while fetching image sha for '{image_name}:{image_tag}'", "light_red")
        print()
        colored_print(e, "red")
        exit(1)
        
        



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
                colored_print(f"ValueError: Invalid RHOAI release '{release}' found in the passed argument.", "red")
                exit(1)
    else:
        filename = "releases.yaml"
        url = "https://raw.githubusercontent.com/red-hat-data-services/rhoai-disconnected-install-helper/main/releases.yaml"
        
        file_path = download_file(filename, url)
        rhoai_releases = parse_yaml(file_path)
        validator.validate_releases_yaml(rhoai_releases)
        
    return rhoai_releases
    
    
    
def get_nudged_file_download_url(config, release):
    """
    Constructs and returns the download URL for a nudged file based on the provided 
    configuration and release version.

    This function extracts the repository URL and the path to the nudged file from 
    the `config` dictionary. It then constructs a URL by replacing parts of the repository 
    URL to point to the raw content on GitHub and appending the release version and file path.

    Args:
        - config (dict): A dictionary containing configuration details such as 'repo-url' and 
                       'nudged-file-path'.
        - release (str): The specific release version to be included in the download URL.

    Returns:
        - str: The constructed URL to download the nudged file for the specified release.
    """
    repo_url = config.get('repo-url')
    nudged_file_path = config.get('nudged-file-path')
    base_url = repo_url.replace('.git', '').replace('github.com', 'raw.githubusercontent.com')
    download_url = f"{base_url}/{release}/{nudged_file_path}"
    return download_url



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
        release_version = LooseVersion(release.replace('rhoai-', ''))
        onboarded_version = LooseVersion(onboarded_since.replace('rhoai-', ''))
        return release_version >= onboarded_version
    else:
        return True
    
    

def verify_nudge(release, config):
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
    
    # Downloading nudged-file
    nudged_filename = f"{config.get('name')}-{release}-params.env"
    nudged_file_url = get_nudged_file_download_url(config, release)
    nudged_file_path = download_file(filename=nudged_filename, url=nudged_file_url)
    
    # Parse nudged file
    params_env_list = parse_nudged_file(file_path=nudged_file_path)
    
    # Boolean to check if any mismatch is found
    mismatch_found = False

    # Compare the SHAs and print the results
    for param in params_env_list:
        # colored_print(f"param  : {param}", "blue")
        
        # Extracting details from the nudged file
        component_name, image_name, image_sha, image_tag = extract_nudge_details(config, nudged_filename, param)
        tag_to_use = f"{release}-{image_tag}" if image_tag else release
        if image_name:
            if "quay.io/modh" in image_name:
                # Fetch sha from quay
                quay_sha = get_quay_image_sha(image_name, release)

                if quay_sha != image_sha:
                    color = 'red'
                    mismatch_found = True
                else:
                    color = 'green'

                colored_print(f"Component Name  : {component_name}", color)
                colored_print(f"Image Name      : {image_name}", color)
                colored_print(f"Image SHA       : {image_sha.split(':')[1]}", color)
                colored_print(f"Quay  SHA       : {quay_sha.split(':')[1]}", color)
                print()
            else:
                colored_print(f"ValueError: Invalid Image reference found in '{nudged_file_url}'.", "light_red")
                print()
                colored_print(f"Image '{image_name}' is not from 'modh' quay repo!", "red")
                exit(1)
            
     
    return mismatch_found
