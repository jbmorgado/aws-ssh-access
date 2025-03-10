#!/bin/bash
  
#############################################################################################
# Helper script to allow standard SSH tooling to access servers via AWS Session Manager
#
# Requires the AWS CLI, and the Session Manager plugin to be installed.
#
# Assumes AWS session already started, or creds available, for the account where the EC2 instance lives.
# Also assumes the instance is in the region already set in AWS_DEFAULT_REGION/AWS_REGION, but this can
# be overridden here.
#
# Example usage in your local .ssh/config file:
#
# A server in your current/default region:
#
# Host confluence-server-1
#   HostName i-058333c60d11f0a1e
#   User ubuntu
#   ProxyCommand ssh-aws-ssm.sh %h %p
#
# A server in another region:
#
# Host au-test
#   HostName i-00fd3ff38393b2c1f
#   User ec2-user
#   ProxyCommand ssh-aws-ssm.sh %h %p ap-southeast-2
#
# The region ($3) can be omitted, in which case the current/default region will be used.
#
  
# Treat use of an undefined variable as an error.
set -o nounset
# Ensure we exit on all errors.
set -o errexit
# Ensure we see failures buried in pipelines.
set -o pipefail
# set -x
  
echoerr () {
  printf '%s\n' "$@" 1>&2
}
  
die () {
  (( $# > 0 )) && echoerr "$@"
  exit 1
}
  
__HOST="${1}"
__PORT="${2}"
__AWS_REGION="${3:-}"
  
if [[ "${__AWS_REGION:-}" == '' ]]; then
  aws ssm start-session --document-name 'AWS-StartSSHSession' --target "$__HOST" --parameters "portNumber=$__PORT"
else
  aws --region "$__AWS_REGION" ssm start-session --document-name 'AWS-StartSSHSession' --target "$__HOST" --parameters "portNumber=$__PORT" --cli-read-timeout 0 --cli-connect-timeout 0
fi