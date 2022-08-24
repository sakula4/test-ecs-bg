# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CREATE AN APPLICATION LOAD BALANCER (ALB)
# This template creates an ALB, the necessary security groups, and sets up the desired ALB Listeners. A single ALB is
# expected to serve as the load balancer for potentially multiple ECS Services and Auto Scaling Groups.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

terraform {
  # This module is now only being tested with Terraform 0.14.x. However, to make upgrading easier, we are setting
  # 0.12.26 as the minimum version, as that version added support for required_providers with source URLs, making it
  # forwards compatible with 0.14.x code.
  required_version = ">= 0.12.26"
}

locals {
  traffic_dist_map = {
    blue = {
      blue  = 100
      green = 0
    }
    blue-90 = {
      blue  = 90
      green = 10
    }
    split = {
      blue  = 50
      green = 50
    }
    green-90 = {
      blue  = 10
      green = 90
    }
    green = {
      blue  = 0
      green = 100
    }
  }
}




# ---------------------------------------------------------------------------------------------------------------------
# SET MODULE DEPENDENCY RESOURCE
# This works around a terraform limitation where we can not specify module dependencies natively.
# See https://github.com/hashicorp/terraform/issues/1178 for more discussion.
# By resolving and computing the dependencies list, we are able to make all the resources in this module depend on the
# resources backing the values in the dependencies list.
# ---------------------------------------------------------------------------------------------------------------------

resource "null_resource" "dependency_getter" {
  triggers = {
    instance = join(",", var.dependencies)
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN APPLICATION LOAD BALANCER
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_alb" "alb" {
  name     = var.alb_name
  internal = var.is_internal_alb
  subnets  = var.vpc_subnet_ids
  security_groups = concat(
    [aws_security_group.alb.id],
    var.additional_security_group_ids,
  )

  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.enable_deletion_protection
  drop_invalid_header_fields = var.drop_invalid_header_fields

  tags = var.custom_tags

  dynamic "access_logs" {
    # The contents of the list is irrelevant. The only important thing is whether or not to create this block.
    for_each = var.enable_alb_access_logs ? ["use_access_logs"] : []
    content {
      bucket  = var.alb_access_logs_s3_bucket_name
      prefix  = var.alb_name
      enabled = true
    }
  }

  depends_on = [null_resource.dependency_getter]
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ALB TARGET GROUP & LISTENER RULE
# - To understand the ALB concepts of a Listener, Listener Rule, and Target Group, visit https://goo.gl/jGPQPE.
# - Because many ECS Services may potentially share a single Listener, we must define a Listener at the ALB Level, not
#   at the ECS Service level. We create one ALB Listener for each given port.
# ---------------------------------------------------------------------------------------------------------------------

# Create one HTTP Listener for each given HTTP port.
resource "aws_alb_listener" "http" {
  count = length(var.http_listener_ports)

  load_balancer_arn = aws_alb.alb.arn
  port              = element(var.http_listener_ports, count.index)
  protocol          = "HTTP"

  default_action {
    # type = "fixed-response"

    # fixed_response {
    #   content_type = var.default_action_content_type
    #   message_body = var.default_action_body
    #   status_code  = var.default_action_status_code
    # }

    type = "forward"
    # target_group_arn = aws_lb_target_group.blue.arn
    forward {
      target_group {
        arn    = var.blue_target_group_arn #aws_lb_target_group.blue.arn
        weight = lookup(local.traffic_dist_map[var.traffic_distribution], "blue", 100)
      }

      target_group {
        arn    = var.green_target_group_arn #aws_lb_target_group.green.arn
        weight = lookup(local.traffic_dist_map[var.traffic_distribution], "green", 0)
      }

      stickiness {
        enabled  = false
        duration = 1
      }
    }
  }

  depends_on = [null_resource.dependency_getter]
}

# Create one HTTPS Listener for each given HTTPS port and TLS cert ARN passed in by the user. Note that the user may
# also pass in TLS certs issued by ACM, which are handled in the listener below.
resource "aws_alb_listener" "https_non_acm_certs" {
  count = var.https_listener_ports_and_ssl_certs_num

  load_balancer_arn = aws_alb.alb.arn
  port              = var.https_listener_ports_and_ssl_certs[count.index]["port"]
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.https_listener_ports_and_ssl_certs[count.index]["tls_arn"]

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = var.default_action_content_type
      message_body = var.default_action_body
      status_code  = var.default_action_status_code
    }
  }

  depends_on = [null_resource.dependency_getter]
}

# Create one HTTPS Listener for each given HTTPS port and TLS cert issued by ACM. Note that the user may also pass
# manually pass in TLS cert ARNs, which are handled by the listener above.
resource "aws_alb_listener" "https_acm_certs" {
  count = var.https_listener_ports_and_acm_ssl_certs_num

  load_balancer_arn = aws_alb.alb.arn
  port              = var.https_listener_ports_and_acm_ssl_certs[count.index]["port"]
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = element(data.aws_acm_certificate.certs.*.arn, count.index)

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = var.default_action_content_type
      message_body = var.default_action_body
      status_code  = var.default_action_status_code
    }
  }

  depends_on = [null_resource.dependency_getter]
}

