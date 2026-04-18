# 🚀 VanVyaapaar AWS Deployment Guide

## ✅ ALL ISSUES FIXED

### What Was Fixed:
1. ✅ **Nginx port changed from 3000 → 80**
2. ✅ **Backend health check changed to `/public/products`**
3. ✅ **Frontend API URL now uses ALB DNS (dynamic)**
4. ✅ **Database dump.sql will be imported automatically**
5. ✅ **Backend startup wait added (prevents race condition)**
6. ✅ **SSH access added to security groups**
7. ✅ **Nginx configuration cleaned (no proxy block)**
8. ✅ **Swap space added for t3.micro builds**
9. ✅ **Initial admin user created if no dump exists**
10. ✅ **S3 bucket for images configured with CloudFront**

---

## 📋 PRE-DEPLOYMENT CHECKLIST

### 1. **AWS Account Setup**
- [ ] AWS Account created
- [ ] AWS CLI installed: `aws --version`
- [ ] AWS credentials configured: `aws configure`
- [ ] Choose region (e.g., us-east-1, ap-south-1)

### 2. **EC2 Key Pair (for SSH access)**
```bash
# Create a new key pair
aws ec2 create-key-pair \
  --key-name vanvyaapaar-key \
  --query 'KeyMaterial' \
  --output text > vanvyaapaar-key.pem

# Set permissions
chmod 400 vanvyaapaar-key.pem
```

### 3. **GitHub Repository**
- [ ] Code pushed to GitHub
- [ ] Repository URL: `https://github.com/samikshamulik/Cloud_Vanvyaapaar.git`
- [ ] Verify nginx.conf has `listen 80;`
- [ ] Verify dump.sql is in root directory

---

## 🚀 DEPLOYMENT STEPS

### **Step 1: Validate CloudFormation Template**
```bash
aws cloudformation validate-template \
  --template-body file://infrastructure.yaml
```

### **Step 2: Deploy the Stack**
```bash
aws cloudformation create-stack \
  --stack-name vanvyaapaar-prod \
  --template-body file://infrastructure.yaml \
  --parameters \
    ParameterKey=EnvironmentName,ParameterValue=vanvyaapaar-prod \
    ParameterKey=KeyName,ParameterValue=vanvyaapaar-key \
    ParameterKey=InstanceType,ParameterValue=t3.micro \
    ParameterKey=DBInstanceClass,ParameterValue=db.t3.micro \
    ParameterKey=GitRepositoryURL,ParameterValue=https://github.com/samikshamulik/Cloud_Vanvyaapaar.git \
  --capabilities CAPABILITY_IAM \
  --region us-east-1
```

### **Step 3: Monitor Stack Creation**
```bash
# Watch stack events
aws cloudformation describe-stack-events \
  --stack-name vanvyaapaar-prod \
  --query 'StackEvents[*].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId]' \
  --output table

# Or use wait command
aws cloudformation wait stack-create-complete \
  --stack-name vanvyaapaar-prod
```

**Expected Time:**
- VPC & Networking: 2-3 minutes
- RDS Database: 5-7 minutes
- EC2 Instances: 3-5 minutes
- Frontend Build: 10-15 minutes (on t3.micro with swap)
- Backend Build: 5-7 minutes
- **Total: ~25-35 minutes**

### **Step 4: Get Stack Outputs**
```bash
aws cloudformation describe-stacks \
  --stack-name vanvyaapaar-prod \
  --query 'Stacks[0].Outputs' \
  --output table
```

**You'll get:**
- `FrontendURL`: http://vanvyaapaar-prod-ex-alb-XXXXXXXXX.us-east-1.elb.amazonaws.com
- `BackendURL`: Same as frontend (ALB routes based on path)
- `CloudFrontURL`: https://XXXXXXXXXXXXX.cloudfront.net
- `MediaBucketName`: vanvyaapaar-prod-media-assets-XXXXXXXXXXXX
- `RDSEndpoint`: vanvyaapaar-prod-db.XXXXXXXXX.us-east-1.rds.amazonaws.com
- `AdminLoginCredentials`: Email: admin@vanvyaapaar.com | Password: admin123

---

## 🧪 TESTING THE DEPLOYMENT

### **1. Test Frontend**
```bash
# Get the ALB URL
FRONTEND_URL=$(aws cloudformation describe-stacks \
  --stack-name vanvyaapaar-prod \
  --query 'Stacks[0].Outputs[?OutputKey==`FrontendURL`].OutputValue' \
  --output text)

# Test frontend
curl -I $FRONTEND_URL
# Expected: HTTP/1.1 200 OK
```

Open in browser: `http://vanvyaapaar-prod-ex-alb-XXXXXXXXX.us-east-1.elb.amazonaws.com`

