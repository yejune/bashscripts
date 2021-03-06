#!/bin/bash

set +e
set -o noglob


#
# Set Colors
#

bold="\e[1m"
dim="\e[2m"
underline="\e[4m"
blink="\e[5m"
reset="\e[0m"
red="\e[31m"
green="\e[32m"
blue="\e[34m"


#
# Common Output Styles
#

function wait_for_dpkg_lock {
  # check for a lock on dpkg (another installation is running)
  sudo lsof /var/lib/dpkg/lock > /dev/null
  dpkg_is_locked="$?"
  if [ "$dpkg_is_locked" == "0" ]; then
    echo "Waiting for another installation to finish"
    sleep 5
    wait_for_dpkg_lock
  else
    sudo rm -f /var/lib/dpkg/lock
  fi
}
 
h1() {
  if [ ! -z "$DEBUG" ]; then
    if [ "$DEBUG" == "on" ]; then
      printf "\n$@\n"
    elif [ "$DEBUG" == "beauty" ]; then
      printf "\n${bold}${underline}%s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
    fi
  fi
}
h2() {
  if [ ! -z "$DEBUG" ]; then
    if [ "$DEBUG" == "on" ]; then
      printf "\n$@\n"
    elif [ "$DEBUG" == "beauty" ]; then
      printf "\n${bold}%s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
    fi
  fi
}
info() {
  if [ ! -z "$DEBUG" ]; then
    if [ "$DEBUG" == "on" ]; then
      printf "$@\n"
    elif [ "$DEBUG" == "beauty" ]; then
      printf "${dim}➜ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
    fi
  fi
}
success() {
  if [ ! -z "$DEBUG" ]; then
    if [ "$DEBUG" == "on" ]; then
      printf "$@\n"
    elif [ "$DEBUG" == "beauty" ]; then
      printf "${green}✔ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
    fi
  fi
}
error() {
  printf "${red}${bold}✖ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
warnError() {
  printf "${red}✖ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
warnNotice() {
  if [ ! -z "$DEBUG" ]; then
    if [ "$DEBUG" == "on" ]; then
      printf "$@\n"
    elif [ "$DEBUG" == "beauty" ]; then
      printf "${blue}✖ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
    fi
  fi
}
note() {
  if [ ! -z "$DEBUG" ]; then
    if [ "$DEBUG" == "on" ]; then
      printf "\n$@\n"
    elif [ "$DEBUG" == "beauty" ]; then
      printf "\n${bold}${blue}Note:${reset} ${blue}%s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
    fi
  fi
}

# Runs the specified command and logs it appropriately.
#   $1 = command
#   $2 = (optional) error message
#   $3 = (optional) success message
#   $4 = (optional) global variable to assign the output to
runCommand() {
  command="$1"
  info "$1"
  output="$(eval $command 2>&1)"
  ret_code=$?

  if [ $ret_code != 0 ]; then
    warnError "$output"
    if [ ! -z "$2" ]; then
      error "$2"
    fi
    exit $ret_code
  fi
  if [ ! -z "$3" ]; then
    success "$3"
  fi
  if [ ! -z "$4" ]; then
    eval "$4='$output'"
  fi
}

typeExists() {
  if [ $(type -P $1) ]; then
    return 0
  fi
  return 1
}

inArray() {
    local haystack=${1}[@]
    local needle=${2}
    for i in ${!haystack}; do
        if [[ ${i} == ${needle} ]]; then
            return 0
        fi
    done
    return 1
}

installAwsCli() {
  h2 "Installing AWS CLI"
  wait_for_dpkg_lock
  runCommand "sudo apt-get -y install python zip unzip"
  runCommand "curl -s https://s3.amazonaws.com/aws-cli/awscli-bundle.zip -o awscli-bundle.zip"
  runCommand "unzip awscli-bundle.zip"
  runCommand "sudo ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws"
}

vercomp() {
  if [[ $1 == $2 ]]
  then
    return 0
  fi
  local IFS=.
  local i ver1=($1) ver2=($2)

  # fill empty fields in ver1 with zeros
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
  do
    ver1[i]=0
  done

  for ((i=0; i<${#ver1[@]}; i++))
  do
    if [[ -z ${ver2[i]} ]]
    then
      # fill empty fields in ver2 with zeros
      ver2[i]=0
    fi
    if ((10#${ver1[i]} > 10#${ver2[i]}))
    then
      return 1
    fi
    if ((10#${ver1[i]} < 10#${ver2[i]}))
    then
      return 2
    fi
  done
  return 0
}

handle_argument() {
  echo $1
}
usage() {
  echo "help"
}
deploy_create() {
  local DEBUG="off"
  DEPLOYMENT_VAR_NAME=""
  while true; do
    # uncomment the next line to see how shift is working
    #echo "\$1:\"$1\" \$2:\"$2\" \$3:\"$3\""
    if [ ! -z "$1" ]; then
      case "$1" in
        -h | --help ) usage; exit; ;;
        -v | --DEBUG ) DEBUG="$2"; shift 2 ;;
        -k | --AWS-ACCESS-KEY ) AWS_ACCESS_KEY="$2"; shift 2 ;;
        -s | --AWS-ACCESS-SECRET ) AWS_ACCESS_SECRET="$2"; shift 2 ;;
        -r | --AWS-REGION ) AWS_REGION="$2"; shift 2 ;;
        -n | --APPLICATION-NAME ) APPLICATION_NAME="$2"; shift 2 ;;
        -g | --DEPLOYMENT-GROUP ) DEPLOYMENT_GROUP="$2"; shift 2 ;;
        -b | --S3-LOCATION-BUCKET ) S3_LOCATION_BUCKET="$2"; shift 2 ;;
        -f | --S3-FOLDER-NAME ) S3_FOLDER_NAME="$2"; shift 2 ;;
        -o | --DEPLOYMENT-OVERVIEW ) DEPLOYMENT_OVERVIEW="$2"; shift 2 ;;
        -* ) echo "unknown option: $1" >&2; exit 1; shift; break ;;
        * ) DEPLOYMENT_VAR_NAME="$1"; shift 1;;
      esac
    else
      break;
    fi
  done

  if [ -z "$APPLICATION_NAME" ]; then
    error "Please set the \"--APPLICATION-NAME\" variable"
    exit 1
  fi

  if [ -z "$DEPLOYMENT_GROUP" ]; then
    error "Please set the \"--DEPLOYMENT-GROUP\" variable"
    exit 1
  fi

  if [ -z "$S3_LOCATION_BUCKET" ]; then
    error "Please set the \"--S3-LOCATION-BUCKET\" variable"
    exit 1
  fi

  if [ -z "$S3_FOLDER_NAME" ]; then
    error "Please set the \"--S3-FOLDER_NAME\" variable"
    exit 1
  fi

  vpsservers=("Ready" "Succeeded");
  if ! inArray vpsservers $DEPLOYMENT_OVERVIEW; then
    if [ ! -z $DEPLOYMENT_OVERVIEW ]; then
      echo "--DEPLOYMENT-OVERVIEW is null ${vpsservers[*]/#/| }"
      exit 1
    fi
  fi


  # ----- Install AWS Cli -----
  # see documentation http://docs.aws.amazon.com/cli/latest/userguide/installing.html
  # ---------------------------

  # Check AWS is installed
  h1 "Step 1: Checking Dependencies"

  if ! typeExists "aws"; then
    installAwsCli
    success "Installing AWS CLI $(aws --version 2>&1) succeeded"
  else
    # aws-cli 1.11.80 is required for proper SSE syntax
    REQURED_VERSION="1.11.80"
    AWS_FULL_VER=$(aws --version 2>&1)
    AWS_VER=$(echo $AWS_FULL_VER | sed -e 's/aws-cli\///' | sed -e 's/ Python.*//')
    vercomp $AWS_VER $REQURED_VERSION
    if [[ $? == 2 ]]; then
      warnError "Update AWS CLI version ($AWS_VER < $REQURED_VERSION)"
      exit 1
    fi

    success "Dependencies met $(aws --version 2>&1)"
  fi

  # ----- Configure -----
  # see documentation
  #    http://docs.aws.amazon.com/cli/latest/reference/configure/index.html
  # ----------------------

  h1 "Step 2: Configuring AWS"
  if [ -z "$AWS_ACCESS_KEY" ]; then
    # Ensure an access key has already been set
    if [ $(aws configure list | grep access_key | wc -l) -lt 1 ]; then
      error "No AWS_ACCESS_KEY specified and AWS cli is not configured with an access key via env, config, or shared credentials"
      exit 1
    fi
    success "AWS Access Key already configured."
  else
    $(aws configure set aws_access_key_id $AWS_ACCESS_KEY 2>&1)
    success "Successfully configured AWS Access Key ID."
  fi

  if [ -z "$AWS_ACCESS_SECRET" ]; then
    # Ensure an access key secret has already been set
    if [ $(aws configure list | grep secret_key | wc -l) -lt 1 ]; then
      error "No AWS_ACCESS_SECRET specified and AWS cli is not configured with an access secret via env, config, or shared credentials"
      exit 1
    fi
    success "AWS Secret Access Key already configured."
  else
    $(aws configure set aws_secret_access_key $AWS_ACCESS_SECRET 2>&1)
    success "Successfully configured AWS Secret Access Key ID."
  fi

  if [ -z "$AWS_REGION" ]; then
    # Ensure AWS region has already been set
    if [ $(aws configure list | grep region | wc -l) -lt 1 ]; then
      error "No AWS_REGION specified and AWS cli is not configured with an existing default region via env, config, or shared credentials"
      exit 1
    fi
    success "AWS Region already configured."
  else
    $(aws configure set default.region $AWS_REGION 2>&1)
    success "Successfully configured AWS default region."
  fi

  if [ $(aws configure list | grep output | wc -l) -lt 1 ]; then
    $(aws configure set default.output json 2>&1)
  fi



  # Check deployment group exists
  h1 "Step 3: Checking Deployment Application"
  DEPLOYMENT_APPLICATION_EXISTS="aws deploy get-application --application-name $APPLICATION_NAME"
  info "$DEPLOYMENT_APPLICATION_EXISTS"
  DEPLOYMENT_GROUP_EXISTS_OUTPUT=$($DEPLOYMENT_APPLICATION_EXISTS 2>&1)

  if [ $? -ne 0 ]; then
    error "Deployment application \"$APPLICATION_NAME\" not found"
    exit 1;
  else
    success "Deployment application \"$APPLICATION_NAME\" exists"
  fi



  # Check deployment group exists
  h1 "Step 4: Checking Deployment Group"
  DEPLOYMENT_GROUP_EXISTS="aws deploy get-deployment-group --application-name $APPLICATION_NAME --deployment-group-name $DEPLOYMENT_GROUP"
  info "$DEPLOYMENT_GROUP_EXISTS"
  DEPLOYMENT_GROUP_EXISTS_OUTPUT=$($DEPLOYMENT_GROUP_EXISTS 2>&1)

  if [ $? -ne 0 ]; then
    error "Deployment group \"$DEPLOYMENT_GROUP\" not found for application \"$APPLICATION_NAME\""
    exit 1;
  else
    success "Deployment group \"$DEPLOYMENT_GROUP\" exists for application \"$APPLICATION_NAME\""
  fi



  h1 "Step 5: Checking appspec"
  BASEDIR=$(pwd)
  APP_SOURCE="${BASEDIR}/deploy"
  if [ ! -e "${APP_SOURCE}/appspec.yml" ]; then
    error "The specified source directory \"${APP_SOURCE}\" does not contain an \"appspec.yml\" in the application root."
    exit 1
  else
    success "\"appspec.yml\" exists for directory \"${APP_SOURCE}\""
  fi



  h1 "Step 6: Pushing to S3"
  PUSH_S3="aws deploy push --application-name ${APPLICATION_NAME} --s3-location s3://${S3_LOCATION_BUCKET}/${S3_FOLDER_NAME} --source deploy"

  info "$PUSH_S3"
  PUSH_S3_OUTPUT=$($PUSH_S3 2>&1)

  if [ $? -ne 0 ]; then
    warnError "$PUSH_S3_OUTPUT"
    error "Pushing revision '$S3_FOLDER_NAME' to S3 failed"
    exit 1
  fi
  success "Pushing revision '$S3_FOLDER_NAME' to S3 succeeded"


  # ----- Create Deployment -----
  # see documentation http://docs.aws.amazon.com/cli/latest/reference/deploy/create-deployment.html
  # ----------------------
  DEPLOYMENT_CONFIG_NAME="CodeDeployDefault.OneAtATime"
  DEPLOYMENT_DESCRIPTION="code deploy"
  h1 "Step 7: Creating Deployment"
  DEPLOYMENT_CMD="aws deploy create-deployment --application-name $APPLICATION_NAME --ignore-application-stop-failures --deployment-config-name $DEPLOYMENT_CONFIG_NAME --deployment-group-name $DEPLOYMENT_GROUP --s3-location bucket=${S3_LOCATION_BUCKET},key=${S3_FOLDER_NAME},bundleType=zip --query 'deploymentId' --output text"

  if [ -n "$DEPLOYMENT_DESCRIPTION" ]; then
    DEPLOYMENT_CMD="$DEPLOYMENT_CMD --description \"$DEPLOYMENT_DESCRIPTION\""
  fi

  DEPLOYMENT_ID=""
  runCommand "$DEPLOYMENT_CMD" \
             "Deployment of application \"$APPLICATION_NAME\" on deployment group \"$DEPLOYMENT_GROUP\" failed" \
             "" \
             DEPLOYMENT_ID

  success "Successfully created deployment: \"$DEPLOYMENT_ID\""
  note "You can follow your deployment at: https://console.aws.amazon.com/codedeploy/home#/deployments/$DEPLOYMENT_ID"

  eval "$DEPLOYMENT_VAR_NAME='$DEPLOYMENT_ID'"
  export $DEPLOYMENT_VAR_NAME

  deploy_wait --DEBUG ${DEBUG} --DEPLOYMENT-ID ${DEPLOYMENT_ID} --APPLICATION-NAME ${APPLICATION_NAME} --DEPLOYMENT-GROUP ${DEPLOYMENT_GROUP} --DEPLOYMENT-OVERVIEW ${DEPLOYMENT_OVERVIEW}

}

