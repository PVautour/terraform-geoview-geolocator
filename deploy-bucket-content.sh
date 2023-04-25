#!/bin/sh
aws s3 cp ./geolocator-bucket-content/ s3://geolocator-tf --recursive
