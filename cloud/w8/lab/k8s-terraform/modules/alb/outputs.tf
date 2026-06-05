output "alb_dns_name" {
  description = "DNS name của ALB"
  value       = aws_lb.main.dns_name
}