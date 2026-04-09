# ---------------------------------------------
# VPC
# ---------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "membership-blog-eks-vpc" }
}

# ---------------------------------------------
# Internet Gateway
# ---------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "membership-blog-eks-igw" }
}

# ---------------------------------------------
# Public subnets
# ---------------------------------------------
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true
  tags = {
    Name                     = "eks-public-subnet-a"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "public_c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true
  tags = {
    Name                     = "eks-public-subnet-c"
    "kubernetes.io/role/elb" = "1"
  }
}

# ---------------------------------------------
# Private subnets (RDS)
# ---------------------------------------------
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "ap-northeast-1a"
  tags = {
    Name                              = "eks-private-subnet-a"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "private_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "ap-northeast-1c"
  tags = {
    Name                              = "eks-private-subnet-c"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# ---------------------------------------------
# Route tables
# ---------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "eks-public-rt" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "eks-private-rt" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_c" {
  subnet_id      = aws_subnet.private_c.id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------
# Security group for EKS nodes
# Allows inter-node traffic and inbound from the ALB on port 8000
# ---------------------------------------------
resource "aws_security_group" "eks_nodes" {
  name        = "membership-blog-eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  # Allow all traffic between nodes in the same SG (required for pod-to-pod communication)
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Allow inbound on application port from anywhere (ALB forwards to this port)
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS from control plane for kubelet/API communication
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "membership-blog-eks-nodes-sg" }
}
