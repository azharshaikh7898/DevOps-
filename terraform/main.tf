data "aws_caller_identity" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
    Platform  = "AWS"
    Env       = "dev"
  }

  model_bucket_name = var.model_bucket_name != "" ? var.model_bucket_name : "${var.project_name}-${data.aws_caller_identity.current.account_id}-models"
  engine_dns        = "iii-engine.${var.private_zone_name}"
  caller_dns        = "caller-worker.${var.private_zone_name}"
  inference_dns     = "inference-worker.${var.private_zone_name}"
}

resource "aws_vpc" "iii" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_internet_gateway" "iii" {
  vpc_id = aws_vpc.iii.id

  tags = merge(local.tags, {
    Name = "${var.project_name}-igw"
  })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.iii.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-public-subnet"
  })
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.iii.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${var.project_name}-private-subnet"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.iii.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.iii.id
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.iii.id

  tags = merge(local.tags, {
    Name = "${var.project_name}-private-rt"
  })
}

resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id

  timeouts {
    create = "5m"
    delete = "5m"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "public_instance" {
  name               = "${var.project_name}-public-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role" "private_instance" {
  name               = "${var.project_name}-private-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role" "nat_instance" {
  name               = "${var.project_name}-nat-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "public_ssm" {
  role       = aws_iam_role.public_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "public_ecr" {
  role       = aws_iam_role.public_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "public_cw" {
  role       = aws_iam_role.public_instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "private_ssm" {
  role       = aws_iam_role.private_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "private_ecr" {
  role       = aws_iam_role.private_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "private_cw" {
  role       = aws_iam_role.private_instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "nat_ssm" {
  role       = aws_iam_role.nat_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "nat_cw" {
  role       = aws_iam_role.nat_instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_policy" "private_s3_read" {
  name = "${var.project_name}-private-s3-read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.model_artifacts.arn
        Condition = {
          StringLike = {
            "s3:prefix" = [var.model_s3_prefix, "${var.model_s3_prefix}*"]
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.model_artifacts.arn}/${var.model_s3_prefix}*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "private_s3_read" {
  role       = aws_iam_role.private_instance.name
  policy_arn = aws_iam_policy.private_s3_read.arn
}

resource "aws_iam_instance_profile" "public_instance" {
  name = "${var.project_name}-public-instance"
  role = aws_iam_role.public_instance.name
}

resource "aws_iam_instance_profile" "private_instance" {
  name = "${var.project_name}-private-instance"
  role = aws_iam_role.private_instance.name
}

resource "aws_iam_instance_profile" "nat_instance" {
  name = "${var.project_name}-nat-instance"
  role = aws_iam_role.nat_instance.name
}

resource "aws_security_group" "public" {
  name        = "${var.project_name}-public-sg"
  description = "Public API and internal RPC on the public EC2 instance"
  vpc_id      = aws_vpc.iii.id

  ingress {
    description = "SSH from admin CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Public HTTP API"
    from_port   = var.http_api_port
    to_port     = var.http_api_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "private" {
  name        = "${var.project_name}-private-sg"
  description = "Private inference worker SG"
  vpc_id      = aws_vpc.iii.id

  ingress {
    description = "Optional bastion SSH from the public subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.public_subnet_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "public_rpc_from_private" {
  security_group_id            = aws_security_group.public.id
  referenced_security_group_id = aws_security_group.private.id
  ip_protocol                  = "tcp"
  from_port                    = var.iii_engine_port
  to_port                      = var.iii_engine_port
  description                  = "Internal III WebSocket RPC from private inference SG"
}

resource "aws_vpc_security_group_ingress_rule" "private_rpc_from_public" {
  security_group_id            = aws_security_group.private.id
  referenced_security_group_id = aws_security_group.public.id
  ip_protocol                  = "tcp"
  from_port                    = var.iii_engine_port
  to_port                      = var.iii_engine_port
  description                  = "Internal III WebSocket RPC from public API SG"
}

resource "aws_security_group" "nat" {
  name        = "${var.project_name}-nat-sg"
  description = "NAT instance security group"
  vpc_id      = aws_vpc.iii.id

  ingress {
    description = "SSH from admin CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Traffic from private subnet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.private_subnet_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecr_repository" "apps" {
  for_each = toset(["iii-engine", "caller-worker", "inference-worker"])

  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_s3_bucket" "model_artifacts" {
  bucket        = local.model_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "model_artifacts" {
  bucket = aws_s3_bucket.model_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "model_artifacts" {
  bucket = aws_s3_bucket.model_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "model_artifacts" {
  bucket                  = aws_s3_bucket.model_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_route53_zone" "private" {
  name = var.private_zone_name

  vpc {
    vpc_id = aws_vpc.iii.id
  }

  comment = "Private zone for III internal RPC"
}

resource "aws_eip" "public_api" {
  domain = "vpc"
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_instance" "nat" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.nat_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.nat.id]
  associate_public_ip_address = true
  source_dest_check           = false
  iam_instance_profile        = aws_iam_instance_profile.nat_instance.name
  key_name                    = var.ec2_key_name != "" ? var.ec2_key_name : null
  private_ip                  = cidrhost(var.public_subnet_cidr, 11)
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/user-data-nat.sh.tftpl", {
    vpc_cidr = var.vpc_cidr
  })

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-nat"
  })
}

resource "aws_eip_association" "nat" {
  allocation_id = aws_eip.nat.id
  instance_id   = aws_instance.nat.id
}

resource "aws_instance" "public_api" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.public_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.public.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.public_instance.name
  key_name                    = var.ec2_key_name != "" ? var.ec2_key_name : null
  private_ip                  = cidrhost(var.public_subnet_cidr, 10)
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/user-data-public.sh.tftpl", {
    project_name      = var.project_name
    aws_region        = var.aws_region
    engine_image      = aws_ecr_repository.apps["iii-engine"].repository_url
    caller_image      = aws_ecr_repository.apps["caller-worker"].repository_url
    engine_dns        = local.engine_dns
    http_api_port     = var.http_api_port
    rpc_port          = var.iii_engine_port
    private_zone_name = var.private_zone_name
  })

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-public-api"
  })

  depends_on = [aws_eip_association.nat]
}

resource "aws_eip_association" "public_api" {
  allocation_id = aws_eip.public_api.id
  instance_id   = aws_instance.public_api.id
}

resource "aws_instance" "private_inference" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.private_instance_type
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.private.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.private_instance.name
  key_name                    = var.ec2_key_name != "" ? var.ec2_key_name : null
  private_ip                  = cidrhost(var.private_subnet_cidr, 10)
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/user-data-private.sh.tftpl", {
    project_name      = var.project_name
    aws_region        = var.aws_region
    inference_image   = aws_ecr_repository.apps["inference-worker"].repository_url
    engine_dns        = local.engine_dns
    model_bucket_name = aws_s3_bucket.model_artifacts.bucket
    model_s3_prefix   = var.model_s3_prefix
    model_path        = "/models"
    rpc_port          = var.iii_engine_port
  })

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-private-inference"
  })

  depends_on = [aws_eip_association.nat, aws_route53_record.engine]
}

resource "aws_ebs_volume" "model_disk" {
  availability_zone = var.availability_zone
  size              = var.model_ebs_size_gb
  type              = "gp3"

  tags = merge(local.tags, {
    Name = "${var.project_name}-model-disk"
  })
}

resource "aws_volume_attachment" "model_attach" {
  device_name  = "/dev/xvdf"
  volume_id    = aws_ebs_volume.model_disk.id
  instance_id  = aws_instance.private_inference.id
  force_detach = true

  depends_on = [aws_instance.private_inference]
}

resource "aws_route53_record" "engine" {
  zone_id = aws_route53_zone.private.zone_id
  name    = local.engine_dns
  type    = "A"
  ttl     = 30
  records = [aws_instance.public_api.private_ip]
}

resource "aws_route53_record" "caller" {
  zone_id = aws_route53_zone.private.zone_id
  name    = local.caller_dns
  type    = "A"
  ttl     = 30
  records = [aws_instance.public_api.private_ip]
}

resource "aws_route53_record" "inference" {
  zone_id = aws_route53_zone.private.zone_id
  name    = local.inference_dns
  type    = "A"
  ttl     = 30
  records = [aws_instance.private_inference.private_ip]
}

resource "aws_cloudwatch_log_group" "engine" {
  name              = "/iii-stack/engine"
  retention_in_days = tonumber(var.cloudwatch_retention_days)
}

resource "aws_cloudwatch_log_group" "caller" {
  name              = "/iii-stack/caller-worker"
  retention_in_days = tonumber(var.cloudwatch_retention_days)
}

resource "aws_cloudwatch_log_group" "inference" {
  name              = "/iii-stack/inference-worker"
  retention_in_days = tonumber(var.cloudwatch_retention_days)
}
