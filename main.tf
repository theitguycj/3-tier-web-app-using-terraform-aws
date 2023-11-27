# Configure Terraform Behaviors
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}


# Configure the Provider
provider "aws" {
  region = "us-east-1"
}


# Part 0: Setup IAM (Using GitHub and Parameter Store instead of S3)
# Step 0a: IAM role permissions policies
data "aws_iam_policy" "threetas3readonly" {
  arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" # Used arn instead of name
}

data "aws_iam_policy" "threetassm" {
  name = "AmazonSSMManagedInstanceCore" # Used name instead of arn
}

# Step 0b: IAM role trust policy
data "aws_iam_policy_document" "threetatrustedentities" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Step 0c: Create IAM role and attach policies
resource "aws_iam_role" "threeta_iam_ec2_instance_role" {
  name                = "3TA-IAM-EC2-Instance-Role"
  path                = "/system/"
  assume_role_policy  = data.aws_iam_policy_document.threetatrustedentities.json
  managed_policy_arns = [data.aws_iam_policy.threetassm.arn, data.aws_iam_policy.threetas3readonly.arn]
}

#Step 0d: Create instance profile
resource "aws_iam_instance_profile" "instance_profile" {
  name = "3TA-Instance-Profile"
  role = aws_iam_role.threeta_iam_ec2_instance_role.name
}

#Step 0e: Retrieve data from & store data to the Parameter Store
# Retrieve previously stored RDS username
data "aws_ssm_parameter" "rds_username" {
  name = "rds_username"
}

# Retrieve previously stored RDS password
data "aws_ssm_parameter" "rds_password" {
  name = "rds_password"
}

# Retrieve your IPv4 IP address
data "http" "icanhazip" {
  url = "https://ipv4.icanhazip.com"
}

# Store your IPv4 IP address for security groups
resource "aws_ssm_parameter" "my_ip_address" {
  name  = "my_ip_address"
  type  = "String"
  value = "${chomp(data.http.icanhazip.body)}/32"
}

# Retrieve your Route 53 zone
data "aws_route53_zone" "threeta-selectdomain" {
  name = "aws.theitguycj.com."
}


# Part 1: Build out VPC and Networking Components
# Step 1a: Create VPC
resource "aws_vpc" "threetierarch_vpc" {
  cidr_block = "10.20.0.0/16"
  tags       = {
    Name = "3TA_VPC"
  }
}

# Step 1b: Create subnets
resource "aws_subnet" "public_subnet_az_1"{
  vpc_id            = aws_vpc.threetierarch_vpc.id
  cidr_block        = "10.20.0.0/24"
  availability_zone = "us-east-1a"
  tags              = {
    Name = "Public-Subnet-AZ1 (3TA)"
  }
}

resource "aws_subnet" "private_subnet_az_1"{
  vpc_id            = aws_vpc.threetierarch_vpc.id
  cidr_block        = "10.20.1.0/24"
  availability_zone = "us-east-1a"
  tags              = {
    Name = "Private-Subnet-AZ1 (3TA)"
  }
}

resource "aws_subnet" "private_db_subnet_az_1"{
  vpc_id            = aws_vpc.threetierarch_vpc.id
  cidr_block        = "10.20.2.0/24"
  availability_zone = "us-east-1a"
  tags              = {
    Name = "Private-DB-Subnet-AZ1 (3TA)"
  }
}

resource "aws_subnet" "public_subnet_az_2"{
  vpc_id            = aws_vpc.threetierarch_vpc.id
  cidr_block        = "10.20.3.0/24"
  availability_zone = "us-east-1f"
  tags              = {
    Name = "Public-Subnet-AZ2 (3TA)"
  }
}

resource "aws_subnet" "private_subnet_az_2"{
  vpc_id            = aws_vpc.threetierarch_vpc.id
  cidr_block        = "10.20.4.0/24"
  availability_zone = "us-east-1f"
  tags              = {
    Name = "Private-Subnet-AZ2 (3TA)"
  }
}

