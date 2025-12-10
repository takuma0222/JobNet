#!/bin/bash
# Test Shell Script for Analyzer

# 1. Variable Definitions
export BASE_DIR="/opt/batch"
declare LOG_DIR="${BASE_DIR}/log"
ERROR_LOG="${LOG_DIR}/error.log"
ARCHIVE_ERROR="${ERROR_LOG}.old"
JOB_SCRIPT="${BASE_DIR}/jobs/daily_job.sh"

# 2. Normal Call
source ${BASE_DIR}/lib/common.sh
./simple_call.sh

# 3. Variable Call
${JOB_SCRIPT}

# 4. Here-document (Should be ignored)
cat <<EOF
This is not a call: ./fake_script.sh
source fake_lib.sh
EOF

# 5. String with comment char (Should be preserved/ignored as comment)
echo "This is # not a comment"
echo "Call inside string: ./string_script.sh"

# 6. File I/O
echo "Start" > ${LOG_DIR}/start.log
cat input.dat | grep "error" >> error.log
echo "Error occurred" > ${ERROR_LOG}
mv ${ERROR_LOG} ${ARCHIVE_ERROR}

# 7. DB Operation
sqlplus user/pass@db @insert_data.sql
