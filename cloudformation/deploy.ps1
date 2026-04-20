# VanVyaapaar Nested Stacks Deployment Script
# This script uploads nested templates to S3 and deploys the main stack

param(
    [Parameter(Mandatory=$true)]
    [string]$BucketName,
    
    [Parameter(Mandatory=$false)]
    [string]$StackName = "vanvyaapaar-main",
    
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentName = "vanvyaapaar-prod",
    
    [Parameter(Mandatory=$false)]
    [string]$KeyName = "vanvyaapaar-key",
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "us-east-1"
)

Write-Host "=== VanVyaapaar Nested Stacks Deployment ===" -ForegroundColor Cyan

# 1. Create S3 bucket if it doesn't exist
Write-Host "`n[1/4] Checking S3 bucket..." -ForegroundColor Yellow
$bucketExists = aws s3 ls "s3://$BucketName" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating bucket: $BucketName" -ForegroundColor Yellow
    aws s3 mb "s3://$BucketName" --region $Region
} else {
    Write-Host "Bucket already exists: $BucketName" -ForegroundColor Green
}

# 2. Upload nested stack templates
Write-Host "`n[2/4] Uploading nested stack templates..." -ForegroundColor Yellow
$templates = @(
    "1-network.yaml",
    "2-security.yaml",
    "3-database.yaml",
    "4-storage.yaml",
    "5-loadbalancer.yaml",
    "6-compute.yaml"
)

foreach ($template in $templates) {
    Write-Host "  Uploading $template..." -ForegroundColor Gray
    aws s3 cp $template "s3://$BucketName/cloudformation/$template" --region $Region
}
Write-Host "All templates uploaded!" -ForegroundColor Green

# 3. Deploy main stack
Write-Host "`n[3/4] Deploying main stack..." -ForegroundColor Yellow
$templateUrl = "https://$BucketName.s3.amazonaws.com/cloudformation"

aws cloudformation create-stack `
    --stack-name $StackName `
    --template-body file://main.yaml `
    --parameters `
        ParameterKey=EnvironmentName,ParameterValue=$EnvironmentName `
        ParameterKey=KeyName,ParameterValue=$KeyName `
        ParameterKey=InstanceType,ParameterValue=t3.micro `
        ParameterKey=DBInstanceClass,ParameterValue=db.t3.micro `
        ParameterKey=GitRepositoryURL,ParameterValue=https://github.com/IngolePrasad777/Cloud_Vanvyaapaar.git `
        ParameterKey=TemplatesBucketURL,ParameterValue=$templateUrl `
    --capabilities CAPABILITY_IAM `
    --region $Region

if ($LASTEXITCODE -eq 0) {
    Write-Host "Stack creation initiated!" -ForegroundColor Green
    
    # 4. Monitor deployment
    Write-Host "`n[4/4] Monitoring deployment (this takes 25-30 minutes)..." -ForegroundColor Yellow
    Write-Host "Press Ctrl+C to stop monitoring (stack will continue deploying)" -ForegroundColor Gray
    
    aws cloudformation wait stack-create-complete --stack-name $StackName --region $Region
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n=== DEPLOYMENT SUCCESSFUL ===" -ForegroundColor Green
        Write-Host "`nFetching outputs..." -ForegroundColor Cyan
        aws cloudformation describe-stacks --stack-name $StackName --query 'Stacks[0].Outputs' --output table --region $Region
    } else {
        Write-Host "`n=== DEPLOYMENT FAILED ===" -ForegroundColor Red
        Write-Host "Check events: aws cloudformation describe-stack-events --stack-name $StackName --region $Region" -ForegroundColor Yellow
    }
} else {
    Write-Host "Failed to create stack!" -ForegroundColor Red
}

Write-Host "`n=== Script Complete ===" -ForegroundColor Cyan
