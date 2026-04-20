#!/bin/bash
set -e

echo "Setting correct permissions..."
chown -R nginx:nginx /usr/share/nginx/html
chmod -R 755 /usr/share/nginx/html
echo "Permissions set successfully"
