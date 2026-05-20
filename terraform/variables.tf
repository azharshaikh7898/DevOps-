variable "aws_region" {
  description = "AWS region for the stack."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as a prefix for AWS resources."
  type        = string
  default     = "iii-stack"
}

variable "availability_zone" {
  description = "Availability zone for the EC2 instances."
  type        = string
  default     = "us-east-1a"
}

variable "vpc_cidr" {
  description = "CIDR for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR for the private subnet."
  type        = string
  default     = "10.20.2.0/24"
}

variable "public_instance_type" {
  description = "Instance type for the public EC2 instance."
  type        = string
  default     = "t3.micro"
}

variable "private_instance_type" {
  description = "Instance type for the private EC2 instance."
  type        = string
  default     = "t3.micro"
}

variable "nat_instance_type" {
  description = "Instance type for the NAT instance."
  type        = string
  default     = "t3.micro"
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH to the public EC2 instance."
  type        = string
  default     = "0.0.0.0/0"
}

variable "ec2_key_name" {
  description = "Optional EC2 key pair name for SSH access to the public instance."
  type        = string
  default     = "iii-stack-key"
}

variable "private_zone_name" {
  description = "Private Route 53 zone used for internal RPC resolution."
  type        = string
  default     = "iii.internal"
}

variable "http_api_port" {
  description = "Public HTTP API port exposed by the engine container."
  type        = number
  default     = 3111
}

variable "iii_engine_port" {
  description = "WebSocket RPC port for the III engine."
  type        = number
  default     = 49134
}

variable "model_bucket_name" {
  description = "Optional custom S3 bucket name for model artifacts."
  type        = string
  default     = ""
}

variable "model_s3_prefix" {
  description = "S3 prefix that contains the model artifact files."
  type        = string
  default     = "models/gemma-3-270m/"
}

variable "model_ebs_size_gb" {
  description = "Size in GB for the EBS volume attached to the private inference instance."
  type        = number
  default     = 20
}

variable "cloudwatch_retention_days" {
  description = "Retention days for CloudWatch log groups."
  type        = number
  default     = 14
}

variable "ssh_username" {
  description = "Linux username for SSH access to the public EC2 instance."
  type        = string
  default     = "ubuntu"
}
