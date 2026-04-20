#!/bin/bash
set -e

echo "Validating Nginx service..."

# Check if Nginx is running
if systemctl is-active --quiet nginx; then
    echo "✓ Nginx is running"
else
    echo "✗ Nginx is not running"
    exit 1
fi

# Check if port 80 is listening
if netstat -tuln | grep -q ':80 '; then
    echo "✓ Port 80 is listening"
else
    echo "✗ Port 80 is not listening"
    exit 1
fi

# Check if index.html exists
if [ -f /usr/share/nginx/html/index.html ]; then
    echo "✓ Frontend files deployed"
else
    echo "✗ Frontend files missing"
    exit 1
fi

echo "Frontend deployment validated successfully!"
exit 0
