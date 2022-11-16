FROM golang:latest AS builder
COPY ./api/ /api
WORKDIR /api
RUN CGO_ENABLED=1 GOOS=linux go build -o handler .

FROM mcr.microsoft.com/azure-functions/dotnet:4.9.1-appservice
ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
    AzureFunctionsJobHost__Logging__Console__IsEnabled=true

COPY --from=builder /api/ /home/site/wwwroot
RUN rm /home/site/wwwroot/handler.go
RUN rm /home/site/wwwroot/go.mod
RUN rm /home/site/wwwroot/go.sum
