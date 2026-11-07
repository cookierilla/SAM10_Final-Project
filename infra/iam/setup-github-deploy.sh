#!/usr/bin/env bash
# One-time setup so GitHub Actions can deploy to AWS without any stored AWS keys.
# GitHub proves who it is with a short-lived OpenID Connect (OIDC) token; AWS lets ONLY
# pushes to main of cookierilla/SAM10_Final-Project assume the KapeGithubDeploy role,
# which can do two things: run deploy.sh on our one instance, and update café content in S3.
# GitHub's token names the repo with its owner and repo IDs (owner@125032983/repo@1447898669),
# so a deleted-and-recreated repo with the same name cannot reuse this role. The deploy
# workflow's "Show the identity GitHub presents to AWS" step prints the exact value to trust.
#
# Run from your PC (Git Bash, AWS_PROFILE=kape):   ./infra/iam/setup-github-deploy.sh
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")"

REGION=ap-southeast-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET=kape-lumen-content-$ACCOUNT_ID
INSTANCE_ID=$(aws ec2 describe-instances --region $REGION \
  --filters Name=tag:Name,Values=kape-lumen Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
SITE=$(aws ssm get-parameter --region $REGION --name /kape-lumen/env/SITE_ADDRESS --query Parameter.Value --output text)
PROVIDER=arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com

# 1. Trust GitHub's token issuer (once per account).
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER" >/dev/null 2>&1; then
  echo "OIDC provider already exists"
else
  aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com --tags Key=Project,Value=SAM10 >/dev/null
  echo "Created OIDC provider for GitHub Actions"
fi

# 2. The role, limited to this repo's main branch, with least-privilege permissions.
sed "s/ACCOUNT_ID/$ACCOUNT_ID/g" github-deploy-trust.json > github-deploy-trust.rendered.json
sed -e "s/ACCOUNT_ID/$ACCOUNT_ID/g" -e "s/INSTANCE_ID/$INSTANCE_ID/g" -e "s/BUCKET_NAME/$BUCKET/g" \
  github-deploy-policy.json > github-deploy-policy.rendered.json
if aws iam get-role --role-name KapeGithubDeploy >/dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name KapeGithubDeploy --policy-document file://github-deploy-trust.rendered.json
  echo "Updated role KapeGithubDeploy"
else
  aws iam create-role --role-name KapeGithubDeploy --max-session-duration 3600 \
    --assume-role-policy-document file://github-deploy-trust.rendered.json --tags Key=Project,Value=SAM10 >/dev/null
  echo "Created role KapeGithubDeploy"
fi
aws iam put-role-policy --role-name KapeGithubDeploy --policy-name KapeGithubDeployLeast \
  --policy-document file://github-deploy-policy.rendered.json

cat <<EOF

Done. Now add these 4 repository VARIABLES on GitHub (not secrets: none of them is a password):
  github.com/cookierilla/SAM10_Final-Project -> Settings -> Secrets and variables -> Actions -> Variables tab -> New repository variable

  AWS_DEPLOY_ROLE_ARN = arn:aws:iam::$ACCOUNT_ID:role/KapeGithubDeploy
  INSTANCE_ID         = $INSTANCE_ID
  CONTENT_BUCKET      = $BUCKET
  SITE_ADDRESS        = $SITE
EOF