resource "aws_subnet" "private_db_subnet_az_2"{
  vpc_id            = aws_vpc.threetierarch_vpc.id
  cidr_block        = "10.20.5.0/24"
  availability_zone = "us-east-1f"
  tags              = {
    Name = "Private-DB-Subnet-AZ2 (3TA)"
  }
}

# Step 1c: Create Internet Gateway, Elastic IPs, & NAT Gateways
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.threetierarch_vpc.id
  tags   = {
    Name = "3TA-IGW"
  }
}

resource "aws_eip" "eip1" {
  depends_on = [aws_internet_gateway.igw]
  domain     = "vpc"
  tags       = {
    Name = "3TA-EIP1"
  }
}
resource "aws_eip" "eip2" {
  depends_on = [aws_internet_gateway.igw]
  domain     = "vpc"
  tags       = {
    Name = "3TA-EIP2"
  }
}

resource "aws_nat_gateway" "ngw1" {
  subnet_id     = aws_subnet.public_subnet_az_1.id
  allocation_id = aws_eip.eip1.id
  depends_on    = [aws_internet_gateway.igw]
  tags          = {
    Name = "3TA-NAT-GW-AZ1"
  }
}

resource "aws_nat_gateway" "ngw2" {
  subnet_id     = aws_subnet.public_subnet_az_2.id
  allocation_id = aws_eip.eip2.id
  depends_on    = [aws_internet_gateway.igw]

  tags          = {
    Name = "3TA-NAT-GW-AZ2"
  }
  
}

# Step 1d: Create route tables and subnet associations
resource "aws_route_table" "public_route" {
  vpc_id = aws_vpc.threetierarch_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "3TA-PublicRouteTable"
  }
}

resource "aws_route_table_association" "pubsubnetassociations1" {
  subnet_id      = aws_subnet.public_subnet_az_1.id
  route_table_id = aws_route_table.public_route.id
}

resource "aws_route_table_association" "pubsubnetassociations2" {
  subnet_id      = aws_subnet.public_subnet_az_2.id
  route_table_id = aws_route_table.public_route.id
}

resource "aws_route_table" "private_app_route_az1" {
  vpc_id = aws_vpc.threetierarch_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.ngw1.id
  }

  tags = {
    Name = "3TA-Private-Route-Table-AZ1"
  }
}

resource "aws_route_table_association" "prisubnetassociations1" {
  subnet_id      = aws_subnet.private_subnet_az_1.id
  route_table_id = aws_route_table.private_app_route_az1.id
}

resource "aws_route_table" "private_app_route_az2" {
  vpc_id = aws_vpc.threetierarch_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.ngw2.id
  }

  tags = {
    Name = "3TA-Private-Route-Table-AZ2"
  }
}

resource "aws_route_table_association" "prisubnetassociations2" {
  subnet_id      = aws_subnet.private_subnet_az_2.id
  route_table_id = aws_route_table.private_app_route_az2.id
}

# Step 1e: Create 5 Security Groups
resource "aws_security_group" "internetlb-sg" {
  name        = "Internet-Facing-LB-SG"
  description = "External load balancer security group"
  vpc_id      = aws_vpc.threetierarch_vpc.id
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_ssm_parameter.my_ip_address.value]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "3TA-Internet-Facing-LB-SG"
  }
}

resource "aws_security_group" "webtier-sg" {
  name        = "WebTier-SG"
  description = "SG for the Web Tier"
  vpc_id      = aws_vpc.threetierarch_vpc.id
  
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    cidr_blocks     = [aws_ssm_parameter.my_ip_address.value]
    security_groups = [aws_security_group.internetlb-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "3TA-WebTier-SG"
  }
}

resource "aws_security_group" "internallb-sg" {
  name        = "Internal-LB-SG"
  description = "SG for the internal load balancer"
  vpc_id      = aws_vpc.threetierarch_vpc.id
  
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.webtier-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "3TA-Internal-LB-SG"
  }
}

