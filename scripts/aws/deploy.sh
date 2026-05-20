#!/usr/bin/env bash
set -euo pipefail

# Build & push Docker images to ECR, then run Terraform to provision EC2 and start services.
# Prereqs: awscli, docker, terraform installed and configured. Configure AWS CLI with credentials.

AWS_REGION=${AWS_REGION:-us-east-1}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
ECR_PREFIX=${ECR_PREFIX:-${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com}
TF_DIR=${TF_DIR:-aws/terraform}

REPOS=(iii-engine caller-worker inference-worker)

echo "AWS_REGION=$AWS_REGION AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID ECR_PREFIX=$ECR_PREFIX"

# Create ECR repos if they don't exist
for repo in "${REPOS[@]}"; do
  if ! aws ecr describe-repositories --repository-names "$repo" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "Creating ECR repo: $repo"
    aws ecr create-repository --repository-name "$repo" --region "$AWS_REGION" >/dev/null
  else
    echo "ECR repo $repo already exists"
  fi
done

# Build and push images
build_and_push() {
  local name=$1
  local dir=$2
  local image_uri=${ECR_PREFIX}/${name}:latest

  echo "Building $name"
  docker build -t ${name}:latest ${dir}

  echo "Tagging $image_uri"
  docker tag ${name}:latest ${image_uri}

  echo "Logging into ECR"
  aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_PREFIX%%/*}

  echo "Pushing $image_uri"
  docker push ${image_uri}

  echo "Pushed: $image_uri"
  echo
  echo ${image_uri}
}

ENGINE_URI=$(build_and_push iii-engine engine)
CALLER_URI=$(build_and_push caller-worker caller-worker)
INFERENCE_URI=$(build_and_push inference-worker inference-worker)

# Export image URIs for Terraform or later use
export III_ENGINE_IMAGE=${ENGINE_URI}
export CALLER_IMAGE=${CALLER_URI}
export INFERENCE_IMAGE=${INFERENCE_URI}

# Run Terraform (assumes aws/terraform exists and uses variables for image URIs)
if [ -d "$TF_DIR" ]; then
  echo "Initializing Terraform in $TF_DIR"
  terraform -chdir="$TF_DIR" init
  echo "Applying Terraform (plan will show resources)"
  terraform -chdir="$TF_DIR" apply -var "engine_image=${III_ENGINE_IMAGE}" -var "caller_image=${CALLER_IMAGE}" -var "inference_image=${INFERENCE_IMAGE}" -auto-approve
  echo "Terraform applied"
else
  echo "Terraform directory $TF_DIR not found. Skipping terraform apply. Please provision AWS VPC and EC2 manually or add $TF_DIR."
fi

cat <<EOF

Deployment summary:
  Engine image: ${III_ENGINE_IMAGE}
  Caller image: ${CALLER_IMAGE}
  Inference image: ${INFERENCE_IMAGE}

Next steps:
- Ensure the EC2 instances are created (terraform apply) and have IAM instance profiles allowing ECR Pull and S3 access.
- Instances should use the startup scripts in deploy/aws to write /etc/iii-stack/runtime.env and start systemd units.
- Retrieve public IP of the public EC2 for curl tests.

EOF
