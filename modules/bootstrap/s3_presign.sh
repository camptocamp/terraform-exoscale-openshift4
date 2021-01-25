#!/bin/sh

eval "$(jq -r '@sh "ENDPOINT=\(.endpoint) S3URI=\(.s3uri)"')"

presign=$(aws --endpoint "$ENDPOINT" s3 presign "$S3URI")

jq -n --arg presign "$presign" '{"presign":$presign}'
