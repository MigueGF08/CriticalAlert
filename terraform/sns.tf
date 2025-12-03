resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-physician-alerts"
}

resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.email_subscription
}

resource "aws_sns_topic_subscription" "sms_sub_1" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "sms"
  endpoint  = var.sms_subscription_1
}

resource "aws_sns_topic_subscription" "sms_sub_2" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "sms"
  endpoint  = var.sms_subscription_2
}
