# Deploy Complete VanVyaapaar Infrastructure + CI/CD Pipeline
# Single unified stack deployment

param(
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,
    
    [Parameter(Mandatory=$false)]
    [string]$StackName = "vanvyaapaar-complete",
    
    [Parameter(Mandatory=$false)]
    [string]$KeyName = "vanvyaapaar-key"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "VanVyaapaar Complete Stack Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will deploy:" -ForegroundColor Yellow
Write-Host "  ✅ VPC with Multi-AZ subnets" -ForegroundColor White
Write-Host "  ✅ Application Load Balancer" -ForegroundColor White
Write-Host "  ✅ Auto Scaling Groups (Frontend + Backend)" -ForegroundColor White
Write-Host "  ✅ RDS MySQL Database" -ForegroundColor White
Write-Host "  ✅ S3 + CloudFront for media" -ForegroundColor White
Write-Host "  ✅ CodePipeline + CodeBuild + CodeDeploy" -ForegroundColor White
Write-Host "  ✅ GitHub webhook for auto-deployments" -ForegroundColor White
Write-Host ""

# Validate GitHub token format
if (-not $GitHubToken.StartsWith("ghp_")) {
    Write-Host "⚠️  Warning: GitHub token should start with 'ghp_'" -ForegroundColor Yellow
    Write-Host "Make sure you're using a valid Personal Access Token" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Stack Name: $StackName" -ForegroundColor Cyan
Write-Host "Key Pair: $KeyName" -ForegroundColor Cyan
Write-Host "Region: us-east-1" -ForegroundColor Cyan
Write-Host ""

$confirmation = Read-Host "Do you want to proceed? (yes/no)"
if ($confirmation -ne "yes") {
    Write-Host "Deployment cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "🚀 Starting deployment..." -ForegroundColor Green
Write-Host ""

# Deploy the stack
aws cloudformation create-stack `
  --stack-name $StackName `
  --template-body file://infrastructure-complete.yaml `
  --parameters `
    ParameterKey=EnvironmentName,ParameterValue=$StackName `
    ParameterKey=KeyName,ParameterValue=$KeyName `
    ParameterKey=InstanceType,ParameterValue=t3.micro `
    ParameterKey=DBInstanceClass,ParameterValue=db.t3.micro `
    ParameterKey=GitRepositoryURL,ParameterValue=https://github.com/IngolePrasad777/Cloud_Vanvyaapaar.git `
    ParameterKey=GitHubToken,ParameterValue=$GitHubToken `
    ParameterKey=GitHubOwner,ParameterValue=IngolePrasad777 `
    ParameterKey=GitHubRepo,ParameterValue=Cloud_Vanvyaapaar `
    ParameterKey=GitHubBranch,ParameterValue=main `
  --capabilities CAPABILITY_NAMED_IAM `
  --region us-east-1

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ Stack creation initiated successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "⏳ Waiting for stack creation to complete..." -ForegroundColor Yellow
    Write-Host "This will take approximately 20-30 minutes." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "What's happening:" -ForegroundColor Cyan
    Write-Host "  1. Creating VPC and networking (2-3 min)" -ForegroundColor White
    Write-Host "  2. Creating RDS database (10-15 min)" -ForegroundColor White
    Write-Host "  3. Launching EC2 instances (5-10 min)" -ForegroundColor White
    Write-Host "  4. Setting up CI/CD pipeline (2-3 min)" -ForegroundColor White
    Write-Host ""
    Write-Host "You can monitor progress in AWS Console:" -ForegroundColor Yellow
    Write-Host "https://console.aws.amazon.com/cloudformation/home?region=us-east-1" -ForegroundColor Cyan
    Write-Host ""
    
    # Wait for stack creation
    aws cloudformation wait stack-create-complete --stack-name $StackName --region us-east-1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "🎉 DEPLOYMENT SUCCESSFUL!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        
        # Get stack outputs
        Write-Host "📊 Getting stack outputs..." -ForegroundColor Cyan
        Write-Host ""
        
        $frontendUrl = aws cloudformation describe-stacks `
          --stack-name $StackName `
          --query 'Stacks[0].Outputs[?OutputKey==`FrontendURL`].OutputValue' `
          --output text `
          --region us-east-1
        
        $pipelineUrl = aws cloudformation describe-stacks `
          --stack-name $StackName `
          --query 'Stacks[0].Outputs[?OutputKey==`PipelineURL`].OutputValue' `
          --output text `
          --region us-east-1
        
        $rdsEndpoint = aws cloudformation describe-stacks `
          --stack-name $StackName `
          --query 'Stacks[0].Outputs[?OutputKey==`RDSEndpoint`].OutputValue' `
          --output text `
          --region us-east-1
        
        Write-Host "🌐 Application URLs:" -ForegroundColor Yellow
        Write-Host "  Frontend: $frontendUrl" -ForegroundColor Cyan
        Write-Host "  Backend:  $frontendUrl/public/products" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "🔧 CI/CD Pipeline:" -ForegroundColor Yellow
        Write-Host "  Pipeline URL: $pipelineUrl" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "🗄️  Database:" -ForegroundColor Yellow
        Write-Host "  RDS Endpoint: $rdsEndpoint" -ForegroundColor Cyan
        Write-Host "  Database: vanvyaapaar" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "👤 Admin Credentials:" -ForegroundColor Yellow
        Write-Host "  Email: admin@vanvyaapaar.com" -ForegroundColor Cyan
        Write-Host "  Password: admin123" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "🚀 Next Steps:" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "1. Open the Frontend URL in your browser" -ForegroundColor White
        Write-Host "2. Test the application (may take 2-3 min to fully start)" -ForegroundColor White
        Write-Host "3. Open the Pipeline URL to see CI/CD status" -ForegroundColor White
        Write-Host "4. Push code to GitHub - pipeline will auto-deploy!" -ForegroundColor White
        Write-Host ""
        Write-Host "💡 Test automatic deployment:" -ForegroundColor Yellow
        Write-Host "  git commit --allow-empty -m 'Test CI/CD'" -ForegroundColor Cyan
        Write-Host "  git push origin main" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "🎉 Your complete infrastructure is ready!" -ForegroundColor Green
        Write-Host ""
        
    } else {
        Write-Host ""
        Write-Host "⚠️  Stack creation may have failed." -ForegroundColor Red
        Write-Host "Check AWS Console for details:" -ForegroundColor Yellow
        Write-Host "https://console.aws.amazon.com/cloudformation/home?region=us-east-1" -ForegroundColor Cyan
        Write-Host ""
    }
} else {
    Write-Host ""
    Write-Host "❌ Failed to initiate stack creation" -ForegroundColor Red
    Write-Host "Check the error message above for details" -ForegroundColor Yellow
    Write-Host ""
}
