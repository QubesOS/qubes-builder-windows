#!/bin/sh

# convert msys-style path to native windows format
 echo "$1" | sed 's|^/\(.\)/|\1:\\|g; s|/|\\|g';
 