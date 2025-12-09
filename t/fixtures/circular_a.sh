#!/bin/bash
# Circular dependency test - File A
# This calls circular_b.sh which calls back to circular_a.sh

echo "Circular A"
./circular_b.sh
