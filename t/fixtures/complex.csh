#!/bin/csh
# Test C Shell Script for Analyzer

# 1. Variable Definitions
set BASE_DIR = "/opt/batch"
setenv LOG_DIR "${BASE_DIR}/log"

# 2. Normal Call
source ${BASE_DIR}/lib/common.csh

# 3. Direct Call
./simple_script.csh

# 4. File I/O
echo "Start" > ${LOG_DIR}/csh_start.log
cat input.dat >> output.dat

# 5. Here-document equivalent (Should be ignored)
cat << EOF
This is not a call: ./fake_script.csh
EOF

# 6. DB Operation via sqlplus
sqlplus user/pass@db @update_data.sql
