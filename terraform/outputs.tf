output "region" {
  value = var.aws_region
}

output "vpc_id" {
  value = aws_vpc.iii.id
}

output "public_instance_id" {
  value = aws_instance.public_api.id
}

output "private_instance_id" {
  value = aws_instance.private_inference.id
}

output "nat_instance_id" {
  value = aws_instance.nat.id
}

output "public_eip" {
  value = aws_eip.public_api.public_ip
}

output "public_private_ip" {
  value = aws_instance.public_api.private_ip
}

output "private_instance_private_ip" {
  value = aws_instance.private_inference.private_ip
}

output "nat_private_ip" {
  value = aws_instance.nat.private_ip
}

output "ecr_repository_urls" {
  value = { for name, repo in aws_ecr_repository.apps : name => repo.repository_url }
}

output "model_bucket_name" {
  value = aws_s3_bucket.model_artifacts.bucket
}

output "private_zone_id" {
  value = aws_route53_zone.private.zone_id
}

output "engine_private_dns" {
  value = aws_route53_record.engine.fqdn
}

output "ssh_username" {
  value = var.ssh_username
}
