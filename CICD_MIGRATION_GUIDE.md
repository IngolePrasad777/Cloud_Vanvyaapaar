# CI/CD Migration Guide: From UserData to CodePipeline

## 🔄 Current vs CI/CD Architecture

### **Current Setup (UserData-based)**
- Code deployment happens via **UserData scripts** during EC2 launch
- Every instance launch clones from GitHub and builds the app
- No automated deployments on code changes
- Manual stack updates required for new code

### **CI/CD Setup (CodePipeline-based)**
- Code deployment happens via **CodeDeploy**
- GitHub webhook triggers automatic pipeline
- CodeBuild compiles artifacts
- CodeDeploy deploys to running instances (no restart needed)
- Zero-downtime blue/green or rolling deployments

---

## 📋 Key Changes Required in infrastructure.yaml

### 1. **Add New Parameters**

```yaml
Parameters:
  # ... existing parameters ...
  
  GitHubToken:
    Description: GitHub Personal Access Token for CodePipeline
    Type: String
    NoEcho: true
  
  GitHubOwner:
    Description: GitHub repository owner
    Type: String
    Default: "IngolePrasad777"
  
  GitHubRepo:
    Description: GitHub repository name
    Type: String
    Default: "Cloud_Vanvyaapaar"
  
  GitHubBranch:
    Description: GitHub branch to track
    Type: String
    Default: "main"
```

### 2. **Add S3 Bucket for Artifacts**

```yaml
Resources:
  ArtifactBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub ${EnvironmentName}-cicd-artifacts-${AWS::AccountId}
      VersioningConfiguration:
        Status: Enabled
      LifecycleConfiguration:
        Rules:
          - Id: DeleteOldArtifacts
            Status: Enabled
            ExpirationInDays: 30
```

### 3. **Add CodeBuild Projects**

#### **Frontend Build Project**
```yaml
  FrontendBuildProject:
    Type: AWS::CodeBuild::Project
    Properties:
      Name: !Sub ${EnvironmentName}-frontend-build
      ServiceRole: !GetAtt CodeBuildRole.Arn
      Artifacts:
        Type: CODEPIPELINE
      Environment:
        Type: LINUX_CONTAINER
        ComputeType: BUILD_GENERAL1_SMALL
        Image: aws/codebuild/standard:7.0
        EnvironmentVariables:
          - Name: VITE_API_URL
            Value: !Sub http://${ExternalALB.DNSName}
      Source:
        Type: CODEPIPELINE
        BuildSpec: |
          version: 0.2
          phases:
            install:
              runtime-versions:
                nodejs: 18
            pre_build:
              commands:
                - cd vanvyapaar-frontend
                - npm install --legacy-peer-deps
            build:
              commands:
                - npm run build
          artifacts:
            files:
              - '**/*'
            base-directory: vanvyapaar-frontend/dist
```

#### **Backend Build Project**
```yaml
  BackendBuildProject:
    Type: AWS::CodeBuild::Project
    Properties:
      Name: !Sub ${EnvironmentName}-backend-build
      ServiceRole: !GetAtt CodeBuildRole.Arn
      Artifacts:
        Type: CODEPIPELINE
      Environment:
        Type: LINUX_CONTAINER
        ComputeType: BUILD_GENERAL1_SMALL
        Image: aws/codebuild/standard:7.0
        EnvironmentVariables:
          - Name: RDS_ENDPOINT
            Value: !GetAtt RDSInstance.Endpoint.Address
          - Name: S3_BUCKET
            Value: !Ref MediaBucket
          - Name: CLOUDFRONT_URL
            Value: !Sub https://${CloudFrontDistribution.DomainName}
      Source:
        Type: CODEPIPELINE
        BuildSpec: |
          version: 0.2
          phases:
            install:
              runtime-versions:
                java: corretto17
            build:
              commands:
                - cd vanpaayaar-backend
                - chmod +x mvnw
                - ./mvnw clean package -DskipTests
          artifacts:
            files:
              - target/*.jar
              - appspec.yml
              - scripts/**/*
            base-directory: vanpaayaar-backend
```

### 4. **Add CodeDeploy Applications**

