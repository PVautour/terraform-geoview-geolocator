#!/bin/sh
if [ -n "$bucket_name" ]; then
  printf "\nBucket name is set to:\n"
  printf "\n$bucket_name"
else
  printf "\nPlase enter bucket name: "
  read bucket_name
fi

aws s3 cp ./geolocator-bucket-content/ s3://$bucket_name --recursive
