# hiera_tfstate

Hiera backend for reading data from Terraform state files. Currently Terraform
0.13.x state files are supported.

**WARNING**: right now this Hiera backend is still highly experimental. Use it
at your own risk.

# How does it work?

Terraform state files are JSON so they're technically compatible with the
default JSON Hiera backend. However, all the resources in the state file are in
one huge array and referring to them would require using the resource index.
As the index can change raw state files are rather useless for Hiera.

This Hiera backend takes the Terraform state file and produces a flattened list
of data and resource attribute paths and their values. All values are prefixed
with "tfstate". Some examples:

    tfstate::aws_acm_certificate::my-alb::arn: some-arn
    tfstate::aws_acm_certificate::my-alb::arn_suffix: some-arn-suffix
    tfstate::aws_acm_certificate::my-alb::arn_suffix: some-dns-name
    tfstate::module::my_instance::aws_instance::ec2_instance::0::ami: some_ami_id
    tfstate::module::my_instance::aws_instance::ec2_instance::0::arn: some-arn
    tfstate::module::my_instance::aws_instance::ec2_instance::0::associate_public_ip_address: false

If and only if all resources/data sources are stored inside a module you can
use *no_root_module: true* in the options hash to remove the root module away
from the paths.

# Setup

Setup should be straightforward:

* Add this Puppet module to your Puppetfile (or otherwise install it)
* Configure this backend in hiera.yaml (see below)
* Install Ruby dependencies, if any (see below)
* Backend-specific configuration, if any (see below)

# Supported state file backends

## file

The *file* backend loads the state file from a local file. This has the best
performance, but requires having a copy of the state file locally. You also
need to take care of updating the state file periodically or on-demand when it
changes.

Example for hiera.yaml:

    - name: "Terraform state file"
      data_hash: hiera_tfstate
      options:
        backend: 'file'
        statefile: '/var/lib/misc/.tfstate'

## s3

This backend loads the state file from Amazon S3 bucket. You will need to
install the AWS S3 SDK for Ruby to use it for puppet lookup command:

    $ /opt/puppetlabs/puppet/bin/gem install aws-sdk-s3

Or to use it on a Puppetserver:

    $ puppetserver gem install aws-sdk-s3
    $ systemctl restart puppetserver

Example for hiera.yaml:

    - name: "Terraform state file"
      data_hash: hiera_tfstate
      options:
        backend: 's3'
        profile: 'hiera'
        bucket: 'terraform-state.example.org'
        key: 'foobar'

Credentials and region can be fetched from the profile (/root/.aws/credentials):

    [hiera]
    aws_access_key_id = <access-key-id>
    aws_secret_access_key = <secret-access-key>
    region = us-west-1

If the profile is missing then usual environment variables will be used:

    * AWS_ACCESS_KEY_ID
    * AWS_SECRET_ACCESS_KEY
    * AWS_REGION

# Common configuration options

The "options" has support the following common options:

* *no_root_module*: remove the root module name from all resource paths. This only works if *all* resources in your state file are inside a module. Valid values are *true* and *false*.
* *debug*: print debugging information such as the Hiera-compatible state file

# Testing lookups

It is recommended to test lookups in a feature environment before trying to actually use this backend in Puppet code:

    $ puppet lookup tfstate::aws_acm_certificate::my-alb::arn --node puppet.example.org --environment my_feature

To view debugging information add *--explain*:

    $ puppet lookup tfstate::aws_acm_certificate::my-alb::arn --node puppet.example.org --environment my_feature --explain

To view the produced data hash in yaml format set *debug: true* in the
hiera.yaml options hash for this backend, then run the command above.

# Safety precautions

You **should** use proper data types in your Hiera lookups to ensure that the data
you get matches your expectations.

# License

This software is licensed under the [BSD-2-Clause license](LICENSE).