deploy_wait() {

  DEPLOYMENT_ID=""
  local DEBUG="off"
  while true; do
    # uncomment the next line to see how shift is working
    #echo "\$1:\"$1\" \$2:\"$2\" \$3:\"$3\""
    if [ ! -z "$1" ]; then
      case "$1" in
        -h | --help ) usage; exit; ;;
        -v | --DEBUG ) DEBUG="$2"; shift 2 ;;
        -d | --DEPLOYMENT-ID ) DEPLOYMENT_ID="$2"; shift 2 ;;
        -n | --APPLICATION-NAME ) APPLICATION_NAME="$2"; shift 2 ;;
        -g | --DEPLOYMENT-GROUP ) DEPLOYMENT_GROUP="$2"; shift 2 ;;
        -o | --DEPLOYMENT-OVERVIEW ) DEPLOYMENT_OVERVIEW="$2"; shift 2 ;;
        -* ) echo "unknown option: $1" >&2; exit 1; shift; break ;;
        * ) exit 1; shift 1;;
      esac
    else
      break;
    fi
  done

  info $DEPLOYMENT_OVERVIEW

  h1 "Step 8: Deployment Overview"

  DEPLOYMENT_GET="aws deploy get-deployment --deployment-id ${DEPLOYMENT_ID} --query \"deploymentInfo.status\" --output text "
  h2 "Monitoring deployment \"$DEPLOYMENT_ID\" for \"$APPLICATION_NAME\" on deployment group $DEPLOYMENT_GROUP ..."
  info "$DEPLOYMENT_GET"

  while true; do
    DEPLOYMENT_GET_OUTPUT="$(eval $DEPLOYMENT_GET 2>&1)"
    if [ $? != 0 ]; then
      warnError "$DEPLOYMENT_GET_OUTPUT"
      error "Deployment of application \"$APPLICATION_NAME\" on deployment group \"$DEPLOYMENT_GROUP\" failed"
      exit 1
    fi

    # Deployment Overview
    STATUS=$DEPLOYMENT_GET_OUTPUT;

    info ${STATUS};

    if [ "$STATUS" == "Failed" ]; then
      #OUTPUT=$(eval aws autoscaling delete-auto-scaling-group --force-delete --auto-scaling-group-name CodeDeploy_${DEPLOYMENT_GROUP}_${DEPLOYMENT_ID} 2>&1);
      warnError "$OUTPUT"
      exit 1;
    elif [ "$STATUS" == "Stopped" ]; then
      OUTPUT=$(eval aws autoscaling delete-auto-scaling-group --force-delete --auto-scaling-group-name CodeDeploy_${DEPLOYMENT_GROUP}_${DEPLOYMENT_ID} 2>&1);
      warnError "$OUTPUT"
      exit 1;
    elif [ "$STATUS" == "Succeeded" ]; then
      if [ "$DEPLOYMENT_OVERVIEW" == "Succeeded" ]; then
        success "Deployment ${DEPLOYMENT_ID} of application '${APPLICATION_NAME}' on deployment group '${DEPLOYMENT_GROUP}' succeeded"
        break;
      fi;
    elif [ "$STATUS" == "Ready" ]; then
      if [ "$DEPLOYMENT_OVERVIEW" == "Ready" ]; then
        success "Deployment ${DEPLOYMENT_ID} of application '${APPLICATION_NAME}' on deployment group '${DEPLOYMENT_GROUP}' ready"
        break;
      fi
    else
      echo "" &> /dev/null;
    fi;
    sleep 30;
  done
}