```yaml
  FrontendCodeDeployApp:
    Type: AWS::CodeDeploy::Application
    Properties:
      ApplicationName: !Sub ${EnvironmentName}-frontend
      ComputePlatform: Server

  BackendCodeDeployApp:
    Type: AWS::CodeDeploy::Application
    Properties:
      ApplicationName: !Sub ${EnvironmentName}-backend
      ComputePlatform: Server

  FrontendDeploymentGroup:
    Type: AWS::CodeDeploy::DeploymentGroup
    Properties:
      ApplicationName: !Ref FrontendCodeDeployApp
      DeploymentGroupName: !Sub ${EnvironmentName}-frontend-dg
      ServiceRoleArn: !GetAtt CodeDeployRole.Arn
      DeploymentConfigName: CodeDeployDefault.AllAtOnce
      AutoScalingGroups:
        - !Ref FrontendASG
      LoadBalancerInfo:
        TargetGroupInfoList:
          - Name: !GetAtt FrontendTargetGroup.TargetGroupName

  BackendDeploymentGroup:
    Type: AWS::CodeDeploy::DeploymentGroup
    Properties:
      ApplicationName: !Ref BackendCodeDeployApp
      DeploymentGroupName: !Sub ${EnvironmentName}-backend-dg
      ServiceRoleArn: !GetAtt CodeDeployRole.Arn
      DeploymentConfigName: CodeDeployDefault.OneAtATime
      AutoScalingGroups:
        - !Ref BackendASG
      LoadBalancerInfo:
        TargetGroupInfoList:
          - Name: !GetAtt BackendTargetGroup.TargetGroupName
```

### 5. **Add CodePipeline**

```yaml
  CICDPipeline:
    Type: AWS::CodePipeline::Pipeline
    Properties:
      Name: !Sub ${EnvironmentName}-pipeline
      RoleArn: !GetAtt CodePipelineRole.Arn
      ArtifactStore:
        Type: S3
        Location: !Ref ArtifactBucket
      Stages:
        # Stage 1: Source (GitHub)
        - Name: Source
          Actions:
            - Name: SourceAction
              ActionTypeId:
                Category: Source
                Owner: ThirdParty
                Provider: GitHub
                Version: '1'
              Configuration:
                Owner: !Ref GitHubOwner
                Repo: !Ref GitHubRepo
                Branch: !Ref GitHubBranch
                OAuthToken: !Ref GitHubToken
              OutputArtifacts:
                - Name: SourceOutput
        
        # Stage 2: Build Frontend
        - Name: BuildFrontend
          Actions:
            - Name: BuildFrontendAction
              ActionTypeId:
                Category: Build
                Owner: AWS
                Provider: CodeBuild
                Version: '1'
              Configuration:
                ProjectName: !Ref FrontendBuildProject
              InputArtifacts:
                - Name: SourceOutput
              OutputArtifacts:
                - Name: FrontendBuildOutput
        
        # Stage 3: Build Backend
        - Name: BuildBackend
          Actions:
            - Name: BuildBackendAction
              ActionTypeId:
                Category: Build
                Owner: AWS
                Provider: CodeBuild
                Version: '1'
              Configuration:
                ProjectName: !Ref BackendBuildProject
              InputArtifacts:
                - Name: SourceOutput
              OutputArtifacts:
                - Name: BackendBuildOutput
        
        # Stage 4: Deploy Frontend
        - Name: DeployFrontend
          Actions:
            - Name: DeployFrontendAction
              ActionTypeId:
                Category: Deploy
                Owner: AWS
                Provider: CodeDeploy
                Version: '1'
              Configuration:
                ApplicationName: !Ref FrontendCodeDeployApp
                DeploymentGroupName: !Ref FrontendDeploymentGroup
              InputArtifacts:
                - Name: FrontendBuildOutput
        
        # Stage 5: Deploy Backend
        - Name: DeployBackend
          Actions:
            - Name: DeployBackendAction
              ActionTypeId:
                Category: Deploy
                Owner: AWS
                Provider: CodeDeploy
                Version: '1'
              Configuration:
                ApplicationName: !Ref BackendCodeDeployApp
                DeploymentGroupName: !Ref BackendDeploymentGroup
              InputArtifacts:
                - Name: BackendBuildOutput
```

### 6. **Add IAM Roles**

