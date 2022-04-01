---
layout: post
title:  "How to detect breaking changes and lint Protobuf automatically using Gitlab CI and Buf"
date: 2021-04-07
tags:
 - devops
 - ci/cd
 - gitlab
categories:
 - devops
comments: false
aliases:
 - /ci-pipeline-for-protobuf
---

**Protocol Buffers** or **Protobufs** are language-agnostic mechanisms for serializing data. 
Protobuf schemas are specified using **Protocol Buffer language**, which is among the most popular and widely adopted [IDL](https://en.wikipedia.org/wiki/Interface_description_language)s in the industry.

Protobufs are most commonly used in [RPC](https://grpc.io) services for inter-service communication. Their usage is also growing for public-facing interfaces, and recently they have been adopted in tools such as [Apache Kafka](https://docs.confluent.io/platform/current/schema-registry/serdes-develop/serdes-protobuf.html).

[Used correctly](https://developers.google.com/protocol-buffers/docs/proto3), they enable both forward and backward compatible message producing and consuming. Meaning that old consumers/clients  (using old Protobuf schema) can consume messages from new producers/servers and vice-versa. For me, this is the most compelling point in the offerings of Protobufs.

# Breaking changes detection

To maintain backward/forward compatibility in Protobufs, every change to the schema must be thoroughly code-reviewed and tested for compliance. Humans are prone to making errors. Therefore, several tools have emerged to help with the process, most notably [Buf](https://buf.build).

> We’re working quickly to build a modern Protobuf ecosystem. Our first tool is the Buf CLI, built to help you create consistent Protobuf APIs that preserve compatibility and comply with design best practices. The tool is currently available on an open-source basis.

To check if the current working copy is compatible with a previous revision, you can invoke.

```bash
buf check --against 'reference-to-a-previous-revision'
```

Where `reference-to-a-previous-revision` may be either a git repository reference or an [image built](https://docs.buf.build/tour-7) by Buf.

To check against a particular branch, you can execute

```bash
buf check --against '.git#branch=master'
```

For all other means of referencing particular code revision, you can consult Buf's [excellent docs](https://docs.buf.build/breaking-usage#compare-directly-against-a-git-branch-or-git-tag).

## Ensuring adequate compatibility constraints

Not all systems use Protobufs equal, some will serialize the message to `JSON` down the line, others will solely rely on binary messages. Buf is flexible in terms of defining an adequate compatibility level for a project.

Buf's docs provide a great [overview](https://docs.buf.build/breaking-overview) of supported rules.

## Detecting breaking changes using Gitlab CI

When using a Merge Request based flow it is usually enough to check every merge request for compatibility breaking changes against the target branch. 

The solution does not cover all situations, most notably when changes are introduced without using merge requests, but supporting all cases would require building and storing buf images. 

Besides a static binary, Buf also provides a docker image. Using it will simplify the workflow.

To check every merge request introduce the following snippet to your repository's `.gitlab-ci.yml`:

```yaml
stages:
  - ensure backwards compatibility

validate merge request:
  stage: ensure backwards compatibility
  image: 
    name: bufbuild/buf:0.41.0
    entrypoint: [""]
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
  script:
    - buf breaking --against "${CI_REPOSITORY_URL}#branch=${CI_MERGE_REQUEST_TARGET_BRANCH_NAME}"
```

`CI_REPOSITORY_URL` expands to a URL that can be supplied to `git clone`. It includes a token, therefore, access management is of no concern.

## Detecting breaking changes using other CI solutions

[Buf's repository](https://github.com/bufbuild/buf-example/) contains exemplary workflow definitions for:
- Travis CI
- Github Actions
- Circle CI


# Code style checking

Linters help to ensure code style consistency across files. With Protobuf it is no different.

Linting with buf is effortless and can be done by running `buf lint`.

If you encounter errors or warnings from `buf`, do not try to fix them absent-mindedly. Things will break if the schema is used in a production environment. Instead, make small, incremental changes and check for incompatibilities. Should one arise, you can [make an exclusion](https://docs.buf.build/lint-configuration) and fix your mistake in the future interface version.

## Lint automatically using Gitlab CI

To check every commit on every branch, introduce the following snipped to `.gitlab-ci.yml`.

```yaml
stages:
  - lint

lint:
  stage: lint
  image: 
    name: bufbuild/buf:0.41.0
    entrypoint: [""]
  script:
    - buf lint
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS'
      when: never
    - if: '$CI_COMMIT_BRANCH'
```

The rules attached to the lint stage will prevent multiple pipelines running for a merge request.


# Combining linting with breaking changes detection

You can easily combine examples outlined above in a single `.gitlab-ci.yml`:

```yaml
image: 
  name: bufbuild/buf:0.41.0
  entrypoint: [""]

stages:
  - lint
  - ensure backwards compatibility

lint:
  stage: lint
  script:
    - buf lint
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS'
      when: never
    - if: '$CI_COMMIT_BRANCH'

validate merge request:
  stage: ensure backwards compatibility
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
  script:
    - buf breaking --against "${CI_REPOSITORY_URL}#branch=${CI_MERGE_REQUEST_TARGET_BRANCH_NAME}"
```

I have created a sample repository under [https://gitlab.com/mionskowski/protobuf-ci](https://gitlab.com/mionskowski/protobuf-ci). Navigate to [Merge Requests](https://gitlab.com/mionskowski/protobuf-ci/-/merge_requests) to see both passed and failed pipelines.
