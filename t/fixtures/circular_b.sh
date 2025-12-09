#!/bin/bash
# Circular dependency test - File B
# This calls circular_a.sh creating a loop

echo "Circular B"
./circular_a.sh
