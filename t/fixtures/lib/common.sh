#!/bin/bash
# Common library script

# Utility functions
log_message() {
    echo "[$(date)] $1" >> /var/log/common.log
}

# Common variables
export COMMON_VAR="common_value"
