#!/bin/bash

while getopts "s:p:" opt; do
  case $opt in
    s)
      skip=${OPTARG}
      ;;
    p)
      private=${OPTARG}
      ;;
  esac
done

LOCATION='australiaeast'
APP_NAME='todo-api-func'
RG_NAME="$APP_NAME-rg"
ENVIRONMENT=dev
SEMVER=0.1.0
TAG="$ENVIRONMENT-$SEMVER"
IMAGE_NAME="func-api:$TAG"
TEMPLATE_PATH=./main.bicep

if [ -z ${privatelink+x} ]
then
    TEMPLATE_PATH=./main.privatelink.bicep
    echo "TEMPLATE_PATH: $TEMPLATE_PATH"

    RG_NAME="$APP_NAME-private-rg"
    echo "RG_NAME: $RG_NAME"
fi

# load the .env file 
source ./.env

# create resource group
az group create --name $RG_NAME --location $LOCATION

# deploy ACR
az deployment group create \
    --resource-group $RG_NAME \
    --name 'acr-deployment' \
    --template-file ./modules/acr.bicep \
    --parameters location=$LOCATION

ACR_NAME=$(az deployment group show --resource-group $RG_NAME --name 'acr-deployment' --query properties.outputs.acrName.value -o tsv)

if [ -z !${skip+x} ]
then
   # build image in ACR
    echo "building container image..." 
    az acr build -r $ACR_NAME -t $IMAGE_NAME -f ../func/Dockerfile ../func
else
    echo "skipping container image build..." 
fi

IMAGE_FULL_NAME="${ACR_NAME}.azurecr.io/${IMAGE_NAME}"

# deploy solution
az deployment group create \
    --name 'infra-deployment' \
    --resource-group $RG_NAME \
    --template-file $TEMPLATE_PATH \
    --parameters location=$LOCATION \
    --parameters appName=$APP_NAME \
    --parameters environment='dev' \
    --parameters sqlAdminUserPassword=$SQL_ADMIN_USER_PASSWORD \
    --parameters containerImageName=$IMAGE_FULL_NAME \
    --parameters acrName=$ACR_NAME

FUNCTION_FQDN=$(az deployment group show --name 'infra-deployment' -g $RG_NAME --query properties.outputs.functionFqdn.value -o tsv)
echo $FUNCTION_FQDN