```yaml
  CodePipelineRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: codepipeline.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AWSCodePipelineFullAccess
      Policies:
        - PolicyName: CodePipelinePolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - s3:*
                  - codebuild:*
                  - codedeploy:*
                Resource: '*'

  CodeBuildRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: codebuild.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AWSCodeBuildAdminAccess
      Policies:
        - PolicyName: CodeBuildPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - logs:*
                  - s3:*
                  - ec2:*
                  - secretsmanager:GetSecretValue
                Resource: '*'

  CodeDeployRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: codedeploy.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AWSCodeDeployRole
```

### 7. **Modify EC2 Instance Role**

Add CodeDeploy permissions to existing `AppInstanceRole`:

```yaml
  AppInstanceRole:
    Type: AWS::IAM::Role
    Properties:
      # ... existing properties ...
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
        - arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
        - arn:aws:iam::aws:policy/SecretsManagerReadWrite
        - arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy  # NEW
```

### 8. **Modify Launch Templates - Remove Build Logic**

**CRITICAL CHANGE**: Remove all build commands from UserData. CodeDeploy will handle deployments.

#### **Frontend Launch Template UserData (Simplified)**
```yaml
UserData:
  Fn::Base64: !Sub |
    #!/bin/bash
    yum update -y
    yum install -y ruby wget nginx
    
    # Install CodeDeploy Agent
    cd /home/ec2-user
    wget https://aws-codedeploy-${AWS::Region}.s3.${AWS::Region}.amazonaws.com/latest/install
    chmod +x ./install
    ./install auto
    service codedeploy-agent start
    
    # Configure Nginx (CodeDeploy will deploy the app)
    systemctl enable nginx
    systemctl start nginx
```

#### **Backend Launch Template UserData (Simplified)**
```yaml
UserData:
  Fn::Base64: !Sub |
    #!/bin/bash
    yum update -y
    yum install -y ruby wget java-17-amazon-corretto-devel
    
    # Install CodeDeploy Agent
    cd /home/ec2-user
    wget https://aws-codedeploy-${AWS::Region}.s3.${AWS::Region}.amazonaws.com/latest/install
    chmod +x ./install
    ./install auto
    service codedeploy-agent start
```

---

## 📁 Required Files in GitHub Repository

### 1. **Frontend: `appspec.yml`**
Location: `vanvyapaar-frontend/appspec.yml`

```yaml
version: 0.0
os: linux
files:
  - source: /
    destination: /usr/share/nginx/html
hooks:
  BeforeInstall:
    - location: scripts/before_install.sh
      timeout: 300
      runas: root
  AfterInstall:
    - location: scripts/after_install.sh
      timeout: 300
      runas: root
  ApplicationStart:
    - location: scripts/start_server.sh
      timeout: 300
      runas: root
```

### 2. **Frontend Scripts**

**`vanvyapaar-frontend/scripts/before_install.sh`**
```bash
#!/bin/bash
rm -rf /usr/share/nginx/html/*
```

**`vanvyapaar-frontend/scripts/after_install.sh`**
```bash
#!/bin/bash
chown -R nginx:nginx /usr/share/nginx/html
```

**`vanvyapaar-frontend/scripts/start_server.sh`**
```bash
#!/bin/bash
systemctl restart nginx
```

### 3. **Backend: `appspec.yml`**
Location: `vanpaayaar-backend/appspec.yml`

```yaml
version: 0.0
os: linux
files:
  - source: target/
    destination: /opt/vanvyaapaar
hooks:
  ApplicationStop:
    - location: scripts/stop_server.sh
      timeout: 300
      runas: root
  BeforeInstall:
    - location: scripts/before_install.sh
      timeout: 300
      runas: root
  ApplicationStart:
    - location: scripts/start_server.sh
      timeout: 300
      runas: root
  ValidateService:
    - location: scripts/validate_service.sh
      timeout: 300
      runas: root
```

### 4. **Backend Scripts**

**`vanpaayaar-backend/scripts/stop_server.sh`**
```bash
#!/bin/bash
pkill -f 'java.*vanvyaapaar' || true
```

**`vanpaayaar-backend/scripts/before_install.sh`**
```bash
#!/bin/bash
mkdir -p /opt/vanvyaapaar
rm -rf /opt/vanvyaapaar/*.jar
```

