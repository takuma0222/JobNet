#!/bin/bash
# Simple shell script called by complex.sh

# Variable definition
DATA_DIR="/data/input"

# Call to another script (level 2)
./level2_script.sh

# File I/O
cat ${DATA_DIR}/records.csv > /tmp/output.txt

# Inline SQL
sqlplus user/pass@db @process_records.sql
