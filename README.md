## ERP NEXT DOCKER IMAGE

Custom erpnext image


# Encoding apps.json

```shell
export APPS_JSON_BASE64=$(base64 -w 0 apps.json)
```

# Building Docker Image
```shell
docker build \
  --build-arg=APPS_JSON_BASE64=$APPS_JSON_BASE64 \
  --tag=custom-erpnext:v1.0.0 .
```
# Changing Docker Image Tag

```shell
docker tag custom-erpnext:v1.0.0 geniusdynamics/erpnext:v1.0.0
```

# pushing Docker Image

```shell
docker login 
docker push
```