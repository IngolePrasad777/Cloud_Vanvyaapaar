#!/bin/bash
set -e

echo "Validating Spring Boot service..."

# Wait for application to start (max 2 minutes)
MAX_ATTEMPTS=40
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Checking if Spring Boot is responding..."
    
    if curl -s -f http://localhost:8080/public/products > /dev/null 2>&1; then
        echo "✓ Spring Boot is responding on port 8080"
        echo "✓ /public/products endpoint is accessible"
        echo "Backend deployment validated successfully!"
        exit 0
    fi
    
    sleep 3
done

echo "✗ Spring Boot failed to start within 2 minutes"
echo "Checking logs..."
tail -50 /var/log/springboot.log
exit 1
