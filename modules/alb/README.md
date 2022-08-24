# Application Load Balancer (ALB) Module

This Terraform Module creates an [Application Load Balancer](http://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html)
that you can use as a load balancer for any [ALB Target Group](http://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html).
In practice, a Target Group is usually an [ECS Service](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/Welcome.html)
or an [Auto Scaling Group](http://docs.aws.amazon.com/autoscaling/latest/userguide/WhatIsAutoScaling.html).

See the [Background](#background) section below for more information on the ALB.

## How do you use this module?

* See the [root README](/README.md) for instructions on using Terraform modules.
* See the [examples](/examples) folder for example usage.
* See [vars.tf](./vars.tf) for all the variables you can set on this module.

## ALB Terminology

Amazon has its own vocabulary for the ALB that can be confusing. Here's a helpful guide:

- **Listener:** Represents a port open on the ALB that receives incoming traffic (e.g., port 80 for HTTP, 443 for
  HTTPs).

- **Target Group:** Represents one or more servers that are listening for requests. You can configure what port(s)
  those servers listen on and how to perform health checks on the servers. 

- **Listener Rules:** Represents a mapping between Listeners and Target Groups. For each of your Listeners, you can
  specify which paths and/or domain names should be routed to which Target Groups. For example, you could configure
  path `/foo` to go to the Target Group `foo` and `/bar` to go to `bar`; or, you could configure `foo.my-domain.com` to
  go to `foo` and `bar.my-domain.com` to go to `bar`; or any combination/permutation of these rules.

## Background

### What's the difference between an ALB and ELB?

The ELB, now known as the [Classic Load Balancer](http://docs.aws.amazon.com/elasticloadbalancing/latest/classic/introduction.html),
is a [Layer 4](https://en.wikipedia.org/wiki/Transport_layer) load balancer, which means that the ELB will accept both 
HTTP traffic *and* TCP traffic. By asking the ELB to simply forward TCP traffic, Amazon users gained the benefit of a
high-availability load balancer with the flexibility of handling any kind of TCP traffic they wanted on their backend 
instances.

But over time, it became clear that many customers were running HTTP microservices that needed more "opinionated" functionality
like built-in support for WebSockets, built-in support for HTTP/2, and routing to different backend services depending 
on the particular URL requested in the HTTP request. Because these requests are all HTTP-specific, the "flexible" Layer 4
ELB could not be updated to handle these use cases.

In addition, when Amazon released the EC2 Container Service for easily running a Docker cluster, they needed some way 
to allow a load balancer to route requests to containers that just launched somewhere in the cluster. The ELB was originally
designed in a pre-container world and was able to route only to a _single_ port across many different EC2 Instances.

This imposed an awkward restriction on the ECS Cluster where you had to run each ECS Task (Docker container) so that it
listened on the same host port. This, in turn, meant you couldn't run two instances of the same Docker container on the
same host, which was one of the main benefits of Docker in the first place.

The ALB was meant to solve both of these problems: 

1. Offer HTTP-specific functionality (known as "Layer 7" functionality)
2. Allow Docker containers to launch on a dynamic port

#### ALB Functionality

The ALB gives us the following HTTP-specific functionality compared to the ELB:

- Route requests via HTTP or HTTPS
- Native support for WebSockets
- Native support for HTTP/2
- Path-based routing
- Hostname-based routing
- Ability to route to a [Target](http://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-register-targets.html), 
  which incorporates both an endpoint and a port and therefore allows different instances of an ECS Service to receive
  traffic on different ports.
- Better metrics
- Support for sticky sessions using load-balancer-generated cookies

For a visual explanation of the ALB's features, check out [A Talk on the New AWS Application Load Balancer, Updates to 
ECS, and Kinesis Analytics](https://blog.gruntwork.io/a-talk-on-the-new-aws-application-load-balancer-updates-to-ecs-and-kinesis-analytics-abb599cb3cb8#.qww1to10q). 

#### ELB Functionality

The Classic Load Balancer, or ELB, gives us the following unique functionality compared to the ALB:

- Route requests via HTTP, HTTPS or TCP
- Support for sticky sessions using application-generated cookies

### When should I use an ALB vs. ELB?

Based on the above analysis, you should generally prefer the ALB when selecting a load balancer for an HTTP-based service.
There are, of course, still times when the ELB makes sense:
 
 - If your service listens on a non-HTTP protocol, such as ZeroMQ.
 - If you wish to terminate a TLS connection at your service, instead of at the load balancer, only the ELB will support 
   this. That is, an ALB will accept TLS connections, but it will then open a _second_ HTTP or HTTPS connection to your 
   backend service. If you want end-to-end encryption, only the ELB can forward the TCP request directly to your backend
   service so that the backend service terminates the TLS connection.
 - If you need the power of Nginx, or HAProxy, but don't want to bother setting these up as a High Availability cluster.

Finally, the ALB uses a different pricing model than the ELB. Here's an excerpt from the [Blog Post that introduced the 
ALB](https://aws.amazon.com/blogs/aws/new-aws-application-load-balancer/):

> When you use an Application Load Balancer, you will be billed by the hour and for the use of Load Balancer Capacity Units, 
  also known as LCU’s. An LCU measures the number of new connections per second, the number of active connections, and 
  data transfer. We measure on all three dimensions, but bill based on the highest one. One LCU is enough to support either:
>  - 25 connections/second with a 2 KB certificate, 3,000 active connections, and 2.22 Mbps of data transfer or
>  - 5 connections/second with a 4 KB certificate, 3,000 active connections, and 2.22 Mbps of data transfer.

> Billing for LCU usage is fractional, and is charged at $0.008 per LCU per hour. Based on our calculations, we believe 
  that virtually all of our customers can obtain a net reduction in their load balancer costs by switching from a Classic 
  Load Balancer to an Application Load Balancer.

You may note that if you have 1,000,000 idle WebSocket connections (an "active connection"), this would cost ALB users 
$1,920/month! Whereas with the original ELB, your costs will not scale with the number of idle WebSocket connections 
(credit to [this Hacker News thread](https://news.ycombinator.com/item?id=12269453) for the observation).

Given all the benefits of the ALB, even if you plan to get to massive scale eventually, you may as well start with the 
ALB. You can always re-assess at any time.

## Using the ALB with ECS

### When should I use this module with Amazon ECS?

With the ELB, now known as a [Classic Load Balancer](http://docs.aws.amazon.com/elasticloadbalancing/latest/classic/introduction.html),
each ECS Service was fronted by a unique ELB. As a result, each ECS Service module eventually created its own ELB. This 
gave us good isolation and made it easy to give each ECS Service a unique DNS name on the same port (e.g. api.acme.com and
stats.acme.com, both on port 443). But it also led to low utilization among all the ELBs, little resource sharing, and 
consequently higher costs.
 
With the ALB, a single ALB is shared among multiple ECS Services. For that reason, after you've created an ALB using this
module, you may wish to create an ECS Cluster using the [ecs-cluster](
https://github.com/gruntwork-io/terraform-aws-ecs/tree/master/modules/ecs-cluster) module, where you'll pass in the Security 
Group ID of the newly created ALB to permit the ALB to forward traffic to the ECS Cluster. 
 
With an ECS Cluster and ALB in place, you can now use the [ecs-service-with-alb]
(https://github.com/gruntwork-io/terraform-aws-ecs/tree/master/modules/ecs-service-with-alb) module to create a new ECS Service 
that contains an ALB Target Group you can configure to receive traffic from an ALB. To do that, you need to add one
or more [aws_alb_listener_rule](https://www.terraform.io/docs/providers/aws/r/alb_listener_rule.html) resources to 
map which of the ALB listeners should send their traffic to the ECS service's Target Group.
 
### How should I use the ALB with multiple microservices?

To use the ALB with multiple services, you each service should create 
[aws_alb_listener_rule](https://www.terraform.io/docs/providers/aws/r/alb_listener_rule.html) resources to specify 
which paths or domain names should be routed to that service. For working sample code, check out the 
[docker-service-with-alb example](https://github.com/gruntwork-io/terraform-aws-ecs/tree/master/examples/docker-service-with-alb).

## Gotcha's

### Make sure your Listeners handle all possible request paths

An [ALB Listener](http://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html) 
represents an open port on your ALB, waiting to receive requests and route them to a [Target 
Group](http://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html). 

Suppose you want to have this ALB Listener route requests for `/foo` to ServiceFoo and requests for `/bar` to ServiceBar. 
You'd accomplish this creating two [ALB Listener 
Rules](http://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-update-rules.html) as follows:

  - Route `/foo` traffic to Target Group ServiceFoo
  - Route `/bar` traffic to Target Group ServiceBar

So far so good. But what if the Listener receives a request for `/hello`? Since no Listener Rule handles that path, the 
ALB will handle it with its `default_action`. The `default_action` in this module is to return a fixed response, which 
by default is a blank 404 page.

There are two ways for you to override this behavior:

* You can override the default fixed response via the `default_action_content_type`, `default_action_body`, and 
  `default_action_status_code` parameters.
* You can add an ALB Listener Rule that catches ALL requests (i.e., `*`) and have that rule forward to a custom Target
  Group so your own apps can respond in any way you wish.