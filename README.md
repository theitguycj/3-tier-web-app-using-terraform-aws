# 3 Tier Web Application Architecture Using Terraform and AWS

![alt text](https://github.com/theitguycj/3-tier-web-app-using-terraform-aws/blob/master/3TierArch.png)

## Overview
This is a common cloud architecture: An internet-facing Application Load Balancer (ALB) forwards traffic to the web tier of EC2 instances. Those instances are running Nginx webservers that are configured to serve a React.js website and redirects API calls to the application tier’s internal-facing ALB. That internal ALB forwards that traffic to the Node.js application tier of EC2 instances. The application tier manipulates data in an Aurora MySQL multi-AZ database cluster and returns it to our web tier. Load balancing, health checks and autoscaling groups are created at each layer to maintain the availability of this architecture. Here is an example of this in the [AWS workshop](http://catalog.us-east-1.prod.workshops.aws/workshops/85cd2bb2-7f79-4e96-bdee-8078e469752a/en-US) and a YouTube [video](https://www.youtube.com/watch?v=amiIcyt-J2A).

The problem comes in with the time it takes to do this: AWS says this workshop can take around 3 hours and even the YouTube tutorial is over an hour to complete. This won't do in a corporate environment and you'll need to use some sort of automation or infrastructure as code (IaC) tool like HashiCorp's Terraform to manage this process to make it faster, easily repeatable, and less error prone. To make things easier, I'll have a single main.tf file that will go through all the AWS steps in sequence. I'll also be changing a few things from the AWS Workshop such as using GitHub instead of Amazon S3, using Parameter Store to store sensitive values upfront, and incorporating Route 53.

As with the AWS instructions, I'm going to assume you have foundational knowledge around VPC, EC2, RDS, ELB, and the AWS Console. I'll touch on a few Terraform basics but there are many great in-depth resources such as [Travis Media](https://www.youtube.com/watch?v=nvNqfgojocs), [freeCodeCamp](https://www.youtube.com/watch?v=iRaai1IBlB0), [Dreams of Code](https://www.youtube.com/watch?v=cGPyH-PO8vg), and the [Terraform docs](https://developer.hashicorp.com/terraform). Similar to my Serverless Web App project, I'm going to point out important things name out everything since we are following a workshop but I will point out important things as I go along.

# Step 0: Prereqs/Setup
- Create Terraform/CLI user in AWS Console
- Install Visual Studio Code and Terraform plugin
- Practice with [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/).
- Instead of using S3, I'll use GitHub to for hosting the sample code. This will have our code hosted in advance. Use the code from this git repo or clone it to your own. This has the proper values that we'll have Terraform edit.
- Add RDS (database) username and password into Parameter Store located in AWS Systems Manager. I have the values name "rds_username" and "rds_password" and stored as SecureStrings. Also add your IP address to Parameter Store to use in your security groups.
- Optionally retrieve your Route 53 zone if you'd like to use it instead of the external load balancer's DNS name.

# Step 1: Networking & Security
There aren't any problems to run into in this section if you follow the [Terraform AWS Registry docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs). Here the VPC, 6 subnets (2 public, 4 private), internet gateway, elastic IPs, NAT gateways, route tables, subnet associations, and security groups are created. With your internet-facing load balancer security group, reference your IP address you stored in Parameter Store. You'll also reference that IP in the web-tier and private instance tier security groups for testing purposes.

# Step 2: Database Deployment
Up to this point, it was fairly straight-forward. This step took me longer than I care to admit to get through. Here are a few roadblocks I was running into and suggestions:
- The Terraform docs are a great reference but it's not going to give you all the answers. Sometimes you have to build on the knowledge from previous steps; sometimes you have to try different things. I worked for HOURS a day using "aws_db_instance" docs and Google searches instead of what I really needed: "aws_rds_cluster" and "aws_rds_cluster_instance". I also had this issue with correctly implementing arguments like Multi-AZ, DB instance class, and encryption. What's a single page on the AWS Console may be multiple Terraform resources.
- Really read the error messages that Terraform will give you and see if you can figure out the issue. Beyond that, GOOGLE IT!
- If you need, create the step in the AWS Console to see what everything is suppose to look like then create your Terraform configuration. Compare the 2 to see what in your config is correct and what needs to be changed.
- You'll also need to reference the username and password that were placed in Parameter Store as the master username and master password.

# Step 3: App Tier Deployment

This one here... ... took even longer. Here's where being a solutions architect comes in. So, I wanted this project to be able to go from zero resources consumed to EVERYTHING set up properly with a terraform apply --auto-approve command, including customizing the EC2 instances and databases, with no user interaction. I used a user data file/script to run commands at the instance's start up. That helped me to learn what takes place when an instance starts, what users are automatically on there, how to install and edit packages, how to move through the file system, and how to edit files using the "sed" command. Also, using the user data file in Terraform allows that file to use values and variables. That's what allows for me to dynamically provide the RDS username, password, and writer endpoint address to that startup script.

# Step 4: Internal Load Balancing & Auto Scaling

I ran into a small hurdle when trying to create an AMI from the EC2 instance. You have to remember: Terraform creates all the resources it can simultaneously. That's the magic of it... and a downfall if you don't time it properly. When you create an EC2 instance and include a user data script, AWS and Terraform will mark the EC2 instance as ready to be used when the instance has booted, not when the user data script has been fully ran. So the AMI will start to be created before the customizations have a chance to take place. There needs to be some time between your instance completing and the AMI being created. Terraform doesn't have a way of creating a wait period so I had a few resources create one after another using the "depends_on =" argument to allow time for resources to complete. Here it's app tier instance deployment -> internal load balancer creation -> app tier AMI creation.

# Step 5: Web Tier Instance Deployment

This is very similar to the app tier deployment. Using a user data script, I can use Terraform to download, install, and configure the files needed for the EC2 instances that will be publicly accessible. The user data script also uses the sed command to change "INT-LOAD-BALANCER-DNS" to the internal load balancer's DNS name.

# Step 6: External Load Balancer & Auto Scaling

This is mostly a copy of Step 5. You'll need to change the values to use the web tier and public subnets. Again, use the "depends_on =" argument to give time for resources to complete: web tier instance deployment -> external load balancer creation -> web tier AMI creation.

# Step 7: Route 53

This isn't listed in the AWS Workshop but I wanted to make things a little cleaner. Since I already use a [hosted domain on AWS](https://theitguycj.com/using-amazon-route-53-for-dns/), I wanted Terraform to add a new record in Route 53 so that I can navigate to 3ta.aws.theitguycj.com to see my app working instead of the external load balancer's DNS name. I retrieved the zone id in Step 0 then asked for it in this step.

# Step 8: Deletion and Clean Up

To destroy all of the infrastructure that we've created, we'll run the terraform destroy --auto-approve command to stop incurring charges.
