variable "aws_region" {
    default = "us-east-2"
}

variable "db_password" {
    description = "RDS password"
    type = string
    sensitive = true
}

variable "recording_server_ip" {
    description = "Public IP of the recording server in CIDR notation"
    type = string
    sensitive = true
}