deploy_infomation() {
  DEPLOYMENT_ID=""
  local DEBUG="off"
  while true; do
    # uncomment the next line to see how shift is working
    #echo "\$1:\"$1\" \$2:\"$2\" \$3:\"$3\""
    if [ ! -z "$1" ]; then
      case "$1" in
        -h | --help ) usage; exit; ;;
        -v | --DEBUG ) DEBUG="$2"; shift 2 ;;
        -v | --FILTER ) FILTER="$2"; shift 2 ;;
        -d | --DEPLOYMENT-ID ) DEPLOYMENT_ID="$2"; shift 2 ;;
        -* ) echo "unknown option: $1" >&2; exit 1; shift; break ;;
      esac
    else
      break;
    fi
  done

  INSTANCE_GET="aws deploy list-deployment-instances --instance-type-filter ${FILTER} --deployment-id \"${DEPLOYMENT_ID}\" --output text --query \"instancesList\""

  runCommand "$INSTANCE_GET" \
      "error" \
      "" \
      INSTANCE_IDS

  INSTANCE_LEN=${#INSTANCE_IDS[@]}

  for i in "${!INSTANCE_IDS[@]}"; do
    j=$(($i+1))
    INSTANCE_ID=${INSTANCE_IDS[$i]}

    PUBLIC_DNS_GET="aws ec2 describe-instances --instance-ids ${INSTANCE_ID} --output text --query 'Reservations[*].Instances[*].[InstanceId, NetworkInterfaces[0].Association.PublicIp, NetworkInterfaces[0].PrivateIpAddress]'"

    runCommand "$PUBLIC_DNS_GET" \
        "error" \
        "" \
        PUBLIC_DNS

    echo "${PUBLIC_DNS}"

  done

}

