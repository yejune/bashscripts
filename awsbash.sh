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

jsonValue() {
  key=$1
  num=$2
  awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'$key'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${num}p
}

installAwsCli() {
  h2 "Installing AWS CLI"
  runCommand "sudo apt-get -y install python zip unzip"
  runCommand "curl https://s3.amazonaws.com/aws-cli/awscli-bundle.zip -o awscli-bundle.zip"
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
  DEBUG="off"
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
  DEPLOYMENT_CMD="aws deploy create-deployment --application-name $APPLICATION_NAME --deployment-config-name $DEPLOYMENT_CONFIG_NAME --deployment-group-name $DEPLOYMENT_GROUP --s3-location bucket=${S3_LOCATION_BUCKET},key=${S3_FOLDER_NAME},bundleType=zip --query 'deploymentId' --output text"

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
  DEBUG="off"
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
      echo "break"
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
      OUTPUT=$(eval aws autoscaling delete-auto-scaling-group --force-delete --auto-scaling-group-name CodeDeploy_${DEPLOYMENT_GROUP}_${DEPLOYMENT_ID} 2>&1);
      warnError "$OUTPUT"
      exit 1;
    elif [ "$STATUS" == "Stopped" ]; then
      OUTPUT=$(eval aws autoscaling delete-auto-scaling-group --force-delete --auto-scaling-group-name CodeDeploy_${DEPLOYMENT_GROUP}_${DEPLOYMENT_ID} 2>&1);
      warnError "$OUTPUT"
      exit 1;
    elif [ "$STATUS" == "Succeeded" ]; then
      if [ "$DEPLOYMENT_OVERVIEW" == "Succeeded" ]; then
        success "Deployment of application '$APPLICATION_NAME' on deployment group '$DEPLOYMENT_GROUP' succeeded"
        break;
      fi;
    elif [ "$STATUS" == "Ready" ]; then
      if [ "$DEPLOYMENT_OVERVIEW" == "Ready" ]; then
        success "Deployment of application '$APPLICATION_NAME' on deployment group '$DEPLOYMENT_GROUP' ready"
        break;
      fi
    else
      echo "" &> /dev/null;
    fi;
    sleep 15;
  done
}

deploy_infomation() {
  DEPLOYMENT_VAR_NAME=""
  DEPLOYMENT_ID=""
  DEBUG="off"
  while true; do
    # uncomment the next line to see how shift is working
    #echo "\$1:\"$1\" \$2:\"$2\" \$3:\"$3\""
    if [ ! -z "$1" ]; then
      case "$1" in
        -h | --help ) usage; exit; ;;
        -v | --DEBUG ) DEBUG="$2"; shift 2 ;;
        -d | --DEPLOYMENT-ID ) DEPLOYMENT_ID="$2"; shift 2 ;;
        -* ) echo "unknown option: $1" >&2; exit 1; shift; break ;;
        * ) DEPLOYMENT_VAR_NAME="$1"; shift 1;;
      esac
    else
      break;
    fi
  done

  INSTANCE_GET="aws deploy list-deployment-instances --instance-type-filter Green --deployment-id \"${DEPLOYMENT_ID}\" --output text --query \"instancesList\""
  runCommand "$INSTANCE_GET" \
      "error" \
      "" \
      INSTANCE_IDS

  INSTANCE_LEN=${#INSTANCE_IDS[@]}

  JSON_STRING="{\"DEPLOYMENT_ID\": \"<a href=\\\"https://console.aws.amazon.com/codedeploy/home#/deployments/${DEPLOYMENT_ID}\\\" target='_blank'>${DEPLOYMENT_ID}</a>\","
  JSON_STRING+="\"INSTANCES\": ["
  for i in "${!INSTANCE_IDS[@]}"; do
    j=$(($i+1))
    INSTANCE_ID=${INSTANCE_IDS[$i]}

    PUBLIC_DNS_GET="aws ec2 describe-instances --instance-ids ${INSTANCE_ID} --output text --query 'Reservations[].Instances[].PublicDnsName'"
    runCommand "$PUBLIC_DNS_GET" \
        "error" \
        "" \
        PUBLIC_DNS

    JSON_STRING+=$(printf "{\"INSTANCE_ID\": \"%s\",\"PUBLIC_DNS\": \"%s\"}\n" "${INSTANCE_ID}" "<a href=\\\"http://${PUBLIC_DNS}\\\" target=\\\"_blank\\\">${PUBLIC_DNS}</a>")

    if [ "$j" -lt "$INSTANCE_LEN" ]; then
      JSON_STRING+=", "
    fi

  done
  JSON_STRING+="]}";

  echo "${JSON_STRING}"

  if [ ! -z "$DEPLOYMENT_VAR_NAME" ]; then
    eval "$DEPLOYMENT_VAR_NAME='$JSON_STRING'"
    export $DEPLOYMENT_VAR_NAME
  fi
}
