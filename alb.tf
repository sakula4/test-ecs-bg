resource "null_resource" "dependency_getter" {
  triggers = {
    instance = join(",", var.dependencies)
  }
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

  http_listener_port_arns = {
    for listener in aws_alb_listener.http :
        listener.port => listener.arn
  }
#   https_listener_non_acm_port_arns = {
#     for listener in aws_alb_listener.https_non_acm_certs :
#     listener.port => listener.arn
#   }
#   https_listener_acm_port_arns = {
#     for listener in aws_alb_listener.https_acm_certs :
#     listener.port => listener.arn
#   }
}





# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN APPLICATION LOAD BALANCER
# ---------------------------------------------------------------------------------------------------------------------


resource "aws_alb" "alb" {
  name     = var.alb_name
  internal = false
  subnets  = data.aws_subnets.default.ids
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
  depends_on = [
    null_resource.dependency_getter
  ]
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
        arn    = module.blue_fargate_service.target_group_arns["alb"]
        weight = lookup(local.traffic_dist_map[var.traffic_distribution], "blue", 100)
      }

      target_group {
        arn    = module.green_fargate_service.target_group_arns["alb"]
        weight = lookup(local.traffic_dist_map[var.traffic_distribution], "green", 0)
      }

      stickiness {
        enabled  = false
        duration = 1
      }
    }
  }
}






# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE ALB LISTENER RULES ASSOCIATED WITH THIS ECS SERVICE
# When an HTTP request is received by the ALB, how will the ALB know to route that request to this particular ECS Service?
# The answer is that we define ALB Listener Rules (https://goo.gl/vQv8oQ) that can route a request to a specific "Target
# Group" that contains "Targets". Each Target is actually an ECS Task (which is really just a Docker container). An ECS Service
# is ultimately made up of zero or more ECS Tasks.
#
# For example purposes, we will define one path-based routing rule and one host-based routing rule.
# ---------------------------------------------------------------------------------------------------------------------

# EXAMPLE OF A HOST-BASED LISTENER RULE
# Host-based Listener Rules are used when you wish to have a single ALB handle requests for both foo.acme.com and
# bar.acme.com. Using a host-based routing rule, the ALB can route each inbound request to the desired Target Group.
resource "aws_alb_listener_rule" "blue_host_based_example" {
  # Get the Listener ARN associated with port 80 on the ALB
  # In other words, this ALB has a Listener that listens for incoming traffic on port 80. That Listener has a unique
  # Amazon Resource Name (ARN), which we must pass to this rule so it knows which ALB Listener to "attach" to. Fortunately,
  # Our ALB module outputs values like http_listener_arns, https_listener_non_acm_cert_arns, and https_listener_acm_cert_arns
  # so that we can easily look up the ARN by the port number.
  listener_arn = local.http_listener_port_arns["80"]

  priority = 95

  action {
    type             = "forward"
    target_group_arn = module.blue_fargate_service.target_group_arns["alb"]
  }

  condition {
    host_header {
      values = ["*.${var.route53_hosted_zone_name}"]
    }
  }
}

# EXAMPLE OF A PATH-BASED LISTENER RULE
# Path-based Listener Rules are used when you wish to route all requests received by the ALB that match a certain
# "path" pattern to a given ECS Service. This is useful if you have one service that should receive all requests sent
# to /api and another service that receives requests sent to /customers.
resource "aws_alb_listener_rule" "blue_path_based_example" {
  # Get the Listener ARN associated with port 5000 on the ALB
  # In other words, this ALB has a Listener that listens for incoming traffic on port 80. That Listener has a unique
  # Amazon Resource Name (ARN), which we must pass to this rule so it knows which ALB Listener to "attach" to. Fortunately,
  # Our ALB module outputs values like http_listener_arns, https_listener_non_acm_cert_arns, and https_listener_acm_cert_arns
  # so that we can easily look up the ARN by the port number.
  listener_arn = local.http_listener_port_arns["5000"]

  priority = 100

  action {
    type             = "forward"
    target_group_arn = module.blue_fargate_service.target_group_arns["alb"]
  }

  condition {
    path_pattern {
      values = ["/static/*"]
    }
  }
}

