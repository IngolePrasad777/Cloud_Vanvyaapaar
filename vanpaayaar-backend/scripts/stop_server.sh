#!/bin/bash
set -e

echo "Stopping Spring Boot application..."

# Find and kill the Java process
if pgrep -f 'java.*vanvyaapaar' > /dev/null; then
    pkill -f 'java.*vanvyaapaar'
    echo "Spring Boot application stopped"
    sleep 5
else
    echo "No running Spring Boot application found"
fi

exit 0
