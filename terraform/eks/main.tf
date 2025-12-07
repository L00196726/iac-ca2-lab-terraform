terraform {
  # Minimal version required by "terraform-aws-modules/vpc/aws"
  required_version = ">= 1.5.7"

  # Minimal version required by "terraform-aws-modules/eks/aws"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.25"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host        = module.eks.cluster_endpoint
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes = {
    host        = module.eks.cluster_endpoint
    config_path = "~/.kube/config"
  }
}


# VPC for the EKS Cluster
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.5"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  # I only want two AZs
  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.20.0/24"]

  # One NAT Gateway per AZ
  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# VPC Flow Logs for the EKS Cluster VPC
# This will create a CloudWatch Log Group and IAM Role automatically
# All traffic will be logged
module "flow_log" {
  source = "terraform-aws-modules/vpc/aws//modules/flow-log"

  name       = "${var.cluster_name}-flow-log"
  vpc_id     = module.vpc.vpc_id


}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.10"

  name               = var.cluster_name
  # This is the latest Kubernetes version supported by EKS
  kubernetes_version = "1.34"

  # AWS-managed Kubernetes components
  # * CoreDNS: internal DNS inside Kubernetes
  # * EKS Pod Identity Agent: manage IAM roles for service accounts
  # * kube-proxy: Kubernetes networking rules
  # * VPC CNI: networking between AWS VPC and Kubernetes
  addons = {
    coredns = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Enable public access to the EKS cluster endpoint
  # so the CICD pipeline can access it
  endpoint_public_access = true

  # Grant admin permissions to me as the cluster creator
  enable_cluster_creator_admin_permissions = true

  # AWS will manage the worker nodes
  eks_managed_node_groups = {
    example = {
      # The instance type restricts the number of ENIs we can attach
      # t3.small allows up to 3 ENIs and 4 IP addresses per ENI, which is enough for this lab
      instance_types = ["t3.small"]
      ami_type       = "AL2023_x86_64_STANDARD"
      desired_size   = 1
      min_size       = 1
      max_size       = 3
    }
  }

  tags = {
    "Name" = var.cluster_name
  }
}

resource "kubernetes_service_account_v1" "aws_lb_sa" {
  metadata {
    name      = "aws-alb-controller-sa"
    namespace = "kube-system"

    annotations = {
      "eks.amazonaws.com/role-arn" = module.aws_lb_controller_pod_identity.iam_role_arn
    }
  }
}

# ALB IAM Role for the EKS Cluster
module "aws_lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.5"

  use_name_prefix = false
  name = "${var.cluster_name}-aws-alb-controller-pod-identity"

  # Attach the AWS Load Balancer Controller IAM policy to the role
  # This policy is required for the AWS Load Balancer Controller to function
  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = kubernetes_service_account_v1.aws_lb_sa.metadata[0].name
    }
  }
}

# AWS Load Balancer Controller.
resource "helm_release" "aws_lb_controller" {
  name       = "${var.cluster_name}-aws-alb-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"

  depends_on = [
    kubernetes_service_account_v1.aws_lb_sa
  ]

  set = [
    {
      name  = "clusterName"
      value = module.eks.cluster_name
    }
    ,
    {
      name  = "serviceAccount.name"
      value = kubernetes_service_account_v1.aws_lb_sa.metadata[0].name
    }
    , {
      name  = "serviceAccount.create"
      value = "false"
    }
    , {
      name  = "region"
      value = var.aws_region
    }
    , {
      name  = "vpcId"
      value = module.vpc.vpc_id
    }
  ]
}
