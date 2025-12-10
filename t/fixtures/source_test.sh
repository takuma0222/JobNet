#!/bin/bash
# Test script for source variable inheritance
# This tests that variables from sourced files are available

# Source the config file (setenv should set BATCH_DIR, LIB_DIR, COMMON_SCRIPT)
source ./config.csh

# Use variables defined in config.csh
# These should resolve properly because source inherits variables
source ${LIB_DIR}/common.sh
${COMMON_SCRIPT}

# File I/O using sourced variables
echo "log" > ${BATCH_DIR}/output.log
