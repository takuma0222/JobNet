#!/bin/sh
# Test file for path-only script detection

# Test case 1: Path only - should be detected
/A/B/AAAA

# Test case 2: Path only - in line with other content
echo "starting" && /opt/batch/process

# Test case 3: Path only - in assignment
SCRIPT=/usr/local/bin/myapp

# Test case 4: Path - with pipes/redirects
/var/scripts/job.sh | tee log.txt

# Test case 5: Relative path - should be detected
./run_script

# Test case 6: Mixed with variable
$BASE_DIR/bin/execute
