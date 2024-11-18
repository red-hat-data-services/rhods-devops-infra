import os
import subprocess
import requests
import string
import yaml


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
        
        # If the file already exists, return the path to the existing file without downloading it again.
        if os.path.exists(file_path):
            return file_path
            
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



def parse_yaml(file_path, release):
    """
    Performs placeholder substitution, Parses the YAML file
    and returns the content as a Python dictionary.

    Args:
        - file_path (str): The path to the YAML file to be parsed.
        - release (str): The value to substitute for the {{release}} placeholder.

    Returns:
        - dict: The content of the YAML file as a dictionary, with substitutions applied.

    Raises:
        - yaml.YAMLError: Raised if there is an error specific to parsing the YAML content.
        - FileNotFoundError: Raised if the specified file is not found.
        - Exception: Catches all other exceptions that may occur during file processing.
        
        The program will print an error message and exit with a status code of 1.
    """
    try:
        # Open and read the YAML file
        with open(file_path, 'r') as file:
            content = file.read()

        # Substitute placeholders in the content
        template = string.Template(content)
        substituted_content = template.substitute(release=release)

        # Parse the substituted YAML content
        return yaml.safe_load(substituted_content)

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
    

    
def extract_nudge_details(component_names, nudged_filename, params_env):
    """
    Extracts component name, image name, and image SHA digest from a given environment parameter string.

    Args:
        - component_names (list): List of component names to be verified
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
    component_name = image = image_name = image_sha = ""
    try:
        component_name = params_env.split('=')[0]
        
        if not component_names or component_name in component_names:
            image = params_env.split('=')[1]
            
            # check if image is referenced by sha digest 
            if '@sha256' in image:
                image_name = image.split('@')[0]
                image_sha = image.split('@')[1]
            else:
                raise Exception("Error: The Image reference doesn't have SHA Digest.")
        else:
            colored_print(f"'[{component_name}]' is not in verify-components list. Skipping nudge verification! ", "yellow")
            print()
        
        return component_name, image_name, image_sha
    
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
        quay_api_token = "TOKEN" # Maybe a bug, but any arbitrary value works        
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
        
        

def get_nudged_file_download_url(repo_url, nudged_file_path, release):
    """
    Constructs and returns the download URL for a nudged file based on the provided 
    repository URL, path to the nudged file and release version.
    
    It then constructs a URL by replacing parts of the repository 
    URL to point to the raw content on GitHub and appending the release version and file path.

    Args:
        - repo_url (str): The github repository URL.
        - nudged_file_path (str): Path to the nudged file from the repository root.
        - release (str): The specific release version to be included in the download URL.

    Returns:
        - merged_file_path: The constructed URL to download the nudged file for the specified release.
    """
    base_url = repo_url.replace('.git', '').replace('github.com', 'raw.githubusercontent.com')
    download_url = f"{base_url}/{release}/{nudged_file_path}"
    return download_url



def merge_files_content(files, output_file):
    """
    Merges the content of all files in the `files` list into a single output file.

    Args:
        - files (list): List of file paths to be merged.
        - output_file (str): output filename where merged content will be saved.
        
    Returns:
        - merged_file_path: The full path to the merged file in the 'downloads' directory.
    """
    merged_content = ""
    
    # Define the path for the downloads directory in the current directory
    downloads_dir = os.path.join(os.getcwd(), "downloads")
    
    # Create the downloads directory if it doesn't exist
    if not os.path.exists(downloads_dir):
        os.makedirs(downloads_dir)
        
    # Define the full path for the file in the downloads directory
    merged_file_path = os.path.join(downloads_dir, output_file)
    for filename in files:
        filename = os.path.join(downloads_dir, filename)
        try:
            with open(filename, 'r') as file:
                file_content = file.read()
                merged_content += file_content
        except FileNotFoundError as e:
            colored_print(f"Content Merge Error: Unable to parse '{filename}'. File not found!", "light_red")
            print()
            colored_print(e, "red")
            exit(1)
        except Exception as e:
            colored_print(f"Content Merge Error: An unexpected error occurred while parsing '{filename}'.", "light_red")
            print()
            colored_print(e, "red")
            exit(1)
    
    # Write the merged content into the output file
    with open(merged_file_path, 'w') as output:
        output.write(merged_content)
        
    return merged_file_path

    