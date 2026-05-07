resource "aws_s3_bucket" "musiql_bucket" {
    bucket = "musiql-s3-bucket"
}

resource "aws_sqs_queue" "musiql_uploads_queue" {
    name = "RecordingServerQueue"
    max_message_size = 1048576
    visibility_timeout_seconds = 30
}