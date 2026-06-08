resource "aws_s3_bucket" "musiql_bucket" {
    bucket = "musiql-s3-bucket"
}

resource "aws_vpc" "musiql_vpc" {
    cidr_block = "10.0.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support = true

    tags = {
        Name = "musiql-vpc"
    }
}

resource "aws_subnet" "private_a" {
    vpc_id = aws_vpc.musiql_vpc.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "us-east-2a"

    tags = {
        Name = "musiql-private-a"
    }
}

resource "aws_subnet" "private_b" {
    vpc_id = aws_vpc.musiql_vpc.id
    cidr_block = "10.0.2.0/24"
    availability_zone = "us-east-2b"

    tags = {
        Name = "musiql-private-b"
    }
}

# S3 Gateway Endpoint
resource "aws_vpc_endpoint" "s3" {
    vpc_id          = aws_vpc.musiql_vpc.id
    service_name    = "com.amazonaws.us-east-2.s3"
    route_table_ids = [aws_route_table.private.id]

    tags = {
        Name = "musiql-s3-endpoint"
    }
}

resource "aws_db_subnet_group" "musiql_db_subnet_group" {
    name = "musiql-db-subnet-group"
    subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

    tags = {
        Name = "musiql-db-subnet-group"
    }
}

resource "aws_security_group" "rds_sg" {
    name = "musiql-rds-sg"
    description = "Allow Postgress access from recording server and Lambda"
    vpc_id = aws_vpc.musiql_vpc.id

    ingress {
        description = "Postgres from recording server"
        from_port = 5432
        to_port = 5432
        protocol = "tcp"
        cidr_blocks = [var.recording_server_ip]
    }

    ingress {
        description = "Postgres from Lambda"
        from_port = 5432
        to_port = 5432
        protocol = "tcp"
        security_groups = [aws_security_group.lambda_sg.id]
    }

    ingress {
        description = "Postgres from bastion"
        from_port = 5432
        to_port = 5432
        protocol = "tcp"
        security_groups = [aws_security_group.bastion_sg.id]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "musiql-rds-sg"
    }
}

resource "aws_internet_gateway" "musiql_igw" {
    vpc_id = aws_vpc.musiql_vpc.id

    tags = {
        Name = "musiql-igw"
    }
}

resource "aws_subnet" "public_a" {
    vpc_id = aws_vpc.musiql_vpc.id
    cidr_block = "10.0.3.0/24"
    availability_zone = "us-east-2a"
    map_public_ip_on_launch = true

    tags = {
        Name = "musiql-public-a"
    }
}

resource "aws_route_table" "public" {
    vpc_id = aws_vpc.musiql_vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.musiql_igw.id
    }

    tags = {
        Name = "musiql-public-rt"
    }
}

resource "aws_route_table_association" "public_a" {
    subnet_id = aws_subnet.public_a.id
    route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "bastion_sg" {
    name = "musiql-bastion-sg"
    description = "Allow ssh from home IP"
    vpc_id = aws_vpc.musiql_vpc.id

    ingress {
        description = "SSH from home"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = [var.recording_server_ip]
    }

    ingress {
        description = "NAT - HTTPS from private subnets"
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["10.0.1.0/24", "10.0.2.0/24"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "musiql-bastion-sg"
    }
}

data "aws_ami" "ubuntu" {
    most_recent = true
    owners = ["099720109477"] # Canonical's account ID

    filter {
        name = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
    }

    filter {
        name = "state"
        values = ["available"]
    }
}

resource "aws_instance" "bastion" {
    ami = data.aws_ami.ubuntu.id
    instance_type = "t3.micro"
    subnet_id = aws_subnet.public_a.id
    vpc_security_group_ids = [aws_security_group.bastion_sg.id]
    associate_public_ip_address = true
    source_dest_check = false
    key_name = var.bastion_key_name

    tags = {
        Name = "musiql-bastion"
    }
}

resource "aws_route_table" "private" {
    vpc_id = aws_vpc.musiql_vpc.id

    route {
        cidr_block           = "0.0.0.0/0"
        network_interface_id = aws_instance.bastion.primary_network_interface_id
    }

    tags = {
        Name = "musiql-private-rt"
    }
}

resource "aws_route_table_association" "private_a" {
    subnet_id      = aws_subnet.private_a.id
    route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
    subnet_id      = aws_subnet.private_b.id
    route_table_id = aws_route_table.private.id
}

resource "aws_db_instance" "musiql_db" {
    identifier = "musiql-db"
    engine = "postgres"
    engine_version = "16"
    instance_class = "db.t3.micro"
    allocated_storage = 20

    db_name = "musiql"
    username = "musiql_admin"
    password = var.db_password

    db_subnet_group_name = aws_db_subnet_group.musiql_db_subnet_group.name
    vpc_security_group_ids = [aws_security_group.rds_sg.id]

    publicly_accessible = false
    skip_final_snapshot = true

    tags = {
        Name = "musiql-db"
    }
}

resource "aws_security_group" "lambda_sg" {
    name = "musiql-lambda-sg"
    description = "Security group for Lambda functions"
    vpc_id = aws_vpc.musiql_vpc.id

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "musiql-lambda-sg"
    }
}

resource "aws_secretsmanager_secret" "musiql_db_credentials" {
    name = "musiql/db-credentials"

    tags = {
        Name = "musiql-db-credentials"
    }
}

resource "aws_security_group" "secretsmanager_endpoint_sg" {
    name        = "musiql-secretsmanager-endpoint-sg"
    description = "Allow HTTPS from Lambda to Secrets Manager VPC endpoint"
    vpc_id      = aws_vpc.musiql_vpc.id

    ingress {
        description     = "HTTPS from Lambda"
        from_port       = 443
        to_port         = 443
        protocol        = "tcp"
        security_groups = [aws_security_group.lambda_sg.id]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "musiql-secretsmanager-endpoint-sg"
    }
}

resource "aws_vpc_endpoint" "secretsmanager" {
    vpc_id              = aws_vpc.musiql_vpc.id
    service_name        = "com.amazonaws.us-east-2.secretsmanager"
    vpc_endpoint_type   = "Interface"
    subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids  = [aws_security_group.secretsmanager_endpoint_sg.id]
    private_dns_enabled = true

    tags = {
        Name = "musiql-secretsmanager-endpoint"
    }
}

resource "aws_ecr_repository" "musiql_container_registry" {
    name = "musiql/container-registry"

    tags = {
        Name = "musiql-container-registry"
    }
}

resource "aws_iam_role" "lambda_role" {
    name = "musiql-lambda-role-a17jjid1"
    path = "/service-role/"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Action = "sts:AssumeRole"
            Effect = "Allow"
            Principal = {
                Service = "lambda.amazonaws.com"
            }
        }]
    })
}



