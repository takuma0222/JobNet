#!/bin/csh
# JCL file but with .jcl extension (not recognized by extension)
# This should be detected by shebang

setenv BATCH_DIR /opt/batch
setenv LOG_DIR ${BATCH_DIR}/logs

source ${LOG_DIR}/common.csh
${BATCH_DIR}/process.sh

echo "Job started" > ${LOG_DIR}/job.log
