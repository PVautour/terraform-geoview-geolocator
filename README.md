# README

## To do

- [ ] fix request to nomitatim. seems to send to incorrect url. fix for curl was to put quotes arount the url. the issue in the lambda is probably similar. maybe url encoding?
- [ ] fix the fact that bucket name is hardcoded.
- [ ] setup github actions
- [ ] set naming of s3 bucket based on dev, staging, prod environment variable.

## Deployment

1. deploy/update the infrastructure using `terraform apply`.
2. deploy the s3 bucket content using `./deploy-bucket-content.sh`.

## testing

### sample url args

q=water&keys=geonames
q=eau&keys=nominatim&lang=fr


### sample test event

```JSON
{
  "params": {
    "path": {},
    "querystring": {
      "q": "water",
      "keys": "geonames"
    },
    "header": {}
  }
}
```

## Known bugs

- right now, the function requires increased ram to complete it's queries. 3009 
mb is the current amount. This needs to be monitored as requests timeout or fail 
if ram is filled by the result of a query.