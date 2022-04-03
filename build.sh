#!/usr/bin/env bash

set -eux

base_url="https://mionskowski.pl/"
environment="production"

if [[ "${CF_PAGES:=0}" == "1" ]]; then
    if [[ "$CF_PAGES_BRANCH" != "master" ]]; then
        base_url="$CF_PAGES_URL"
        environment="development"
    fi
fi

hugo --environment "$environment" --baseURL "$base_url"