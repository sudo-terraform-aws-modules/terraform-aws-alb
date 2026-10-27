variable "name" {
  description = "Name of the ALB."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_ids" {
  description = "List of public subnet IDs."
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs."
  type        = list(string)
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener."
  type        = string
}

variable "access_logs_bucket" {
  description = "S3 bucket name to receive ALB access logs. The bucket policy must allow the regional ELB service account to write."
  type        = string
}
