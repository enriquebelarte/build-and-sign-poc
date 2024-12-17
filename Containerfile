ARG DTK_IMAGE
ARG SIGNER_SDK_IMAGE
ARG DRIVER_IMAGE
ARG AWS_AUTH_SECRET
FROM ${DTK_IMAGE} as dtk
ARG DRIVER_REPO
WORKDIR /home/builder
COPY --chmod=0755 build-commands.sh /home/builder/build-commands.sh
RUN git clone $DRIVER_REPO && cd $(basename $DRIVER_REPO .git) && \
    /home/builder/build-commands.sh

FROM ${SIGNER_SDK_IMAGE} as signer
ARG AWS_AUTH_SECRET
ARG AWS_DEFAULT_REGION
ARG AWS_KMS_KEY_LABEL
USER root
COPY --from=dtk /home/builder /opt/drivers/
COPY --from=dtk /usr/src/kernels/5.14.0-503.15.1.el9_5.x86_64/scripts/sign-file /usr/local/bin/sign-file
RUN --mount=type=secret,id=${AWS_AUTH_SECRET}/AWS_KMS_TOKEN echo "export AWS_KMS_TOKEN="$(cat /run/secrets/${AWS_AUTH_SECRET}/AWS_KMS_TOKEN) >> /tmp/envfile 
RUN --mount=type=secret,id=${AWS_AUTH_SECRET}/AWS_ACCESS_KEY_ID echo "export AWS_ACCESS_KEY_ID="$(cat /run/secrets/${AWS_AUTH_SECRET}/AWS_ACCESS_KEY_ID) >> /tmp/envfile
RUN --mount=type=secret,id=${AWS_AUTH_SECRET}/AWS_SECRET_ACCESS_KEY echo "export AWS_SECRET_ACCESS_KEY="$(cat /run/secrets/${AWS_AUTH_SECRET}/AWS_SECRET_ACCESS_KEY) >> /tmp/envfile
RUN source /tmp/envfile && \
    sed  -i '1i openssl_conf = openssl_init' /etc/pki/tls/openssl.cnf  && \
    cat /etc/aws-kms-pkcs11/openssl-pkcs11.conf >> /etc/pki/tls/openssl.cnf && \
    export PKCS11_MODULE_PATH=/usr/lib64/pkcs11/aws_kms_pkcs11.so && \
    export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} && \
    export AWS_KMS_KEY_LABEL=${AWS_KMS_KEY_LABEL} && \
    rm -f /etc/aws-kms-pkcs11/config.json && \
    cat <<EOF /etc/aws-kms-pkcs11/config.json
{
  "slots": [
    {
      "label": "$AWS_KMS_KEY_LABEL",
      "kms_key_id": "$AWS_KMS_TOKEN",
      "aws_region": "$AWS_DEFAULT_REGION",
      "certificate_path": "/etc/aws-kms-pkcs11/cert.pem"
     }
           ]
}
EOF
RUN cat /etc/aws-kms-pkcs11/config.json && \
    openssl engine -t -c && \
    openssl req -config /etc/aws-kms-pkcs11/x509.genkey -x509 -key "pkcs11:model=0;manufacturer=aws_kms;serial=0;token=$AWS_KMS_KEY_LABEL" -keyform engine -engine pkcs11 -out /etc/aws-kms-pkcs11/cert.pem -days 36500 
    #bash -x /bin/enable_kms_pkcs11 && \
#    sign-file sha256 "pkcs11:model=0;manufacturer=aws_kms;serial=0;token=$AWS_KMS_KEY_LABEL" /etc/aws-kms-pkcs11/cert.pem \
#    /opt/drivers/silly-kmod/silly.ko /opt/drivers/silly-kmod/silly-signed.ko
#    oot_modules="/opt/drivers/" && \
#    find "$oot_modules" -type f -name "*.ko" | while IFS= read -r file; do \
#        signedfile="${oot_modules}$(basename "${file%.*}")-signed.ko"; \
#        sign-file sha256 \
#            "pkcs11:model=0;manufacturer=aws_kms;serial=0;token=$AWS_KMS_KEY_LABEL" \
#            /etc/aws-kms-pkcs11/cert.pem \
#            "$file" \
#            "$signedfile"; \
#    done	   
#FROM ${DRIVER_IMAGE}
#COPY --from=signer /opt/drivers /opt/drivers