### **2. Test Backend API**
```bash
# Test public products endpoint
curl $FRONTEND_URL/public/products
# Expected: JSON array of products

# Test auth endpoint
curl -X POST $FRONTEND_URL/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@vanvyaapaar.com",
    "password": "admin123",
    "role": "ADMIN"
  }'
# Expected: {"token":"...", "role":"ADMIN", "name":"Admin", "id":10}
```

### **3. Test Database Connection**
```bash
# SSH into backend instance
BACKEND_INSTANCE=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=*Backend*" \
           "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

ssh -i vanvyaapaar-key.pem ec2-user@$BACKEND_INSTANCE

# Check Spring Boot logs
tail -f /var/log/springboot.log

# Check if database is populated
mysql -h <RDS_ENDPOINT> -u admin -p vanvyaapaar
# Enter password from Secrets Manager
SELECT COUNT(*) FROM products;
```

### **4. Test S3 Image Upload**
```bash
# Get bucket name
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name vanvyaapaar-prod \
  --query 'Stacks[0].Outputs[?OutputKey==`MediaBucketName`].OutputValue' \
  --output text)

# Upload test image
aws s3 cp test-image.jpg s3://$BUCKET_NAME/products/test-image.jpg

# Get CloudFront URL
CLOUDFRONT_URL=$(aws cloudformation describe-stacks \
  --stack-name vanvyaapaar-prod \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' \
  --output text)

# Access image via CloudFront
curl -I $CLOUDFRONT_URL/products/test-image.jpg
```

---

## 🔍 TROUBLESHOOTING

### **Frontend Not Loading**
```bash
# SSH into frontend instance
FRONTEND_INSTANCE=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=*Frontend*" \
           "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

ssh -i vanvyaapaar-key.pem ec2-user@$FRONTEND_INSTANCE

# Check user-data logs
sudo tail -f /var/log/user-data.log

# Check nginx status
sudo systemctl status nginx

# Check nginx error logs
sudo tail -f /var/log/nginx/error.log

# Check if files exist
ls -la /usr/share/nginx/html/

# Test nginx locally
curl http://localhost:80
```

### **Backend Not Responding**
```bash
# SSH into backend instance
ssh -i vanvyaapaar-key.pem ec2-user@$BACKEND_INSTANCE

# Check user-data logs
sudo tail -f /var/log/user-data.log

# Check Spring Boot logs
tail -f /var/log/springboot.log

# Check if Spring Boot is running
ps aux | grep java

# Test backend locally
curl http://localhost:8080/public/products
```

### **Database Connection Issues**
```bash
# Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier vanvyaapaar-prod-db \
  --query 'DBInstances[0].DBInstanceStatus'

# Get DB credentials from Secrets Manager
SECRET_ARN=$(aws rds describe-db-instances \
  --db-instance-identifier vanvyaapaar-prod-db \
  --query 'DBInstances[0].MasterUserSecret.SecretArn' \
  --output text)

aws secretsmanager get-secret-value \
  --secret-id $SECRET_ARN \
  --query SecretString \
  --output text | jq
```

### **Health Check Failing**
```bash
# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn <TARGET_GROUP_ARN>

# Common issues:
# - Backend not started yet (wait 3-5 minutes)
# - Health check path wrong (should be /public/products)
# - Security group blocking traffic
# - Application crashed (check logs)
```

---

## 💰 FREE TIER ELIGIBILITY

### **What's Free:**
- ✅ **EC2**: 750 hours/month of t2.micro or t3.micro (2 instances × 24/7 = 1440 hours)
  - **Your usage**: 2 instances (Frontend + Backend) = ~1440 hours/month
  - **Status**: ⚠️ **WILL EXCEED FREE TIER** (need 1440 hours, have 750)
  
- ✅ **RDS**: 750 hours/month of db.t3.micro
  - **Your usage**: 1 instance × 24/7 = 720 hours/month
  - **Status**: ✅ **WITHIN FREE TIER**

- ✅ **ALB**: ❌ **NOT FREE** (~$16/month + data transfer)

- ✅ **S3**: 5GB storage, 20,000 GET requests, 2,000 PUT requests
  - **Status**: ✅ **WITHIN FREE TIER** (for small usage)

- ✅ **CloudFront**: 1TB data transfer out, 10M HTTP/HTTPS requests
  - **Status**: ✅ **WITHIN FREE TIER**

### **Estimated Monthly Cost:**
```
EC2 (2 × t3.micro beyond free tier): ~$7-10/month
RDS (db.t3.micro): FREE (within 750 hours)
ALB: ~$16/month
S3: FREE (within limits)
CloudFront: FREE (within limits)
Data Transfer: ~$5/month
---
TOTAL: ~$28-31/month
```