resource "aws_security_group" "private-instance-sg" {
  name        = "PrivateInstanceSG"
  description = "SG for our private app tier sg"
  vpc_id      = aws_vpc.threetierarch_vpc.id
  
  ingress {
    from_port       = 4000
    to_port         = 4000
    protocol        = "tcp"
    cidr_blocks     = [aws_ssm_parameter.my_ip_address.value]
    security_groups = [aws_security_group.internallb-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "3TA-PrivateInstanceSG"
  }
}

resource "aws_security_group" "db-sg" {
  name        = "DBSG"
  description = "SG for our databases"
  vpc_id      = aws_vpc.threetierarch_vpc.id
  
  ingress {
    from_port       = 3006
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.private-instance-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "3TA-DBSG"
  }
}


# Part 2: DB Subnet Groups and DB Deployment
resource "aws_db_subnet_group" "db_subnet_group" {
  name        = "threeta-db-subnet-group"
  description = "Subnet group for the database layer of the architecture."
  subnet_ids  = [aws_subnet.private_db_subnet_az_1.id, aws_subnet.private_db_subnet_az_2.id]
}

resource "aws_rds_cluster" "dbcluster" {
  cluster_identifier     = "threeta-database-1"
  engine                 = "aurora-mysql"
  engine_version         = "5.7.mysql_aurora.2.11.2"
  master_username        = data.aws_ssm_parameter.rds_username.value
  master_password        = data.aws_ssm_parameter.rds_password.value
  skip_final_snapshot    = "true"
  apply_immediately      = "true"
  storage_encrypted      = "true"
  vpc_security_group_ids = [aws_security_group.db-sg.id]
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.id
}

resource "aws_rds_cluster_instance" "dbclusterinstance" {
  count                      = 2
  identifier                 = "threeta-database-1-instance-${count.index}"
  cluster_identifier         = aws_rds_cluster.dbcluster.id
  instance_class             = "db.t3.small"
  engine                     = aws_rds_cluster.dbcluster.engine
  engine_version             = aws_rds_cluster.dbcluster.engine_version
  auto_minor_version_upgrade = "false"
  apply_immediately          = "true"
  promotion_tier             = "1"
  monitoring_interval        = "60"
  monitoring_role_arn        = "arn:aws:iam::524604249353:role/rds-monitoring-role"
}


# Part 3: App Tier Instance Deployment
resource "aws_instance" "apptier" {
  ami                    = "ami-0e8a34246278c21e4"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_subnet_az_1.id
  iam_instance_profile   = aws_iam_instance_profile.instance_profile.id
  vpc_security_group_ids = [aws_security_group.private-instance-sg.id]
  depends_on             = [aws_rds_cluster_instance.dbclusterinstance]
  user_data              = templatefile("app_user_data.sh", {
    WRITER-ENDPOINT = aws_rds_cluster.dbcluster.endpoint
    USERNAME        = data.aws_ssm_parameter.rds_username.value
    PASSWORD        = data.aws_ssm_parameter.rds_password.value
  })
  tags                   = {
    Name = "AppLayer"
  }
}


# Part 4: Internal Load Balancing & Auto Scaling
# Step 4a: Create App Tier AMI
resource "aws_ami_from_instance" "threeta_app_ami" {
  name               = "AppTierImage"
  source_instance_id = aws_instance.apptier.id
  depends_on         = [aws_lb.threeta_intlb]
  description        = "App Tier"
}

# Step 4b: Create LB Target Groups
resource "aws_lb_target_group" "threeta_app_tier_target_group" {
  name     = "AppTierTargetGroup"
  protocol = "HTTP"
  port     = 4000
  vpc_id   = aws_vpc.threetierarch_vpc.id
  health_check {
    path = "/health"
  }
}

# Step 4c: Create Internal Load Balancer
resource "aws_lb" "threeta_intlb" {
  name               = "app-tier-internal-lb"
  internal           = true
  load_balancer_type = "application"
  subnets            = [aws_subnet.private_subnet_az_1.id, aws_subnet.private_subnet_az_2.id]
  security_groups    = [aws_security_group.internallb-sg.id]
  depends_on         = [aws_instance.apptier]
}

resource "aws_lb_listener" "threeta_intlb_listener" {
  load_balancer_arn = aws_lb.threeta_intlb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.threeta_app_tier_target_group.arn
  }
}