**`vanpaayaar-backend/scripts/start_server.sh`**
```bash
#!/bin/bash
# Get RDS credentials from Secrets Manager
SECRET_ARN=$(aws rds describe-db-instances \
  --db-instance-identifier <RDS_INSTANCE_ID> \
  --query "DBInstances[0].MasterUserSecret.SecretArn" \
  --region us-east-1 \
  --output text)

SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id $SECRET_ARN \
  --region us-east-1 \
  --query SecretString \
  --output text)

DB_USER=$(echo $SECRET_JSON | jq -r .username)
DB_PASS=$(echo $SECRET_JSON | jq -r .password)
DB_HOST=<RDS_ENDPOINT>

# Start Spring Boot
nohup java -jar /opt/vanvyaapaar/*.jar \
  --spring.datasource.url=jdbc:mysql://$DB_HOST:3306/vanvyaapaar \
  --spring.datasource.username=$DB_USER \
  --spring.datasource.password=$DB_PASS \
  --server.port=8080 \
  > /var/log/springboot.log 2>&1 &
```

**`vanpaayaar-backend/scripts/validate_service.sh`**
```bash
#!/bin/bash
for i in {1..30}; do
  if curl -s http://localhost:8080/public/products > /dev/null; then
    echo "Service is healthy"
    exit 0
  fi
  sleep 2
done
echo "Service failed to start"
exit 1
```

---

## 🚀 Deployment Steps

### 1. **Create GitHub Personal Access Token**
- Go to GitHub Settings → Developer settings → Personal access tokens
- Generate token with `repo` and `admin:repo_hook` permissions
- Save the token securely

### 2. **Update GitHub Repository**
```bash
cd Cloud_Vanvyaapaar

# Add appspec.yml files
mkdir -p vanvyapaar-frontend/scripts
mkdir -p vanpaayaar-backend/scripts

# Create all the script files mentioned above
# ... (create appspec.yml and scripts)

git add .
git commit -m "Add CI/CD configuration"
git push origin main
```

### 3. **Deploy CI/CD-Enabled Stack**
```powershell
aws cloudformation create-stack `
  --stack-name vanvyaapaar-cicd `
  --template-body file://infrastructure-cicd.yaml `
  --parameters `
    ParameterKey=EnvironmentName,ParameterValue=vanvyaapaar-prod `
    ParameterKey=KeyName,ParameterValue=vanvyaapaar-key `
    ParameterKey=GitHubToken,ParameterValue=<YOUR_GITHUB_TOKEN> `
    ParameterKey=GitHubOwner,ParameterValue=IngolePrasad777 `
    ParameterKey=GitHubRepo,ParameterValue=Cloud_Vanvyaapaar `
    ParameterKey=GitHubBranch,ParameterValue=main `
  --capabilities CAPABILITY_IAM `
  --region us-east-1
```

### 4. **Test CI/CD Pipeline**
```bash
# Make a change to your code
echo "// Test change" >> vanvyapaar-frontend/src/App.tsx

# Commit and push
git add .
git commit -m "Test CI/CD pipeline"
git push origin main

# Pipeline will automatically trigger!
```

---

## 📊 Benefits of CI/CD Approach

| Aspect | UserData (Current) | CI/CD (New) |
|--------|-------------------|-------------|
| **Deployment Time** | 5-8 minutes (full rebuild) | 2-3 minutes (artifact deploy) |
| **Code Updates** | Terminate & relaunch instances | Deploy to running instances |
| **Rollback** | Redeploy old stack | One-click rollback |
| **Testing** | Manual | Automated in pipeline |
| **Zero Downtime** | ❌ No | ✅ Yes (blue/green) |
| **Automation** | Manual stack update | Automatic on git push |

---

## ⚠️ Important Notes

1. **First Deployment**: Initial stack creation still uses UserData to install CodeDeploy agent
2. **Database**: RDS remains unchanged - only application code is deployed via CI/CD
3. **Cost**: CodePipeline costs ~$1/month per active pipeline
4. **GitHub Token**: Store securely, never commit to repository

---

Would you like me to create the complete `infrastructure-cicd.yaml` file with all these changes integrated?
