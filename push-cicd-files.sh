#!/bin/bash
# Script to push CI/CD configuration files to GitHub

echo "=== Pushing CI/CD Files to GitHub ==="

# Make scripts executable
echo "Making scripts executable..."
chmod +x vanvyapaar-frontend/scripts/*.sh
chmod +x vanpaayaar-backend/scripts/*.sh

# Check git status
echo -e "\nChecking git status..."
git status

# Add all CI/CD files
echo -e "\nAdding CI/CD configuration files..."
git add vanvyapaar-frontend/buildspec.yml
git add vanvyapaar-frontend/appspec.yml
git add vanvyapaar-frontend/scripts/

git add vanpaayaar-backend/buildspec.yml
git add vanpaayaar-backend/appspec.yml
git add vanpaayaar-backend/scripts/

# Commit
echo -e "\nCommitting changes..."
git commit -m "Add CI/CD configuration (buildspec.yml, appspec.yml, deployment scripts)"

# Push to GitHub
echo -e "\nPushing to GitHub..."
git push origin main

echo -e "\n✓ CI/CD files pushed successfully!"
echo "Repository: https://github.com/IngolePrasad777/Cloud_Vanvyaapaar.git"
