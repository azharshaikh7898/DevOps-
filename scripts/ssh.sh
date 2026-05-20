#!/usr/bin/env bash
set -euo pipefail

INSTANCE_ID="${1:?usage: ssh.sh INSTANCE_ID}"
AWS_REGION="${AWS_REGION:-us-east-1}"

aws ssm start-session --region "$AWS_REGION" --target "$INSTANCE_ID"