function awsconfig()
{
    aws configure set aws_access_key_id "${AWS_ACCESS_KEY_ID}"
    aws configure set aws_secret_access_key "${AWS_SECRET_ACCESS_KEY}"
    aws configure set default.region "${AWS_REGION}"
    aws configure set default.output "json"

    # HOME_FOLDER='~/.aws';
    # mkdir -p "${HOME_FOLDER}"
    #
    # touch "${HOME_FOLDER}/config"
    # echo "[default]" | tee --append "${HOME_FOLDER}/config"
    # echo "output = json" | tee --append "${HOME_FOLDER}/config"
    # echo "region = ap-northeast-2" | tee --append "${HOME_FOLDER}/config"
    #
    # touch "${HOME_FOLDER}/credentials"
    # echo "[default]" | tee --append "${HOME_FOLDER}/credentials"
    # echo "aws_access_key_id = ${AWS_ACCESS_KEY_ID}" | tee --append "${HOME_FOLDER}/credentials"
    # echo "aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}" | tee --append "${HOME_FOLDER}/credentials"
}

function test_deploy() {

  local ENVIRONMENT_NAME=""
  local HOSTED_ZONE=""
  #local DEBUG="off"
  local BUILD_NUMBER=$(date +"%y%m/%d-%H%M")

  while true; do
    # uncomment the next line to see how shift is working
    #echo "\$1:\"$1\" \$2:\"$2\" \$3:\"$3\""
    if [ ! -z "$1" ]; then
      case "$1" in
        -h | --help ) usage; exit; ;;
        -v | --DEBUG ) DEBUG="$2"; shift 2 ;;
        -e | --ENVIRONMENT_NAME ) ENVIRONMENT_NAME="$2"; shift 2 ;;
        -d | --DOMAINS ) DOMAINS="$2"; shift 2 ;;
        -z | --HOSTED_ZONE ) HOSTED_ZONE="$2"; shift 2 ;;
        -b | --BUILD_NUMBER ) BUILD_NUMBER="$2"; shift 2 ;;
        -* ) echo "unknown option: $1" >&2; exit 1; shift; break ;;
        * ) exit 1; shift 1;;
      esac
    else
      break;
    fi
  done

  docker rm -f webserver 2> /dev/null
  docker rm -f buildserver 2> /dev/null

  wait_for_dpkg_lock
  runCommand "sudo apt-get install -y php" "" ""
  awsconfig

  ELB_NAME="${ENVIRONMENT_NAME}LoadBalancer"
  ELB_OUTPUT=`aws elb describe-load-balancers --load-balancer-names ${ELB_NAME}`

  SECURITY_GROUPS=`echo $ELB_OUTPUT | php -r 'foreach(json_decode(fgets(STDIN), true)["LoadBalancerDescriptions"][0]["SecurityGroups"] as $v) echo $v." ";'`;

  INSTANCE_IP=$(curl -s "http://169.254.169.254/latest/meta-data/public-ipv4")
  INSTANCE_ID=$(curl -s "http://169.254.169.254/latest/meta-data/instance-id")
  CLIENT_IP=$(curl -s "http://checkip.amazonaws.com/")

  echo "INSTANCE_ID : ${INSTANCE_ID}"

  aws ec2 create-tags --resources "${INSTANCE_ID}" \
  --tags "Key=Name,Value='Test Server(${DOMAINS}) $(date +%y%m%d-%H%M)'" \
         "Key=Domain,Value='${DOMAINS}'"

  DOMAINS=(${DOMAINS//,/ })

  runCommand "aws route53 list-hosted-zones-by-name" "err" "ok" HOSTED_ZONES

  HOSTED_ZONE_ID=$(echo ${HOSTED_ZONES} | php -r "\$a=json_decode(fgets(STDIN), true);foreach(\$a['HostedZones'] as \$v) if(\$v['Name']=='${HOSTED_ZONE}.') echo str_replace(\"/hostedzone/\",\"\", \$v[\"Id\"]);");

  for DOMAIN in "${DOMAINS[@]}"; do
      INPUT="{\"ChangeBatch\": {\"Comment\": \"SUPERVOLT : Update the A record set\", \"Changes\": [{\"Action\": \"UPSERT\", \"ResourceRecordSet\": {\"Name\": \"${DOMAIN}\", \"Type\": \"A\", \"TTL\": 300, \"ResourceRecords\": [{\"Value\": \"$INSTANCE_IP\"}]}}]}}"

      aws route53 change-resource-record-sets --hosted-zone-id "${HOSTED_ZONE_ID}" --cli-input-json "${INPUT}"
  done

  #runCommand "source '$(pwd)/deploy/scripts/envs/${APP}-Build.sh'" "error build run" "success build run"
  runCommand "composer install --no-dev --no-interaction --no-progress --no-scripts --optimize-autoloader" "error composer" "success composer"
  runCommand "docker build --build-arg BUILD_NUMBER=${BUILD_NUMBER} --build-arg BUILD_ENV=worker --tag webserver ." "error build" "success build"
  runCommand "source '$(pwd)/deploy/scripts/envs/${ENVIRONMENT_NAME}.sh'" "error start" "success start"

  deploy_secrity_group
  runCommand 'aws ec2 describe-security-groups --group-names Supervolt-Deploy-SecurityGroup --output text --query "SecurityGroups[0].GroupId"' "" "" GROUPID
  runCommand "aws ec2 modify-instance-attribute --instance-id ${INSTANCE_ID} --groups ${GROUPID} ${SECURITY_GROUPS}" "error secret group" "success secret group"
}

function deploy_secrity_group() {
  runCommand "aws ec2 describe-security-groups --group-names Supervolt-Deploy-SecurityGroup 2> /dev/null" "" ""

  ret_code=$?

  if [ $ret_code != 0 ]; then
    aws ec2 create-security-group --group-name Supervolt-Deploy-SecurityGroup --description 'Supervolt-Deploy-SecurityGroup Enable port SSH access.'
    aws ec2 authorize-security-group-ingress --group-name Supervolt-Deploy-SecurityGroup --protocol tcp --port 22 --cidr 0.0.0.0/0
  fi
}

function real_deploy() {
  local DEPLOYMENT_GROUP_NAME=$@
  docker rm -f webserver 2> /dev/null
  docker rm -f buildserver 2> /dev/null
  rm -rf ~/deploy/webserver.tgz

  #runCommand "source '$(pwd)/deploy/scripts/envs/${APP}-Build.sh'" "error build run" "success build run"
  runCommand "composer install --no-dev --no-interaction --no-progress --no-scripts --optimize-autoloader" "error composer" "success composer"
  runCommand "docker build --build-arg BUILD_NUMBER=${BUILD_NUMBER} --tag webserver ." "error build" "success build"
  #runCommand "source '$(pwd)/deploy/scripts/envs/${DEPLOYMENT_GROUP_NAME}.sh'" "error run" "success run"

  # save image to tgz
  runCommand "docker save webserver | gzip -c > deploy/webserver.tgz" "error image save" "success image save"

  deploy_create \
    --DEBUG on \
    --APPLICATION-NAME "${APP}-App" \
    --DEPLOYMENT-GROUP "${DEPLOYMENT_GROUP_NAME}" \
    --S3-LOCATION-BUCKET "${S3_LOCATION_BUCKET}" \
    --S3-FOLDER-NAME "${S3_FOLDER_NAME}" \
    --DEPLOYMENT-OVERVIEW Succeeded \
    DEPLOYMENT_ID

  deploy_infomation \
    --DEPLOYMENT-ID "${DEPLOYMENT_ID}" \
    --FILTER Green
}

function real_worker_deploy() {
  local DEPLOYMENT_GROUP_NAME=$@
  docker rm -f webserver 2> /dev/null
  docker rm -f buildserver 2> /dev/null
  rm -rf ~/deploy/webserver.tgz

  #runCommand "source '$(pwd)/deploy/scripts/envs/${APP}-Build.sh'" "error build run" "success build run"
  runCommand "composer install --no-dev --no-interaction --no-progress --no-scripts --optimize-autoloader" "error composer" "success composer"
  runCommand "docker build --build-arg BUILD_NUMBER=${BUILD_NUMBER} --build-arg BUILD_ENV=worker --tag webserver ." "error build" "success build"
  #runCommand "source '$(pwd)/deploy/scripts/envs/${DEPLOYMENT_GROUP_NAME}.sh'" "error run" "success run"

  # save image to tgz
  runCommand "docker save webserver | gzip -c > deploy/webserver.tgz" "error image save" "success image save"

  deploy_create \
    --DEBUG on \
    --APPLICATION-NAME "${APP}-App" \
    --DEPLOYMENT-GROUP "${DEPLOYMENT_GROUP_NAME}" \
    --S3-LOCATION-BUCKET "${S3_LOCATION_BUCKET}" \
    --S3-FOLDER-NAME "${S3_FOLDER_NAME}" \
    --DEPLOYMENT-OVERVIEW Succeeded \
    DEPLOYMENT_ID

  deploy_infomation \
    --DEPLOYMENT-ID "${DEPLOYMENT_ID}"
}

function real_deploy_production() {
  real_deploy "${APP}-Prod"
}

function real_deploy_production_worker() {
  real_worker_deploy "${APP}-Prod-Worker"
}

function real_deploy_staging() {
  real_deploy "${APP}-Staging"
}

function real_deploy_staging_worker() {
  real_worker_deploy "${APP}-Staging-Worker"
}

function test_deploy_production() {
  test_deploy \
    --ENVIRONMENT_NAME "${APP}-Prod" \
    --HOSTED_ZONE "${HOSTED_ZONE}" \
    --DOMAINS ${@}
}

function test_deploy_staging() {
  test_deploy \
    --ENVIRONMENT_NAME "${APP}-Staging" \
    --HOSTED_ZONE "${HOSTED_ZONE}" \
    --DOMAINS ${@}
}

function test_deploy_dev() {
  test_deploy \
    --ENVIRONMENT_NAME "${APP}-Dev" \
    --HOSTED_ZONE "${HOSTED_ZONE}" \
    --DOMAINS ${@}
}

function delete_instance() {
   local INSTANCE_ID=$(curl -s "http://169.254.169.254/latest/meta-data/instance-id")

   INSTANCE_OUTPUT=`aws ec2 describe-instances --instance-ids ${INSTANCE_ID}`

   INSTANCE_IP=`echo $INSTANCE_OUTPUT | php -r 'echo json_decode(fgets(STDIN), true)["Reservations"][0]["Instances"][0]["NetworkInterfaces"][0]["Association"]["PublicIp"];'`;

   DOMAINS=`echo $INSTANCE_OUTPUT | php -r 'foreach(json_decode(fgets(STDIN), true)["Reservations"][0]["Instances"][0]["Tags"] as $v) if($v["Key"]=="Domain") echo $v["Value"]."";'`;
   echo $DOMAINS;

   DOMAINS=(${DOMAINS//,/ })

   runCommand "aws route53 list-hosted-zones-by-name" "err" "ok" HOSTED_ZONES

   HOSTED_ZONE_ID=$(echo ${HOSTED_ZONES} | php -r "\$a=json_decode(fgets(STDIN), true);foreach(\$a['HostedZones'] as \$v) if(\$v['Name']=='${HOSTED_ZONE}.') echo str_replace(\"/hostedzone/\",\"\", \$v[\"Id\"]);");

   for DOMAIN in "${DOMAINS[@]}"; do
       INPUT="{\"ChangeBatch\": {\"Comment\": \"SUPERVOLT : Delete the A record set\", \"Changes\": [{\"Action\": \"DELETE\", \"ResourceRecordSet\": {\"Name\": \"${DOMAIN}\", \"Type\": \"A\", \"TTL\": 300, \"ResourceRecords\": [{\"Value\": \"$INSTANCE_IP\"}]}}]}}"

       aws route53 change-resource-record-sets --hosted-zone-id "${HOSTED_ZONE_ID}" --cli-input-json "${INPUT}"
   done

   aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}"
}