# EXAMPLE OF A LISTENER RULE THAT USES BOTH PATH-BASED AND HOST-BASED ROUTING CONDITIONS
# This Listener Rule will only route when both conditions are met.
resource "aws_alb_listener_rule" "blue_host_based_path_based_example" {
  # Get the Listener ARN associated with port 5000 on the ALB
  # In other words, this ALB has a Listener that listens for incoming traffic on port 80. That Listener has a unique
  # Amazon Resource Name (ARN), which we must pass to this rule so it knows which ALB Listener to "attach" to. Fortunately,
  # Our ALB module outputs values like http_listener_arns, https_listener_non_acm_cert_arns, and https_listener_acm_cert_arns
  # so that we can easily look up the ARN by the port number.
  listener_arn = local.http_listener_port_arns["5000"]

  priority = 105

  action {
    type             = "forward"
    target_group_arn = module.blue_fargate_service.target_group_arns["alb"]
  }

  condition {
    host_header {
      values = ["*.acme.com"]
    }
  }

  condition {
    path_pattern {
      values = ["/static/*"]
    }
  }
}


# ------------------------
# Green alb-listener-rules 
# ------------------------
resource "aws_alb_listener_rule" "green_host_based_example" {
  # Get the Listener ARN associated with port 80 on the ALB
  # In other words, this ALB has a Listener that listens for incoming traffic on port 80. That Listener has a unique
  # Amazon Resource Name (ARN), which we must pass to this rule so it knows which ALB Listener to "attach" to. Fortunately,
  # Our ALB module outputs values like http_listener_arns, https_listener_non_acm_cert_arns, and https_listener_acm_cert_arns
  # so that we can easily look up the ARN by the port number.
  listener_arn = local.http_listener_port_arns["80"]

  priority = 96

  action {
    type             = "forward"
    target_group_arn = module.green_fargate_service.target_group_arns["alb"]
  }

  condition {
    host_header {
      values = ["*.${var.route53_hosted_zone_name}"]
    }
  }
}

# EXAMPLE OF A PATH-BASED LISTENER RULE
# Path-based Listener Rules are used when you wish to route all requests received by the ALB that match a certain
# "path" pattern to a given ECS Service. This is useful if you have one service that should receive all requests sent
# to /api and another service that receives requests sent to /customers.
resource "aws_alb_listener_rule" "green_path_based_example" {
  # Get the Listener ARN associated with port 5000 on the ALB
  # In other words, this ALB has a Listener that listens for incoming traffic on port 80. That Listener has a unique
  # Amazon Resource Name (ARN), which we must pass to this rule so it knows which ALB Listener to "attach" to. Fortunately,
  # Our ALB module outputs values like http_listener_arns, https_listener_non_acm_cert_arns, and https_listener_acm_cert_arns
  # so that we can easily look up the ARN by the port number.
  listener_arn = local.http_listener_port_arns["5000"]

  priority = 101

  action {
    type             = "forward"
    target_group_arn = module.green_fargate_service.target_group_arns["alb"]
  }

  condition {
    path_pattern {
      values = ["/static/*"]
    }
  }
}

# EXAMPLE OF A LISTENER RULE THAT USES BOTH PATH-BASED AND HOST-BASED ROUTING CONDITIONS
# This Listener Rule will only route when both conditions are met.
resource "aws_alb_listener_rule" "green_host_based_path_based_example" {
  # Get the Listener ARN associated with port 5000 on the ALB
  # In other words, this ALB has a Listener that listens for incoming traffic on port 80. That Listener has a unique
  # Amazon Resource Name (ARN), which we must pass to this rule so it knows which ALB Listener to "attach" to. Fortunately,
  # Our ALB module outputs values like http_listener_arns, https_listener_non_acm_cert_arns, and https_listener_acm_cert_arns
  # so that we can easily look up the ARN by the port number.
  listener_arn = local.http_listener_port_arns["5000"]

  priority = 106

  action {
    type             = "forward"
    target_group_arn = module.green_fargate_service.target_group_arns["alb"]
  }

  condition {
    host_header {
      values = ["*.acme.com"]
    }
  }

  condition {
    path_pattern {
      values = ["/static/*"]
    }
  }
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

