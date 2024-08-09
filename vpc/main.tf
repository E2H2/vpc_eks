terraform {
    required_providers {
      aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
      }
    }
}

# vpc 정의
resource "aws_vpc" "this" {
    cidr_block = "10.50.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support = true
    tags = {
        Name = "eks-vpc"
    }
}

# IGW를 생성

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name = "eks-vpc-igw"
  }
}

# vpc와 IGW 연결 (이미 vpc를 지정했기 때문에 패스)
# NATGW를 위한 탄력 IP 생성
resource "aws_eip" "this" {
    lifecycle {
      create_before_destroy = true #재생성시 먼저 새로운 eip를 하나 만들고 기존 것을 삭제
    }
    tags = {
      Name = "eks-vpc-eip"
    }
  
}

# 퍼블릭 서브넷 생성
resource "aws_subnet" "pub_sub1" {
    vpc_id = aws_vpc.this.id #위에서 aws_vpc라는 리소스로 만든 this라는 리소스의 id
    cidr_block = "10.50.10.0/24"
    map_public_ip_on_launch = true
    enable_resource_name_dns_a_record_on_launch = true
    availability_zone = "ap-northeast-2a"
    tags = {
        Name = "pub-sub1"
        "kubernetes.io/cluster/pri-cluster" = "owned"
        "kubernetes.io/role/elb" = "1"
   
    }
    depends_on = [ aws_internet_gateway.this ]
}
# 퍼블릭 서브넷 하나 더 만듦
resource "aws_subnet" "pub_sub2" {
    vpc_id = aws_vpc.this.id #위에서 aws_vpc라는 리소스로 만든 this라는 리소스의 id
    cidr_block = "10.50.11.0/24"
    map_public_ip_on_launch = true
    enable_resource_name_dns_a_record_on_launch = true
    availability_zone = "ap-northeast-2c"
    tags = {
        Name = "pub-sub2"
        "kubernetes.io/cluster/pri-cluster" = "owned"
        "kubernetes.io/role/elb" = "1"
   
    }
    depends_on = [ aws_internet_gateway.this ]
}



# NATGW를 생성 (원래는 퍼블릭 서브넷이 2개 있다면 NATGW를 각각의 서브넷에 만들어야하지만
#               , 퍼블릭 서브넷 하나에만 생성할 예정)

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.this.id
  subnet_id     = aws_subnet.pub_sub1.id

  tags = {
    Name = "eks-vpc-natgw"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.this]
}

# 프라이빗 서브넷 생성

resource "aws_subnet" "pri_sub1" {
    vpc_id = aws_vpc.this.id #위에서 aws_vpc라는 리소스로 만든 this라는 리소스의 id
    cidr_block = "10.50.20.0/24"
    enable_resource_name_dns_a_record_on_launch = true
    availability_zone = "ap-northeast-2a"
    tags = {
        Name = "pri-sub1"
        "kubernetes.io/cluster/pri-cluster" = "owned"
        "kubernetes.io/role/internal-elb" = "1"
   
    }
    depends_on = [ aws_nat_gateway.this ]
}

resource "aws_subnet" "pri_sub2" {
    vpc_id = aws_vpc.this.id #위에서 aws_vpc라는 리소스로 만든 this라는 리소스의 id
    cidr_block = "10.50.21.0/24"
    enable_resource_name_dns_a_record_on_launch = true
    availability_zone = "ap-northeast-2c"
    tags = {
        Name = "pri-sub2"
        "kubernetes.io/cluster/pri-cluster" = "owned"
        "kubernetes.io/role/internal-elb" = "1"
   
    }
    depends_on = [ aws_nat_gateway.this ]
}

# 퍼블릭 라우팅 테이블 정의
resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.this.id
  # 로컬에서 라우팅하는 것
  route {
    cidr_block = "10.50.0.0/16" # 목적지
    gateway_id = "local"        
  }

  # 외부로 라우팅하고 싶다면
  route {
    cidr_block = "0.0.0.0/0" # 목적지
    gateway_id = aws_internet_gateway.this.id 
  }

  tags = {
    Name = "eks-vpc-pub-rt"
  }
}

# 프라이빗 라우팅 테이블 정의
resource "aws_route_table" "pri_rt" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "10.50.0.0/16"
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.this.id
  }
  tags = {
    Name = "eks-vpc-pri-rt"
  }
}

# 라우팅 테이블과 서브넷을 붙어줌 (정책을 반영!)
# 퍼블릭 라우팅 테이블과 퍼블릭 서브넷을 연결
resource "aws_route_table_association" "pub1_rt_asso" {
    subnet_id = aws_subnet.pub_sub1.id
    route_table_id = aws_route_table.pub_rt.id
}

resource "aws_route_table_association" "pub2_rt_asso" {
    subnet_id = aws_subnet.pub_sub2.id
    route_table_id = aws_route_table.pub_rt.id
}


# 프라이빗 라우팅 테이블과 프라이빗 서브넷을 연결
resource "aws_route_table_association" "pri1_rt_asso" {
    subnet_id = aws_subnet.pri_sub1.id
    route_table_id = aws_route_table.pri_rt.id
}

resource "aws_route_table_association" "pri2_rt_asso" {
    subnet_id = aws_subnet.pri_sub2.id
    route_table_id = aws_route_table.pri_rt.id
}

# 보안그룹 생성

resource "aws_security_group" "eks-vpc-pub-sg" {
    vpc_id = aws_vpc.this.id
    name = "eks-vpc-pub-sg"
    tags = {
        Name = "eks-vpc-pub-sg"
    }
}
# 인그리스 규칙, 이그리스 규칙
    # 보안그룹 내 정책
    #  1. http 인그리스 규칙 허용
resource "aws_security_group_rule" "eks-vpc-http-ingress" {
    type = "ingress"
    from_port = 80
    to_port = 80
    protocol = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
    security_group_id = aws_security_group.eks-vpc-pub-sg.id
    lifecycle {
      create_before_destroy = true
    }
 
}

    # 2. ssh 허용

resource "aws_security_group_rule" "eks-vpc-ssh-ingress" {
    type = "ingress"
    from_port = 22
    to_port = 22
    protocol = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
    security_group_id = aws_security_group.eks-vpc-pub-sg.id
    lifecycle {
      create_before_destroy = true
    }
 
}

    # 3. 이그리스 규칙 (아웃바운드)
resource "aws_security_group_rule" "eks-vpc-all-egress" {
    type = "egress"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [ "0.0.0.0/0"]
    security_group_id = aws_security_group.eks-vpc-pub-sg.id
    lifecycle {
      create_before_destroy = true
    }
 
}
