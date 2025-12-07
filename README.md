# IaC CA2 - Lab Terraform
This is the repo for the IaC module CA2 - Lab Terraform built by L00196726 - Matheus Maximo de Araujo

## The application
This repo uses an application built on https://github.com/L00196726/url-shortner
This is a simple URL Shortener RestAPI with 3 endpoints: GET health, GET and POST shorten. More details on the above repo.
I am using it here as the Docker Image for the application to be deployed
The image used is `docker push matheusmaximo/url-shortener:latest`

## The architecture
Requests comes from Internet and goes to an Application Load Balancer.
That ALB forwards traffic from and through the K8s Ingress and K8s Service (url-shortener-svc)
The traffic is then forwarded to inside the EKS Cluster that contains two replicas running on different AZs.
The ALB ensures the Nodes will receive traffic according to availability.

## How to deploy
There are two steps.
1. Deploy the eks to create the cluster:
```
cd terraform/eks
terraform init
terraform validate
terraform apply
```
Make not of the Region and the Cluster Name
```
aws eks update-kubeconfig  --name <Cluster Name from the EKS>  --region <Region From the EKS>
```

2. Deploy the application:
```
cd terraform/app
terraform init
terraform validate
terraform apply -var="aws_region=<Region From the EKS>" -var="eks_cluster_name=<Cluster Name from the EKS>" 
```

