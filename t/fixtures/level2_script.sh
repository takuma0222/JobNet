#!/bin/bash
# Level 2 script - deepest level in hierarchy

# Final operation
echo "Level 2 processing"

# File output
echo "Done" >> /var/log/batch.log

# DB operation
sqlplus user/pass@db @final_update.sql
