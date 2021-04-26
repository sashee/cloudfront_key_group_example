# Example code to show how to use CloudFront's trusted_key_groups argument

The Trusted Key Group allows using CloudFront signed URLs without the root user or account-level changes. It adds a new resource, the ```aws_cloudfront_key_group```
and you can add keys under that. Then the signing process can use a key that is associated with the distribution.

## Prerequisities

* npm
* terraform

## Init

* ```terraform init```

## Deploy

* ```terraform apply```

## Usage

Go to the URL that Terraform prints when you deploy the stack. It is an API Gateway endpoint that calls a Lambda function. The function signs a URL and redirects
to is. You'll see an object in an S3 bucket that is only accessible using signed URLs.

## Cleanup

* ```terraform destroy```
