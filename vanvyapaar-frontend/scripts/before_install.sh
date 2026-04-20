#!/bin/bash
set -e

echo "Cleaning up old deployment..."
rm -rf /usr/share/nginx/html/*
echo "Cleanup completed"
