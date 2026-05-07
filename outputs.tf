output "bucket_arn" {
    value = aws_s3_bucket.musiql_bucket.arn
}

output "vpc_id" {
    value = aws_vpc.musiql_vpc.id
}

output "private_subnet_ids" {
    value = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

output "db_endpoint" {
    value = aws_db_instance.musiql_db.endpoint
}

output "db_credentials_secret_arn" {
    value = aws_secretsmanager_secret.musiql_db_credentials.arn
}

output "api_endpoint" {
    value = aws_apigatewayv2_api.musiql_api.api_endpoint
}