# Step 4d: Launch Template
resource "aws_launch_template" "threeta-app-launch" {
  name                   = "3TA-App-Launch-Template"
  image_id               = aws_ami_from_instance.threeta_app_ami.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.private-instance-sg.id]
  iam_instance_profile {
    arn = aws_iam_instance_profile.instance_profile.arn
  }
}

# Step 4e: Auto Scaling
resource "aws_autoscaling_group" "threeta_int_asg" {
  name                = "AppTierASG"
  desired_capacity    = 2
  min_size            = 2
  max_size            = 2
  vpc_zone_identifier = [aws_subnet.private_subnet_az_1.id, aws_subnet.private_subnet_az_2.id]
  target_group_arns   = [aws_lb_target_group.threeta_app_tier_target_group.id]
  launch_template {
    id      = aws_launch_template.threeta-app-launch.id
    version = "$Latest"
  }
}


# Part 5: Web Tier Instance Deployment
# Step 5a: Deploy web instance
resource "aws_instance" "webtier" {
  ami                         = "ami-0e8a34246278c21e4"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet_az_1.id
  iam_instance_profile        = aws_iam_instance_profile.instance_profile.id
  vpc_security_group_ids      = [aws_security_group.webtier-sg.id]
  associate_public_ip_address = true
  user_data                   = templatefile("web_user_data.sh", {
    INT-LOAD-BALANCER-DNS = aws_lb.threeta_intlb.dns_name
  })
  tags                        = {
    Name = "WebLayer"
  }
}


# Part 6: External Load Balancing & Auto Scaling
# Step 6a: Create Web Tier AMI
resource "aws_ami_from_instance" "threeta_web_ami" {
  name               = "WebTierImage"
  source_instance_id = aws_instance.webtier.id
  depends_on         = [aws_lb.threeta_extlb]
  description        = "Image of our Web Tier Instance"
}

# Step 6b: Create LB Target Groups
resource "aws_lb_target_group" "threeta_web_tier_target_group" {
  name     = "WebTierTargetGroup"
  protocol = "HTTP"
  port     = 80
  vpc_id   = aws_vpc.threetierarch_vpc.id
  health_check {
    path = "/health"
  }
}

# Step 6c: Create Internet Facing Load Balancer
resource "aws_lb" "threeta_extlb" {
  name               = "web-tier-external-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_subnet_az_1.id, aws_subnet.public_subnet_az_2.id]
  security_groups    = [aws_security_group.internetlb-sg.id]
  depends_on         = [aws_instance.webtier]
}

resource "aws_lb_listener" "threeta_extlb_listener" {
  load_balancer_arn = aws_lb.threeta_extlb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.threeta_web_tier_target_group.arn
  }
}

# Step 6d: Launch Template
resource "aws_launch_template" "threeta-web-launch" {
  name                   = "3TA-Web-Launch-Template"
  image_id               = aws_ami_from_instance.threeta_web_ami.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.webtier-sg.id]
  iam_instance_profile {
    arn = aws_iam_instance_profile.instance_profile.arn
  }
}

# Step 6e: Auto Scaling
resource "aws_autoscaling_group" "threeta_web_asg" {
  name                = "WebTierASG"
  desired_capacity    = 2
  min_size            = 2
  max_size            = 2
  vpc_zone_identifier = [aws_subnet.public_subnet_az_1.id, aws_subnet.public_subnet_az_2.id]
  target_group_arns   = [aws_lb_target_group.threeta_web_tier_target_group.id]
  launch_template {
    id      = aws_launch_template.threeta-web-launch.id
    version = "$Latest"
  }
}


# Part 7: Route 53
resource "aws_route53_record" "threeta-domain" {
  zone_id = data.aws_route53_zone.threeta-selectdomain.zone_id
  name = "3ta.aws.theitguycj.com"
  type = "CNAME"
  ttl = 300
  records = [aws_lb.threeta_extlb.dns_name]
}