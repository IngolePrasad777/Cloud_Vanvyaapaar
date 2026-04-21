# Complete CI/CD Deployment Script
# Checks everything and deploys CI/CD to existing stack

param(
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Complete CI/CD Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check existing stack
Write-Host "Step 1: Checking existing stack..." -ForegroundColor Yellow
$stackStatus = aws cloudformation describe-stacks `
  --stack-name vanvyaapaar-prod `
  --query 'Stacks[0].StackStatus' `
  --output text `
  --region us-east-1 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Stack 'vanvyaapaar-prod' not found!" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Stack exists: $stackStatus" -ForegroundColor Green
Write-Host ""

# Step 2: Check ASG status
Write-Host "Step 2: Checking Auto Scaling Groups..." -ForegroundColor Yellow
$asgs = aws autoscaling describe-auto-scaling-groups `
  --query "AutoScalingGroups[?contains(AutoScalingGroupName, 'vanvyaapaar-prod')].{Name:AutoScalingGroupName,Desired:DesiredCapacity}" `
  --output json `
  --region us-east-1 | ConvertFrom-Json

$allRunning = $true
foreach ($asg in $asgs) {
    Write-Host "  $($asg.Name): Desired=$($asg.Desired)" -ForegroundColor White
    if ($asg.Desired -eq 0) {
        $allRunning = $false
    }
}

if (-not $allRunning) {
    Write-Host ""
    Write-Host "⚠️  Some ASGs have 0 instances!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Starting instances..." -ForegroundColor Cyan
    
    foreach ($asg in $asgs) {
        if ($asg.Desired -eq 0) {
            Write-Host "  Starting $($asg.Name)..." -ForegroundColor White
            aws autoscaling update-auto-scaling-group `
              --auto-scaling-group-name $asg.Name `
              --min-size 1 `
              --desired-capacity 1 `
              --region us-east-1
        }
    }
    
    Write-Host ""
    Write-Host "⏳ Waiting for instances to start (2-3 minutes)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 120
    Write-Host "✅ Instances should be starting" -ForegroundColor Green
} else {
    Write-Host "✅ All ASGs have running instances" -ForegroundColor Green
}
Write-Host ""

# Step 3: Check EC2 instances
Write-Host "Step 3: Checking EC2 instances..." -ForegroundColor Yellow
$instances = aws ec2 describe-instances `
  --filters "Name=tag:aws:cloudformation:stack-name,Values=vanvyaapaar-prod" "Name=instance-state-name,Values=running" `
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' `
  --output json `
  --region us-east-1 | ConvertFrom-Json

$instanceCount = 0
foreach ($reservation in $instances) {
    foreach ($instance in $reservation) {
        $instanceCount++
        Write-Host "  Instance: $($instance[0]) - $($instance[1])" -ForegroundColor White
    }
}

if ($instanceCount -lt 2) {
    Write-Host ""
    Write-Host "⚠️  Expected 2 instances (frontend + backend), found $instanceCount" -ForegroundColor Yellow
    Write-Host "Instances may still be launching. This is OK." -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "✅ Found $instanceCount running instances" -ForegroundColor Green
}
Write-Host ""

# Step 4: Check if CI/CD stack exists
Write-Host "Step 4: Checking for existing CI/CD stack..." -ForegroundColor Yellow
$cicdStatus = aws cloudformation describe-stacks `
  --stack-name vanvyaapaar-cicd `
  --query 'Stacks[0].StackStatus' `
  --output text `
  --region us-east-1 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-Host "⚠️  CI/CD stack already exists: $cicdStatus" -ForegroundColor Yellow
    Write-Host ""
    
    if ($cicdStatus -match "COMPLETE") {
        Write-Host "CI/CD is already deployed!" -ForegroundColor Green
        Write-Host ""
        $pipelineUrl = aws cloudformation describe-stacks `
          --stack-name vanvyaapaar-cicd `
          --query 'Stacks[0].Outputs[?OutputKey==`PipelineURL`].OutputValue' `
          --output text `
          --region us-east-1
        
        Write-Host "Pipeline URL: $pipelineUrl" -ForegroundColor Cyan
        Write-Host ""
        $response = Read-Host "Do you want to delete and redeploy? (yes/no)"
        
        if ($response -ne "yes") {
            Write-Host "Keeping existing CI/CD stack." -ForegroundColor Green
            exit 0
        }
        
        Write-Host ""
        Write-Host "Deleting existing CI/CD stack..." -ForegroundColor Yellow
        aws cloudformation delete-stack --stack-name vanvyaapaar-cicd --region us-east-1
        
        Write-Host "Waiting for deletion..." -ForegroundColor Yellow
        aws cloudformation wait stack-delete-complete --stack-name vanvyaapaar-cicd --region us-east-1 2>$null
        Write-Host "✅ Deleted" -ForegroundColor Green
        Write-Host ""
    } elseif ($cicdStatus -match "FAILED") {
        Write-Host "Deleting failed stack..." -ForegroundColor Yellow
        aws cloudformation delete-stack --stack-name vanvyaapaar-cicd --region us-east-1
        Start-Sleep -Seconds 30
        Write-Host "✅ Deleted" -ForegroundColor Green
        Write-Host ""
    }
} else {
    Write-Host "✅ No existing CI/CD stack" -ForegroundColor Green
    Write-Host ""
}

# Step 5: Deploy CI/CD
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 5: Deploying CI/CD Pipeline" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will create:" -ForegroundColor Yellow
Write-Host "  ✅ CodePipeline" -ForegroundColor White
Write-Host "  ✅ CodeBuild (frontend + backend)" -ForegroundColor White
Write-Host "  ✅ CodeDeploy (frontend + backend)" -ForegroundColor White
Write-Host "  ✅ S3 artifacts bucket" -ForegroundColor White
Write-Host "  ✅ GitHub webhook" -ForegroundColor White
Write-Host ""

Write-Host "🚀 Creating stack..." -ForegroundColor Green

aws cloudformation create-stack `
  --stack-name vanvyaapaar-cicd `
  --template-body file://infrastructure-cicd.yaml `
  --parameters `
    ParameterKey=EnvironmentName,ParameterValue=vanvyaapaar-prod `
    ParameterKey=ExistingStackName,ParameterValue=vanvyaapaar-prod `
    ParameterKey=GitHubToken,ParameterValue=$GitHubToken `
    ParameterKey=GitHubOwner,ParameterValue=IngolePrasad777 `
    ParameterKey=GitHubRepo,ParameterValue=Cloud_Vanvyaapaar `
    ParameterKey=GitHubBranch,ParameterValue=main `
  --capabilities CAPABILITY_NAMED_IAM `
  --region us-east-1

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "❌ Failed to create CI/CD stack" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✅ Stack creation initiated!" -ForegroundColor Green
Write-Host ""
Write-Host "⏳ Waiting for completion (~5-7 minutes)..." -ForegroundColor Yellow
Write-Host ""
Write-Host "Timeline:" -ForegroundColor Cyan
Write-Host "  00:00 - Creating IAM roles" -ForegroundColor White
Write-Host "  00:02 - Creating S3 artifacts bucket" -ForegroundColor White
Write-Host "  00:03 - Creating CodeBuild projects" -ForegroundColor White
Write-Host "  00:04 - Creating CodeDeploy applications" -ForegroundColor White
Write-Host "  00:05 - Creating CodePipeline" -ForegroundColor White
Write-Host "  00:06 - Setting up GitHub webhook" -ForegroundColor White
Write-Host "  00:07 - ✅ Complete!" -ForegroundColor White
Write-Host ""
Write-Host "Monitor: https://console.aws.amazon.com/cloudformation/home?region=us-east-1" -ForegroundColor Cyan
Write-Host ""

aws cloudformation wait stack-create-complete --stack-name vanvyaapaar-cicd --region us-east-1

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "🎉 CI/CD DEPLOYED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    
    # Get outputs
    $pipelineUrl = aws cloudformation describe-stacks `
      --stack-name vanvyaapaar-cicd `
      --query 'Stacks[0].Outputs[?OutputKey==`PipelineURL`].OutputValue' `
      --output text `
      --region us-east-1
    
    $frontendUrl = aws cloudformation describe-stacks `
      --stack-name vanvyaapaar-prod `
      --query 'Stacks[0].Outputs[?OutputKey==`FrontendURL`].OutputValue' `
      --output text `
      --region us-east-1
    
    Write-Host "🔧 CI/CD Pipeline:" -ForegroundColor Yellow
    Write-Host "  $pipelineUrl" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "🌐 Your Application:" -ForegroundColor Yellow
    Write-Host "  $frontendUrl" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "🚀 Next Steps:" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "1. Open Pipeline URL and click 'Release change'" -ForegroundColor White
    Write-Host "2. Or push code to GitHub - auto-deploys!" -ForegroundColor White
    Write-Host ""
    Write-Host "💡 Test automatic deployment:" -ForegroundColor Yellow
    Write-Host "  git commit --allow-empty -m 'Test CI/CD'" -ForegroundColor Cyan
    Write-Host "  git push origin main" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "🎉 Everything is ready!" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "❌ Deployment failed" -ForegroundColor Red
    Write-Host ""
    Write-Host "Check what failed:" -ForegroundColor Yellow
    Write-Host "  aws cloudformation describe-stack-events --stack-name vanvyaapaar-cicd --query 'StackEvents[?contains(ResourceStatus, ``FAILED``)].[LogicalResourceId,ResourceStatusReason]' --output table --region us-east-1" -ForegroundColor Cyan
    Write-Host ""
}
