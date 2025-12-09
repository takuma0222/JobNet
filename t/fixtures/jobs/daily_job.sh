#!/bin/bash
# Daily job script

# Processing
echo "Daily job started"

# Call to common processing
source ./lib/common.sh

# File I/O  
cat /data/daily/input.csv | process_data > /data/daily/output.csv
