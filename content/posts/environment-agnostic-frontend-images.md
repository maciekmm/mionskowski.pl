---
layout: post
title:  "How to create frontend images with environment variables"
date:   2021-01-24 
tags:
  - docker
  - react
categories:
  - frontend
  - devops
aliases:
  - /environment-agnostic-frontend-images
---

Environment variables are a standard way to parametrize backend containers. For some reason, they haven't seen wide adoption on the frontend side, which just as much requires customization. Both *React* and *Vue* still recommend creating separate `.env` files for different environments, which is unwieldy at best if you want to containarize the application. In this tutorial, I will guide You through an opinionated way to **create environment agnostic frontend images** in React.

# What are the advantages of environment agnostic frontend images?

- Reduced CI pipeline time - single build pass means no need to create three different images for your development, staging, and production environments
- Simplified environment promotion - deploy an image to staging environment and promote it to production once all tests pass
- Mitigated risk of deploying improper image to production environment

# How to add an API URL environment variable to frontend Docker images?

The most common use case for environment variables on the frontend side is to have a customizable backend url for dev, staging and production environments respectively.
This example is based on a **React** app created using create-react-app. But the examples can be easily ported to *Vue* or even *Next* with slight modifications.

## Step 1: Create `/public/env.js` file

You should put values related to the local development environment there. You might decide to commit the file to the code repository assuming that all local environments will have the same configuration.

```javascript
window.env = {}
window.env.API_HOST = 'http://localhost:10001' // local development API_HOST if applicable
```

## Step 2: Create a <code>script</code> tag in `index.html`'s `<head>` section pointing to the file created previously.

It is important to load the file before loading any other javascript that will use the variables, thus `<head>` seems to be a good place. 

```html
<head>
    ...
    <script src="%PUBLIC_URL%/env.js"></script>
</head>
```

## Step 3: Create a `docker` directory

This is where all image related files will live to reduce clutter in the project root.

## Step 4: Create `50-substitute-env-variables.sh` under `/docker`

The `50-substitute-env-variables.sh` script will be responsible for substituting environment variables in container **runtime**. It will utilize a built-in feature in the nginx image that runs scripts from `/docker-entrypoint.d/` directory.

```bash
#!/usr/bin/env sh

set -o errexit
set -o nounset 
set -o pipefail

: "${API_HOST}" # ensure API_HOST exists and exit otherwise

cat <<EOF > /usr/share/nginx/html/env.js
window.env = {};
window.env.API_HOST = "$API_HOST";
EOF
```

Don't forget to make it executable by running `chown +x 50-substitute-env-variables.sh`

## Step 5: Create `nginx.conf` under `/docker`

You might want to tweak the `try_files` directive based on the router you use. The configuration below will try to load a file if it exists and the `index.html` otherwise.

```nginx
user nginx;

worker_processes    auto;

events { worker_connections 1024; }

http {
    server {
        server_tokens off;

        listen  80;
        root    /usr/share/nginx/html;
        include /etc/nginx/mime.types;

        location / {
            try_files $uri $uri/ index.html =404;
        }
    }
}
```

## Step 6: Create a `Dockerfile` under `/docker`

We will use multi-stage Docker image to reduce the image size. Note that You should bind both `node` and `nginx` images to some version.

```docker
FROM node:current as build

WORKDIR /src

COPY package.json /src

RUN npm install

COPY . /src

RUN npm run build


FROM nginx:alpine

RUN rm -rf /usr/share/nginx/html/*
COPY --from=build /src/build /usr/share/nginx/html/
COPY /docker/nginx.conf /etc/nginx/nginx.conf
COPY /docker/50-substitute-env-variables.sh /docker-entrypoint.d/
```

At the end of this step the directory structure should look as follows.
```
/app
    /docker
        50-substitute-env-variables.sh
        Dockerfile
        nginx.conf
```

## Step 7: Reference the environment variable in code

You can reference the `API_HOST` variable under `window.env.API_HOST`, for example:

```javascript
function App() {
  const apiHost = window.env.API_HOST

  return (
    <div className="App">
      <p>
        API Host: {apiHost}
      </p>
    </div>
  );
}
```

## Step 8: Build the image

From app's root directory execute:

```bash
docker build -f docker/Dockerfile -t docker.your-company.com/app:version .
```

After successful build, you can start the container by typing:

```bash
docker run --rm -e API_HOST=http://prod.company.com/ -p 8080:80 docker.your-company.com/app:version
```

In case you forget to specify the environment variable the container will exit with:

```
/docker-entrypoint.d/50-substitute-env-variables.sh: line 7: API_HOST: parameter not set
```

You can now access the container under 127.0.0.1:8080.

{{< code-preview url="localhost:8080" >}}
{{< code-preview-file language="html" hide=true >}}
API Host: http://prod.company.com/
{{< /code-preview-file >}}
{{< /code-preview >}}


The full code is available on [Github](https://github.com/maciekmm/environment-agnostic-frontend-docker-image).
