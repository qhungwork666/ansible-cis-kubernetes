FROM alpine:3.22.2

RUN apk update \
    && apk add --no-cache \
        bash \
        ansible \
        openssh-client \
    && rm -rf /var/cache/apk/*

WORKDIR /ansible-cis-k8s
COPY . /ansible-cis-k8s/