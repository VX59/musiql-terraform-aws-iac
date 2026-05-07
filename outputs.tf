output "bucket_arn" {
    value = aws_s3_bucket.musiql_bucket.arn
}

output "queue_url" {
    value = aws_sqs_queue.musiql_uploads_queue.url
}