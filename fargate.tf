
# ---------------------------------------------------------------------------------------------------------------------
# CREATE A FARGATE SERVICE TO RUN MY ECS TASK
# ---------------------------------------------------------------------------------------------------------------------

module "blue_fargate_service" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-ecs.git//modules/ecs-service?ref=v1.0.8"
  source = "git::git@github.com:gruntwork-io/terraform-aws-ecs.git//modules/ecs-service?ref=v0.34.0"

  service_name    = "blue-${var.service_name}"
  ecs_cluster_arn = aws_ecs_cluster.fargate_cluster.arn

  desired_number_of_tasks        = var.desired_number_of_tasks
  ecs_task_container_definitions = local.blue_container_definition
  launch_type                    = "FARGATE"

  # Network information is necessary for Fargate, as it required VPC type
  ecs_task_definition_network_mode = "awsvpc"
  ecs_service_network_configuration = {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_task_security_group.id]
    assign_public_ip = true
  }

  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html#fargate-tasks-size.
  # Specify memory in MB
  task_cpu    = 256
  task_memory = 512

  # Configure ALB
  elb_target_groups = {
    alb = {
      name                  = "blue-${var.service_name}"
      container_name        = var.container_name
      container_port        = var.http_port
      protocol              = "HTTP"
      health_check_protocol = "HTTP"
    }
  }
  elb_target_group_vpc_id = data.aws_vpc.default.id
  elb_slow_start          = 30

  # Give the container 30 seconds to boot before having the ALB start checking health
  health_check_grace_period_seconds = 30

  enable_ecs_deployment_check      = var.enable_ecs_deployment_check
  deployment_check_timeout_seconds = var.deployment_check_timeout_seconds

  deployment_circuit_breaker = {
    enable   = var.deployment_circuit_breaker_enabled
    rollback = var.deployment_circuit_breaker_rollback
  }

  # Make sure all the ECS cluster and ALB resources are deployed before deploying any ECS service resources. This is
  # also necessary to avoid issues on 'destroy'.
  depends_on = [aws_ecs_cluster.fargate_cluster, aws_alb.alb]

  # Explicit dependency to aws_alb_listener_rules to make sure listeners are created before deploying any ECS services
  # and avoid any race condition.
  listener_rule_ids = [
    aws_alb_listener_rule.blue_host_based_example.id,
    aws_alb_listener_rule.blue_host_based_path_based_example.id,
    aws_alb_listener_rule.blue_path_based_example.id
  ]
}


module "green_fargate_service" {

#   count  = var.enable_green_env ? 1 : 0

  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-ecs.git//modules/ecs-service?ref=v1.0.8"
  source = "git::git@github.com:gruntwork-io/terraform-aws-ecs.git//modules/ecs-service?ref=v0.34.0"

  service_name    = "green-${var.service_name}"
  ecs_cluster_arn = aws_ecs_cluster.fargate_cluster.arn

  desired_number_of_tasks        = var.desired_number_of_tasks
  ecs_task_container_definitions = local.green_container_definition
  launch_type                    = "FARGATE"

  # Network information is necessary for Fargate, as it required VPC type
  ecs_task_definition_network_mode = "awsvpc"
  ecs_service_network_configuration = {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_task_security_group.id]
    assign_public_ip = true
  }

  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html#fargate-tasks-size.
  # Specify memory in MB
  task_cpu    = 256
  task_memory = 512

  # Configure ALB
  elb_target_groups = {
    alb = {
      name                  = "green-${var.service_name}"
      container_name        = var.container_name
      container_port        = var.http_port
      protocol              = "HTTP"
      health_check_protocol = "HTTP"
    }
  }
  elb_target_group_vpc_id = data.aws_vpc.default.id
  elb_slow_start          = 30

  # Give the container 30 seconds to boot before having the ALB start checking health
  health_check_grace_period_seconds = 30

  enable_ecs_deployment_check      = var.enable_ecs_deployment_check
  deployment_check_timeout_seconds = var.deployment_check_timeout_seconds

  deployment_circuit_breaker = {
    enable   = var.deployment_circuit_breaker_enabled
    rollback = var.deployment_circuit_breaker_rollback
  }

  # Make sure all the ECS cluster and ALB resources are deployed before deploying any ECS service resources. This is
  # also necessary to avoid issues on 'destroy'.
  depends_on = [aws_ecs_cluster.fargate_cluster, aws_alb.alb]

  # Explicit dependency to aws_alb_listener_rules to make sure listeners are created before deploying any ECS services
  # and avoid any race condition.
  listener_rule_ids = [
    aws_alb_listener_rule.green_host_based_example.id,
    aws_alb_listener_rule.green_host_based_path_based_example.id,
    aws_alb_listener_rule.green_path_based_example.id
  ]
}

# This local defines the Docker containers we want to run in our ECS Task
locals {
  blue_container_definition = templatefile(
    "${path.module}/containers/container-definition.json",
    {
      container_name = var.container_name
      # For this example, we run the Docker container defined under examples/example-docker-image.
      image          = "gruntwork/docker-test-webapp"
      version        = "latest"
      server_text    = "blue"
      aws_region     = var.aws_region
      s3_test_file   = "s3://${aws_s3_bucket.s3_test_bucket.id}/${var.s3_test_file_name}"
      cpu            = 256
      memory         = 512
      awslogs_group  = var.service_name
      awslogs_region = var.aws_region
      awslogs_prefix = var.service_name
      # The container and host must listen on the same port for Fargate
      container_http_port = var.http_port
      command             = "[${join(",", formatlist("\"%s\"", var.container_command))}]"
      boot_delay_seconds  = var.container_boot_delay_seconds
    },
  )

  green_container_definition = templatefile(
    "${path.module}/containers/container-definition.json",
    {
      container_name = var.container_name
      # For this example, we run the Docker container defined under examples/example-docker-image.
      image          = "gruntwork/docker-test-webapp"
      version        = "latest"
      server_text    = "green"
      aws_region     = var.aws_region
      s3_test_file   = "s3://${aws_s3_bucket.s3_test_bucket.id}/${var.s3_test_file_name}"
      cpu            = 256
      memory         = 512
      awslogs_group  = var.service_name
      awslogs_region = var.aws_region
      awslogs_prefix = var.service_name
      # The container and host must listen on the same port for Fargate
      container_http_port = var.http_port
      command             = "[${join(",", formatlist("\"%s\"", var.container_command))}]"
      boot_delay_seconds  = var.container_boot_delay_seconds
    },
  )
  
}
