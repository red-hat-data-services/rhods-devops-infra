Tracer
====================

Overview
----------
Tracer is a client side tool which can be used to trace the information about latest RHOAI builds without navigating to any other systems. It can majorly serve following use case: 
   * Trace the latest CI/nightly build info for any given RHOAI version 
   * Trace down the individual commits of each component with any given FBC/index image

Please note:
   * Tracer will only work for the RHOAI versions built after the Konflux transition

Prerequisites
----------------
- bash 4.0 or higher
- jq latest
- yq latest
- skopeo latest
- git latest

Setup & configuration
----------
* Ensure all the prerequisites are installed
* Download the [tracer.sh](https://github.com/red-hat-data-services/rhods-devops-infra/blob/main/tools/tracer/tracer.sh) script to your local machine
* Provide the execute access to the script using following command - ```chmod +x tracer.sh```
* Copy the [RHOAI Quay ReadOnly bot - pull secret](https://vault.bitwarden.com/#/vault?collectionId=75f54536-fa36-4ef9-8f1a-b09701646cac&itemId=e6e1fdde-6601-4e8b-8154-b211005518a1) from bitwarden
* Save the pull-secret to a file at following location - **~/.ssh/.rhoai_quay_ro_token** on your machine
* Configure the tracer using following command ```./tracer.sh configure```
* Make sure you see ```Login Succeeded!``` message
* You are all set to use the tracer now!

Usage
-----
Tracer has multiple functionalities exposed through a combination of following arguments:
```commandline
  Usage: tracer.sh [-h] [-v] [-c] [-n] [-b] [configure] [update]
  1. -h, --help - Display this usage info
  2. -v, --rhoai-version - RHOAI version to get the build info for, valid formats are X.Y or rhoai-X.Y or vX.Y, optional, default value is latest RHOAI version
  3. -d, --digest - Complete digest of the image to be provided as an input, optional, if rhoai-verson and digest both are provided then digest will take precedence
  4. -c, --show-commits - Show the commits info for all the components, by default only basic info is shown
  5. -s, --search - Search for a specific source code commit using the format REPO_NAME/SHA, where both REPO_NAME and SHA can be partial matches
  5. -n, --nightly - Show the info of latest nightly build, by default the CI-build info is shown
  6. -b, --bundle - Show the info about operator bundle image, by default it will show the FBC image info
  7. -i, --image - Complete URI of the image to be provided as an input, optional, if image and digest both are provided then image will take precedence, it suppports all the image formats - :tag, @sha256:digest and :tag@sha256:digest 
  8. configure - To configure the tracer and skopeo as needed
  9. update - To update the tracer to latest version available in the repo
```
Examples
----------
* ```./tracer.sh``` - without any arguments it will provide the basic build info of the latest CI build of the latest RHOAI version
* ```./tracer.sh --nightly``` will provide the basic build info of the latest **nightly** build of the latest RHOAI version
* ```./tracer.sh --rhoai-version v2.16``` - will provide the basic build info of the latest **CI** build of 2.16
* ```./tracer.sh --rhoai-version v2.16 --nightly``` - will provide the basic build info of the latest **nightly** build of 2.16
* ```./tracer.sh --show-commits``` - will provide the **detailed** build info of with all the commit details of all the components for the latest **CI** build of latest RHOAI version
* ```./tracer.sh --show-commits --image quay.io/rhoai/rhoai-fbc-fragment@sha256:9f2937c6b367ff1211dba8d71438a93193638ecd06ee644bb9258e1a316a1541``` will provide the **detailed** build info of with all the commit details of all the components for the given image
* ```./tracer.sh --search modelmesh/0030a6b'``` - will search if there is a commit SHA containing 0030a6b in all source repos that match 'modelmesh' in the latest RHOAI version (checks the first 100 commits of a given history)
* ```./tracer.sh --digest 9f2937c6b367ff1211dba8d71438a93193638ecd06ee644bb9258e1a316a1541``` will show info about the FBC image with the given digest
* ```./tracer.sh --bundle``` it will show the info about operator-bundle image instead of FBC image, all other parameters can be applied as needed
