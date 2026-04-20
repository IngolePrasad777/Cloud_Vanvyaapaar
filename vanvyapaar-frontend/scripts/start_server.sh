#!/bin/bash
set -e

echo "Starting Nginx server..."
systemctl restart nginx
systemctl enable nginx
echo "Nginx started successfully"
