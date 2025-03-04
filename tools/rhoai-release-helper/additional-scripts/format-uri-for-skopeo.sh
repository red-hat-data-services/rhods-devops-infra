#!/bin/bash

URI=$1

# gets rid of protocol:// at beginning 
URI=$(echo $URI | sed -E 's|^.*://||')

# gets rid of tag if SHA is present
URI=$(echo $URI | sed 's/:.*@sha/@sha/')

echo "docker://$URI"
