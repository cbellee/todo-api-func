# Azure Function container
This example deploys a small Go todo list application as a custom container image to an Azure Function running on a Linux App Service plan. 

The Bicep template also deploys the following resources:
- Azure SQL Server
- Azure SQL Database
- Virtual Network and subnets
- Storage Account
- Azure Container Registry
- Application Insights
- User managed identity.

Optionally, if the ./deploy.sh script is passed the '-p' flag, the SQL Server, Azure Container Registry and Storage Account will each be provisioned behind their own Private Endpoints.

## Deployment
1. create a file ./deploy/.env containing 'SQL_ADMIN_USER_PASSWORD' variable name and value contents show below

NOTE: double quotes are required around the password value
```
SQL_ADMIN_USER_PASSWORD="<your password>"
```
2. run the deployment script

NOTE: ./deploy/main.bicep template will be used.
```
$ cd ./deploy
$ ./deploy.sh
```
3. add the '-p' flag to deploy the Azure SQL Database, Azure Container Registry and Azure Function storage account behind private endpoints. 

NOTE: ./deploy/main.private.bicep template will be used instead.
```
$ cd ./deploy
$ ./deploy.sh -p
```
4. add the '-s' flag to skip the container image build
```
$ cd ./deploy
$ ./deploy.sh -s
```

## Test the API

1. get the function FQDN
```
FUNCTION_FQDN=$(az deployment group show --name 'infra-deployment' -g $RG_NAME --query properties.outputs.functionFqdn.value -o tsv)
```

2. add new todo items
```
curl https://$FUNCTION_FQDN/api/todos -X POST -d '{"description":"feed the dogs"}'
curl https://$FUNCTION_FQDN/api/todos -X POST -d '{"description":"get milk"}'
curl https://$FUNCTION_FQDN/api/todos -X POST -d '{"description":"walk the dogs"}'
```

3. display all todo items
```
curl https://$FUNCTION_FQDN/api/todos
```

4. complete a todo item
```
curl https://$FUNCTION_FQDN/api/todos/complete/1 -X PATCH
```

5. get completed todo items
```
curl https://$FUNCTION_FQDN/api/todos/completed
```

6. get incomplete todo items
```
curl https://$FUNCTION_FQDN/api/todos/incomplete
```

7. update todo item
```
curl https://$FUNCTION_FQDN/api/todos/2 -X PATCH -d '{"description":"get chocolate"}'
```

8. delete todo item
```
curl https://$FUNCTION_FQDN/api/todos/1 -X DELETE
```