#!/usr/bin/env bash
#
# Set up isolated, clean pisi python3.11 venv
#

source ./pisi_venv_functions.bash

# set up a nice and clean venv environment from newest upstream commits
prepare_venv

# show useful next steps re. testing
help