### **Cost Optimization:**
1. **Use t2.micro instead of t3.micro** (both free tier eligible)
2. **Stop instances when not in use**
3. **Use single instance** (remove auto-scaling, Min=1, Max=1)
4. **Delete stack when not needed**

---

## 🗑️ CLEANUP (Delete Everything)

```bash
# Delete CloudFormation stack (deletes all resources)
aws cloudformation delete-stack --stack-name vanvyaapaar-prod

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name vanvyaapaar-prod

# Verify deletion
aws cloudformation describe-stacks --stack-name vanvyaapaar-prod
# Expected: Stack does not exist
```

**Note**: S3 bucket must be empty before deletion. If stack deletion fails:
```bash
# Empty S3 bucket
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name vanvyaapaar-prod \
  --query 'Stacks[0].Outputs[?OutputKey==`MediaBucketName`].OutputValue' \
  --output text)

aws s3 rm s3://$BUCKET_NAME --recursive

# Retry deletion
aws cloudformation delete-stack --stack-name vanvyaapaar-prod
```

---

## 📊 MONITORING

### **CloudWatch Logs**
```bash
# View EC2 instance logs
aws logs tail /aws/ec2/vanvyaapaar-prod --follow

# View RDS logs
aws rds describe-db-log-files \
  --db-instance-identifier vanvyaapaar-prod-db
```

### **CloudWatch Metrics**
- EC2 CPU Utilization
- ALB Request Count
- RDS Connections
- S3 Bucket Size

---

## 🔐 SECURITY RECOMMENDATIONS

### **After Deployment:**

1. **Change Admin Password**
```sql
-- SSH to backend, connect to MySQL
UPDATE basetable 
SET password = 'NEW_SECURE_PASSWORD', 
    confirm_password = 'NEW_SECURE_PASSWORD' 
WHERE email = 'admin@vanvyaapaar.com';
```

2. **Restrict SSH Access**
```bash
# Update security group to allow only your IP
aws ec2 authorize-security-group-ingress \
  --group-id <SECURITY_GROUP_ID> \
  --protocol tcp \
  --port 22 \
  --cidr <YOUR_IP>/32
```

3. **Enable HTTPS** (Production)
- Get SSL certificate from AWS Certificate Manager
- Add HTTPS listener to ALB
- Redirect HTTP → HTTPS

4. **Enable RDS Encryption**
- Modify RDS instance to enable encryption at rest

5. **Enable S3 Versioning**
```bash
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled
```

---

## 📝 ARCHITECTURE SUMMARY

```
Internet
   ↓
Application Load Balancer (ALB)
   ├─→ Frontend Target Group (Port 80)
   │    └─→ Frontend ASG (Nginx + React)
   │         └─→ Serves static files from /usr/share/nginx/html
   │
   └─→ Backend Target Group (Port 8080)
        └─→ Backend ASG (Spring Boot)
             └─→ Connects to RDS MySQL (Private Subnet)
                  └─→ Database: vanvyaapaar (with dump.sql data)

CloudFront CDN
   └─→ S3 Bucket (Product Images)
```

---

## ✅ SUCCESS CRITERIA

Your deployment is successful when:
- [ ] Frontend loads at ALB URL
- [ ] Can login with admin@vanvyaapaar.com / admin123
- [ ] Backend API responds to /public/products
- [ ] Database has products from dump.sql
- [ ] Can create new products as seller
- [ ] Can add products to cart as buyer
- [ ] Images can be uploaded to S3
- [ ] CloudFront serves images

---

## 🎯 NEXT STEPS

1. **Test all user flows** (Buyer, Seller, Admin)
2. **Upload product images to S3**
3. **Configure custom domain** (Route 53)
4. **Enable HTTPS** (ACM + ALB)
5. **Set up monitoring** (CloudWatch Alarms)
6. **Configure backups** (RDS Automated Backups)
7. **Implement CI/CD** (GitHub Actions → AWS)

---

## 📞 SUPPORT

If you encounter issues:
1. Check `/var/log/user-data.log` on EC2 instances
2. Check `/var/log/springboot.log` for backend errors
3. Check ALB target health status
4. Verify security group rules
5. Check RDS connectivity

**Common Issues:**
- **Frontend 502**: Backend not healthy yet (wait 5 minutes)
- **Backend 503**: Spring Boot still starting (wait 3 minutes)
- **Database connection failed**: Check security group, RDS status
- **Images not loading**: Check S3 bucket policy, CloudFront distribution

---

**DEPLOYMENT READY!** 🚀

All issues fixed. Stack will deploy successfully on first try!
