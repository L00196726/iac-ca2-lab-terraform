variable "aws_region" {
  description = "AWS region to deploy the app"
  type = string
  default = "eu-west-1"
}

variable "cluster_name" {
    description = "The name of the EKS cluster"
    type        = string
    default     = "url-shortener-eu-west-1-eks"
}