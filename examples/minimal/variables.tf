variable "name" {
  description = "Name of the ALB."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs."
  type        = list(string)
}
