#!/bin/bash
set -e

echo "Preparing deployment directory..."

# Create directory if it doesn't exist
mkdir -p /opt/vanvyaapaar

# Remove old JAR files
rm -f /opt/vanvyaapaar/*.jar

echo "Directory prepared successfully"
