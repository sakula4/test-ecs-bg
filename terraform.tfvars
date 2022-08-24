aws_region = "us-east-1"
ecs_cluster_name = "ecs-test-eastus-1"

ecs_cluster_instance_ami = "ami-040d909ea4e56f8f3"
ecs_cluster_instance_keypair_name = "test-ecs-alb"
ecs_cluster_vpc_subnet_ids = ["subnet-b91c09e5","subnet-b8838adf","subnet-d49456da"]
vpc_id = "vpc-9cdaffe6"

vpc_subnet_ids = ["subnet-3235221c","subnet-82a57dcf","subnet-cd7a26f3"]

alb_name = "ecs-fargate-bg-alb"
is_internal_alb = false
ssl_policy = "ELBSecurityPolicy-TLS-1-1-2017-01"
enable_green_env = true
traffic_distribution = "split"