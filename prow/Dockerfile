FROM quay.io/openshifttest/python:3.9

LABEL vendor="Red Hat Inc." maintainer="OCP Perfscale Team"

RUN curl -sSL https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux-amd64-rhel8.tar.gz | tar -xvzf - &&\
    mv oc /bin && mv kubectl /bin && apt-get update && apt-get install -y gettext-base uuid-runtime jq openssh-client sshpass && \
    ln -s /bin/bash /usr/bin/bash && /usr/local/bin/python -m pip install --upgrade pip && pip install virtualenv jq

RUN curl -sSL $(curl -sSL https://api.github.com/repos/openshift/rosa/releases/latest | jq -r ".assets[] | select(.name == \"rosa_Linux_x86_64.tar.gz\") | .browser_download_url") | tar xvzf - &&\
    mv rosa /bin && chmod 777 /bin/rosa

RUN curl -sSL $(curl -sSL https://api.github.com/repos/openshift-online/ocm-cli/releases/latest | jq -r ".assets[] | select(.name == \"ocm-linux-amd64\") | .browser_download_url") --output /bin/ocm && chmod 777 /bin/ocm

RUN git config --global user.name "Tu Nombre" && git config --global user.email "tu.email@example.com"

WORKDIR /e2e

RUN chown -R 777 /e2e

CMD cd /e2e && tail -f /dev/null
