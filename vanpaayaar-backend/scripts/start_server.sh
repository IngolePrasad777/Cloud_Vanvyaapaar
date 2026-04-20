#!/bin/bash
set -e

echo "Starting Spring Boot application..."

# Get RDS endpoint from environment or use default
RDS_ENDPOINT="${RDS_ENDPOINT:-localhost}"
S3_BUCKET="${S3_BUCKET:-vanvyaapaar-media}"
CLOUDFRONT_URL="${CLOUDFRONT_URL:-https://cloudfront.net}"

# Fetch RDS credentials from Secrets Manager
echo "Fetching database credentials..."
SECRET_ARN=$(aws rds describe-db-instances \
  --query "DBInstances[?contains(DBInstanceIdentifier, 'vanvyaapaar')].MasterUserSecret.SecretArn" \
  --region us-east-1 \
  --output text | head -1)

if [ -z "$SECRET_ARN" ]; then
    echo "Error: Could not find RDS secret ARN"
    exit 1
fi

SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --region us-east-1 \
  --query SecretString \
  --output text)

DB_USER=$(echo "$SECRET_JSON" | jq -r .username)
DB_PASS=$(echo "$SECRET_JSON" | jq -r .password)

# Get actual RDS endpoint
DB_HOST=$(aws rds describe-db-instances \
  --query "DBInstances[?contains(DBInstanceIdentifier, 'vanvyaapaar')].Endpoint.Address" \
  --region us-east-1 \
  --output text | head -1)

echo "Database host: $DB_HOST"

# Start Spring Boot application
cd /opt/vanvyaapaar
JAR_FILE=$(ls -1 *.jar | head -1)

if [ -z "$JAR_FILE" ]; then
    echo "Error: No JAR file found"
    exit 1
fi

echo "Starting $JAR_FILE..."

nohup java -jar "$JAR_FILE" \
  --spring.datasource.url="jdbc:mysql://$DB_HOST:3306/vanvyaapaar" \
  --spring.datasource.username="$DB_USER" \
  --spring.datasource.password="$DB_PASS" \
  --server.port=8080 \
  --aws.s3.bucket-name="$S3_BUCKET" \
  --aws.cloudfront.url="$CLOUDFRONT_URL" \
  > /var/log/springboot.log 2>&1 &

echo $! > /opt/vanvyaapaar/app.pid
echo "Spring Boot application started with PID: $(cat /opt/vanvyaapaar/app.pid)"
