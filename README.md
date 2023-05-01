# README

## To do

- [ ] setup github actions

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