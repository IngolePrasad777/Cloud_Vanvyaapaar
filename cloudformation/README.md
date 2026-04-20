# VanVyaapaar CloudFormation Nested Stacks

This folder contains modular CloudFormation templates organized as nested stacks for better maintainability and reusability.

## 📁 Structure

```
cloudformation/
├── main.yaml              # Main orchestrator stack
├── 1-network.yaml         # VPC, Subnets, IGW, Route Tables
├── 2-security.yaml        # Security Groups
├── 3-database.yaml        # RDS MySQL
├── 4-storage.yaml         # S3 + CloudFront CDN
├── 5-loadbalancer.yaml    # ALB, Target Groups, Listeners
├── 6-compute.yaml         # IAM, Launch Templates, ASGs
└── README.md              # This file
```

## 🚀 Deployment Options

### Option 1: Deploy Individual Stacks (Manual)

Deploy each stack in order, passing outputs from previous stacks as parameters:

```powershell
# 1. Network
aws cloudformation create-stack --stack-name vanvyaapaar-network --template-body file://1-network.yaml --parameters ParameterKey=EnvironmentName,ParameterValue=vanvyaapaar-prod --region us-east-1

# 2. Security (needs VPC ID from Network stack)
aws cloudformation create-stack --stack-name vanvyaapaar-security --template-body file://2-security.yaml --parameters ParameterKey=EnvironmentName,ParameterValue=vanvyaapaar-prod ParameterKey=VPCId,ParameterValue=<VPC_ID> --region us-east-1

# ... and so on
```

### Option 2: Deploy Using Main Stack (Recommended)

**Prerequisites:**
1. Upload all nested stack templates to an S3 bucket
2. Make the bucket publicly readable or configure bucket policy

**Steps:**

```powershell
# 1. Create S3 bucket for templates
aws s3 mb s3://vanvyaapaar-cfn-templates-<your-account-id> --region us-east-1

# 2. Upload nested stack templates
aws s3 cp 1-network.yaml s3://vanvyaapaar-cfn-templates-<your-account-id>/cloudformation/
aws s3 cp 2-security.yaml s3://vanvyaapaar-cfn-templates-<your-account-id>/cloudformation/
aws s3 cp 3-database.yaml s3://vanvyaapaar-cfn-templates-<your-account-id>/cloudformation/
aws s3 cp 4-storage.yaml s3://vanvyaapaar-cfn-templates-<your-account-id>/cloudformation/
aws s3 cp 5-loadbalancer.yaml s3://vanvyaapaar-cfn-templates-<your-account-id>/cloudformation/
aws s3 cp 6-compute.yaml s3://vanvyaapaar-cfn-templates-<your-account-id>/cloudformation/

# 3. Deploy main stack
aws cloudformation create-stack `
  --stack-name vanvyaapaar-main `
  --template-body file://main.yaml `
  --parameters `
    ParameterKey=EnvironmentName,ParameterValue=vanvyaapaar-prod `
    ParameterKey=KeyName,ParameterValue=vanvyaapaar-key `
    ParameterKey=InstanceType,ParameterValue=t3.micro `
    ParameterKey=DBInstanceClass,ParameterValue=db.t3.micro `
    ParameterKey=GitRepositoryURL,ParameterValue=https://github.com/IngolePrasad777/Cloud_Vanvyaapaar.git `
    ParameterKey=TemplatesBucketURL,ParameterValue=https://vanvyaapaar-cfn-templates-<your-account-id>.s3.amazonaws.com/cloudformation `
  --capabilities CAPABILITY_IAM `
  --region us-east-1
```

## 📊 Benefits of Nested Stacks

1. **Modularity**: Each component (network, security, compute) is isolated
2. **Reusability**: Reuse network stack across multiple environments
3. **Easier Updates**: Update only the stack that changed
4. **Better Organization**: 100-200 lines per file vs 762 lines in one file
5. **Team Collaboration**: Different team members can work on different stacks
6. **Faster Debugging**: Easier to identify which component failed

## 🔄 Updating Stacks

### Update Individual Stack
```powershell
aws cloudformation update-stack --stack-name vanvyaapaar-network --template-body file://1-network.yaml --region us-east-1
```

### Update via Main Stack
```powershell
# Upload updated nested template to S3
aws s3 cp 6-compute.yaml s3://vanvyaapaar-cfn-templates-<your-account-id>/cloudformation/

# Update main stack (it will detect changes in nested stacks)
aws cloudformation update-stack --stack-name vanvyaapaar-main --template-body file://main.yaml --capabilities CAPABILITY_IAM --region us-east-1
```

## 🗑️ Deleting Stacks

### Delete Main Stack (deletes all nested stacks)
```powershell
aws cloudformation delete-stack --stack-name vanvyaapaar-main --region us-east-1
```

### Delete Individual Stacks (in reverse order)
```powershell
aws cloudformation delete-stack --stack-name vanvyaapaar-compute --region us-east-1
aws cloudformation delete-stack --stack-name vanvyaapaar-loadbalancer --region us-east-1
aws cloudformation delete-stack --stack-name vanvyaapaar-storage --region us-east-1
aws cloudformation delete-stack --stack-name vanvyaapaar-database --region us-east-1
aws cloudformation delete-stack --stack-name vanvyaapaar-security --region us-east-1
aws cloudformation delete-stack --stack-name vanvyaapaar-network --region us-east-1
```

## 📝 Stack Dependencies

```
main.yaml
├── 1-network.yaml (no dependencies)
├── 2-security.yaml (depends on: network)
├── 3-database.yaml (depends on: network, security)
├── 4-storage.yaml (no dependencies)
├── 5-loadbalancer.yaml (depends on: network, security)
└── 6-compute.yaml (depends on: all above)
```

## 🎯 Use Cases

- **Development**: Deploy only network + security for testing
- **Staging**: Full deployment with smaller instance types
- **Production**: Full deployment with larger instances and Multi-AZ RDS
- **Cost Optimization**: Delete compute stack when not in use, keep data stack

## 📚 Additional Resources

- [AWS Nested Stacks Documentation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-nested-stacks.html)
- [CloudFormation Best Practices](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/best-practices.html)
