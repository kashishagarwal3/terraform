// credentials

provider "aws" {
  region                  = "ap-south-1"
  profile                 = "kashish"
}


//creating a public-private key pair

resource "tls_private_key" "my_key_pair"{
    algorithm = "RSA"

}

//saving the created key pair in our local system

resource "local_file" "my_local_key"{
    content = tls_private_key.my_key_pair.private_key_pem
    filename = "key_task1.pem"
    file_permission = 0400

    provisioner "local-exec" {
        when = destroy
        command = "del  key_task1.pem"
    
    }
    depends_on = [
      tls_private_key.my_key_pair,
  ]

}

// deploying key to aws

resource "aws_key_pair" "key_deploy"{
    key_name = "key_task1"
    public_key = tls_private_key.my_key_pair.public_key_openssh

    depends_on = [
      tls_private_key.my_key_pair,
  ]
}


// creating security groups to allow port 22 and 80

resource "aws_security_group" "mysg"{
    name = "mysg_task1"
    description = "Allow port 22 and 80"

    ingress{
        description = "inbound web traffic"
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress{
        description = "inbound ssh"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress{
        description = "all outbound traffic"
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "My_SG_Task1"
    }
}


// launching AWS instance

resource "aws_instance" "myos" {
  ami           = "ami-052c08d70def0ac62"
  instance_type = "t2.micro"
  availability_zone = "ap-south-1a"
  key_name = "key_task1"
  security_groups = ["${aws_security_group.mysg.name}"]

  tags = {
    Name = "OS_Task1"
  }

  depends_on = [
      tls_private_key.my_key_pair,
      aws_security_group.mysg,
  ]
}

// EBS volume creation

resource "aws_ebs_volume" "myebs" {
  availability_zone = "${aws_instance.myos.availability_zone}"
  size              = 1

  tags = {
    Name = "mypd"
  }

  depends_on = [
      aws_instance.myos,
  ]
}

//EBS volume attachment

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.myebs.id
  instance_id = aws_instance.myos.id
  force_detach = true

  depends_on = [
      aws_ebs_volume.myebs,
  ]
}

resource "null_resource" "remote1"  {

depends_on = [
    aws_volume_attachment.ebs_att, 
 ]
  

  //conecting to the instance
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.my_key_pair.private_key_pem
    host     = aws_instance.myos.public_ip
  }


  //executing commands in instance

  provisioner "remote-exec" {
    inline = [
        "sudo yum install httpd -y",
        "sudo systemctl start httpd",
        "sudo systemctl enable httpd",
        "sudo yum install git -y",
        "sudo setenforce 0",
        "sudo mkfs.ext4  /dev/xvdh",
        "sudo mount  /dev/xvdh  /var/www/html",
        "sudo rm -rf /var/www/html/*",
        "sudo git clone https://github.com/kashishagarwal3/mymulticloud.git  /var/www/html"
    ]
  }
}

//creating S3 Bucket

resource "aws_s3_bucket" "mys3" {
  bucket = "kashish-task1"
  acl    = "public-read"
  force_destroy = true

  tags = {
    Name        = "Bucket using terraform"
  }


//copying the image from github to local system

  provisioner "local-exec" {
        command     = "git clone https://github.com/kashishagarwal3/mymulticloud.git server_img"
    }

    provisioner "local-exec" {
        when        =   destroy
        command     =   "rmdir /s /q server_img"
    }
    depends_on = [
      aws_volume_attachment.ebs_att
    ]
}

//uploading the image to bucket
resource "aws_s3_bucket_object" "s3_upload" {

    depends_on = [
    aws_s3_bucket.mys3,
  ]
  
  bucket  = aws_s3_bucket.mys3.bucket
  key     = "mypic.jpeg"
  source  = "server_img/mypic.jpeg"
  acl     = "public-read"
}

locals {
  s3_origin_id = "S3-${aws_s3_bucket.mys3.bucket}"
}


//creating CloudFront distribution with an S3 origin

resource "aws_cloudfront_distribution" "s3_distribution" {

  depends_on = [
    aws_s3_bucket_object.s3_upload
  ]


  origin {
    domain_name = aws_s3_bucket.mys3.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.my_key_pair.private_key_pem
    host     = aws_instance.myos.public_ip
  }


//getting image from CloudFront and displaying on the website

  provisioner "remote-exec" {
        
        inline = [
          "sudo su << EOF",
          "echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.s3_upload.key}'>\" >> /var/www/html/index.html",
          "EOF"
        ]
    }
}


//launching chrome to display website

resource "null_resource" "local1"  {

depends_on = [
    null_resource.remote1,aws_cloudfront_distribution.s3_distribution
  ]

	provisioner "local-exec" {
	    command = "start chrome  ${aws_instance.myos.public_ip}"
  	     }
}


