[![Build Docker Image](https://github.com/DE-MUC-UCC-OSEM/nodejs/actions/workflows/build.yml/badge.svg)](https://github.com/DE-MUC-UCC-OSEM/nodejs/actions/workflows/build.yml)

## Information
Nodejs running in a minimal OpenSUSE Docker Image

Using a pre-built Nodejs executable version. Everything put into a minimal Container image built from an OpenSUSE tumbleweed image

## Images

Each release publishes two images:

| Tag | Content | Use |
| --- | --- | --- |
| `<version>-r<release>-tumbleweed` | Stripped OpenSUSE tumbleweed with bash, node and the FIPS provider. No npm. | Runtime image |
| `<version>-r<release>-builder` | Full OpenSUSE tumbleweed with bash, git, npm and the same node / FIPS setup | Build stage of multi-stage builds |

Both images contain node at `/usr/local/bin/node` with the same OpenSSL configuration, so build results from the builder image run unchanged in the runtime image.

## Run the image

You can run the image via Docker
```
docker run -dit ghcr.io/de-muc-ucc-osem/nodejs:26.13.0-r0-tumbleweed
```

## Build an application image

```Dockerfile
FROM ghcr.io/de-muc-ucc-osem/nodejs:26.13.0-r0-builder AS build
WORKDIR /app
COPY . .
RUN npm ci --omit=dev

FROM ghcr.io/de-muc-ucc-osem/nodejs:26.13.0-r0-tumbleweed
COPY --from=build /app /app
CMD ["/usr/local/bin/node", "/app/index.js"]
```
## Configuration
