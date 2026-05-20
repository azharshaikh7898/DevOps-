#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-iii-stack}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

terraform -chdir="$TERRAFORM_DIR" init -input=false
terraform -chdir="$TERRAFORM_DIR" apply -auto-approve -input=false \
  -var "aws_region=$AWS_REGION" \
  -var "project_name=$PROJECT_NAME"

ENGINE_REPO="$(terraform -chdir="$TERRAFORM_DIR" output -json ecr_repository_urls | jq -r '."iii-engine"')"
CALLER_REPO="$(terraform -chdir="$TERRAFORM_DIR" output -json ecr_repository_urls | jq -r '."caller-worker"')"
INFERENCE_REPO="$(terraform -chdir="$TERRAFORM_DIR" output -json ecr_repository_urls | jq -r '."inference-worker"')"

PUBLIC_INSTANCE_ID="$(terraform -chdir="$TERRAFORM_DIR" output -raw public_instance_id)"
PRIVATE_INSTANCE_ID="$(terraform -chdir="$TERRAFORM_DIR" output -raw private_instance_id)"
PUBLIC_EIP="$(terraform -chdir="$TERRAFORM_DIR" output -raw public_eip)"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

docker build -f "$ROOT_DIR/engine/Dockerfile" -t "$ENGINE_REPO:$IMAGE_TAG" "$ROOT_DIR"
docker build -f "$ROOT_DIR/caller-worker/Dockerfile" -t "$CALLER_REPO:$IMAGE_TAG" "$ROOT_DIR"
docker build -f "$ROOT_DIR/inference-worker/Dockerfile" -t "$INFERENCE_REPO:$IMAGE_TAG" "$ROOT_DIR"

docker push "$ENGINE_REPO:$IMAGE_TAG"
docker push "$CALLER_REPO:$IMAGE_TAG"
docker push "$INFERENCE_REPO:$IMAGE_TAG"

aws ssm send-command \
  --region "$AWS_REGION" \
  --document-name "AWS-RunShellScript" \
  --instance-ids "$PUBLIC_INSTANCE_ID" \
  --comment "Start III public services" \
  --parameters commands='["sudo systemctl daemon-reload","sudo systemctl enable --now iii-engine.service","sudo systemctl enable --now caller-worker.service"]'

aws ssm send-command \
  --region "$AWS_REGION" \
  --document-name "AWS-RunShellScript" \
  --instance-ids "$PRIVATE_INSTANCE_ID" \
  --comment "Start III inference worker" \
  --parameters commands='["sudo systemctl daemon-reload","sudo systemctl enable --now inference-worker.service"]'

echo "Deployment finished. Public API: http://${PUBLIC_EIP}:3111/v1/chat/completions"
