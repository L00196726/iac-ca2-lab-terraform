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

variable "aws_ami_amzn_linux_eu_west_1" {
    description = "Amazon Linux 2 AMI ID for eu-west-1"
    type = string
    default = "ami-0acd9fd39de089f9b"
  
}