resource "aws_lambda_function" "musiql_lambda" {
    function_name = "musiql-lambda"
    role = aws_iam_role.lambda_role.arn
    package_type = "Image"
    image_uri = "${aws_ecr_repository.musiql_container_registry.repository_url}:latest"

    memory_size = 512
    timeout = 900

    vpc_config {
        subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
        security_group_ids = [aws_security_group.lambda_sg.id]
    }

    environment {
        variables = {
            SECRET_ARN = aws_secretsmanager_secret.musiql_db_credentials.arn
            ENV = "production"
        }
    }

    tags = {
        Name = "musiql-lambda"
    }
}

resource "aws_lambda_function" "musiql_lambda_sb" {
    function_name = "musiql-lambda-dev"
    role = aws_iam_role.lambda_role.arn
    package_type = "Image"
    image_uri = "${aws_ecr_repository.musiql_container_registry.repository_url}:latest"

    memory_size = 512
    timeout = 900

    vpc_config {
        subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
        security_group_ids = [aws_security_group.lambda_sg.id]
    }

    environment {
        variables = {
            SECRET_ARN = aws_secretsmanager_secret.musiql_db_credentials.arn
            ENV = "dev"
        }
    }

    tags = {
        Name = "musiql-lambda-dev"
    }
}

resource "aws_apigatewayv2_api" "musiql_api" {
    name = "musiql"
    protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
    api_id = aws_apigatewayv2_api.musiql_api.id
    name = "$default"
    auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda" {
    api_id = aws_apigatewayv2_api.musiql_api.id
    integration_type = "AWS_PROXY"
    integration_uri = aws_lambda_function.musiql_lambda.invoke_arn
    payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
    api_id = aws_apigatewayv2_api.musiql_api.id
    route_key = "$default"
    target = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "apigw_prod" {
    statement_id  = "AllowAPIGatewayInvoke"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.musiql_lambda.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.musiql_api.execution_arn}/*/*"
}

# Dev API Gateway

resource "aws_apigatewayv2_api" "musiql_api_dev" {
    name = "musiql-dev"
    protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "dev_default" {
    api_id = aws_apigatewayv2_api.musiql_api_dev.id
    name = "$default"
    auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda_dev" {
    api_id = aws_apigatewayv2_api.musiql_api_dev.id
    integration_type = "AWS_PROXY"
    integration_uri = aws_lambda_function.musiql_lambda_sb.invoke_arn
    payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "dev_default" {
    api_id = aws_apigatewayv2_api.musiql_api_dev.id
    route_key = "$default"
    target = "integrations/${aws_apigatewayv2_integration.lambda_dev.id}"
}

resource "aws_lambda_permission" "apigw_dev" {
    statement_id  = "AllowAPIGatewayInvoke"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.musiql_lambda_sb.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.musiql_api_dev.execution_arn}/*/*"
}