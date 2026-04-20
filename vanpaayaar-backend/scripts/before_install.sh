#!/bin/bash
set -e

echo "Preparing deployment directory..."

# Install Java 17 (Amazon Corretto) if not present
if ! command -v java &> /dev/null; then
    echo "Java not found. Installing Amazon Corretto 17..."
    sudo dnf install -y java-17-amazon-corretto-headless
    echo "Java installed: $(java -version 2>&1)"
else
    echo "Java already installed: $(java -version 2>&1)"
fi

# Install jq if not present (needed by start_server.sh)
if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    sudo dnf install -y jq
fi

# Create directory if it doesn't exist
mkdir -p /opt/vanvyaapaar

# Remove old JAR files
rm -f /opt/vanvyaapaar/*.jar

echo "Directory prepared successfully"