# Look up SSL certs issued by ACM
data "aws_acm_certificate" "certs" {
  count       = var.https_listener_ports_and_acm_ssl_certs_num
  domain      = var.https_listener_ports_and_acm_ssl_certs[count.index]["tls_domain_name"]
  statuses    = var.acm_cert_statuses
  types       = var.acm_cert_types
  most_recent = true
  depends_on  = [null_resource.dependency_getter]
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ALB'S SECURITY GROUP
# ---------------------------------------------------------------------------------------------------------------------

# Create a Security Group for the ALB itself.
resource "aws_security_group" "alb" {
  name        = "${var.alb_name}-alb"
  description = "For the ${var.alb_name}-alb ALB."
  vpc_id      = var.vpc_id
  tags        = var.custom_tags
  depends_on  = [null_resource.dependency_getter]
}

# Create one inbound security group rule for each HTTP Listener Port that allows access from the CIDR blocks in var.allow_inbound_from_cidr_blocks.
resource "aws_security_group_rule" "http_listeners" {
  count = length(var.http_listener_ports) * signum(length(var.allow_inbound_from_cidr_blocks))

  type      = "ingress"
  from_port = var.http_listener_ports[count.index]
  to_port   = var.http_listener_ports[count.index]
  protocol  = "tcp"

  cidr_blocks       = var.allow_inbound_from_cidr_blocks
  security_group_id = aws_security_group.alb.id
  depends_on        = [null_resource.dependency_getter]
}

# Create one inbound security group rule for each HTTP Listener Port that allows access from each security group in var.allow_inbound_from_security_group_ids.
resource "aws_security_group_rule" "http_listeners_for_security_groups" {
  count = length(var.http_listener_ports) * var.allow_inbound_from_security_group_ids_num

  type      = "ingress"
  from_port = var.http_listener_ports[floor(count.index / var.allow_inbound_from_security_group_ids_num)]
  to_port   = var.http_listener_ports[floor(count.index / var.allow_inbound_from_security_group_ids_num)]
  protocol  = "tcp"

  source_security_group_id = var.allow_inbound_from_security_group_ids[count.index % var.allow_inbound_from_security_group_ids_num]
  security_group_id        = aws_security_group.alb.id
  depends_on               = [null_resource.dependency_getter]
}

# Create one inbound security group rule for each HTTPS Listener Port that allows access from the CIDR blocks in var.allow_inbound_from_cidr_blocks.
resource "aws_security_group_rule" "https_listeners_non_acm_certs" {
  count = var.https_listener_ports_and_ssl_certs_num * signum(length(var.allow_inbound_from_cidr_blocks))

  type      = "ingress"
  from_port = var.https_listener_ports_and_ssl_certs[count.index]["port"]
  to_port   = var.https_listener_ports_and_ssl_certs[count.index]["port"]
  protocol  = "tcp"

  cidr_blocks       = var.allow_inbound_from_cidr_blocks
  security_group_id = aws_security_group.alb.id

  depends_on = [null_resource.dependency_getter]
}

# Create one inbound security group rule for each HTTPS Listener Port that allows access from each security group in var.allow_inbound_from_security_group_ids.
resource "aws_security_group_rule" "https_listeners_non_acm_certs_for_security_groups" {
  count = var.https_listener_ports_and_ssl_certs_num * var.allow_inbound_from_security_group_ids_num

  type      = "ingress"
  from_port = var.https_listener_ports_and_ssl_certs[floor(count.index / var.allow_inbound_from_security_group_ids_num)]["port"]
  to_port   = var.https_listener_ports_and_ssl_certs[floor(count.index / var.allow_inbound_from_security_group_ids_num)]["port"]
  protocol  = "tcp"

  source_security_group_id = var.allow_inbound_from_security_group_ids[count.index % var.allow_inbound_from_security_group_ids_num]
  security_group_id        = aws_security_group.alb.id

  depends_on = [null_resource.dependency_getter]
}

# Create one inbound security group rule for each HTTPS Listener Port for ACM certs that allows access from the CIDR blocks in var.allow_inbound_from_cidr_blocks.
resource "aws_security_group_rule" "https_listeners_acm_certs" {
  count = var.https_listener_ports_and_acm_ssl_certs_num * signum(length(var.allow_inbound_from_cidr_blocks))

  type      = "ingress"
  from_port = var.https_listener_ports_and_acm_ssl_certs[count.index]["port"]
  to_port   = var.https_listener_ports_and_acm_ssl_certs[count.index]["port"]
  protocol  = "tcp"

  cidr_blocks       = var.allow_inbound_from_cidr_blocks
  security_group_id = aws_security_group.alb.id
  depends_on        = [null_resource.dependency_getter]
}

# Create one inbound security group rule for each HTTPS Listener Port for ACM certs that allows access from each security group in var.allow_inbound_from_security_group_ids.
resource "aws_security_group_rule" "https_listeners_acm_certs_for_security_groups" {
  count = var.https_listener_ports_and_acm_ssl_certs_num * var.allow_inbound_from_security_group_ids_num

  type      = "ingress"
  from_port = var.https_listener_ports_and_acm_ssl_certs[floor(count.index / var.allow_inbound_from_security_group_ids_num)]["port"]
  to_port   = var.https_listener_ports_and_acm_ssl_certs[floor(count.index / var.allow_inbound_from_security_group_ids_num)]["port"]
  protocol  = "tcp"

  source_security_group_id = var.allow_inbound_from_security_group_ids[count.index % var.allow_inbound_from_security_group_ids_num]
  security_group_id        = aws_security_group.alb.id
  depends_on               = [null_resource.dependency_getter]
}

# Allow all outbound traffic
resource "aws_security_group_rule" "allow_all_outbound" {
  count = var.allow_all_outbound ? 1 : 0

  type      = "egress"
  from_port = 0
  to_port   = 0
  protocol  = "-1"

  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  depends_on        = [null_resource.dependency_getter]
}
