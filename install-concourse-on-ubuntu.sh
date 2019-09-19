#! /bin/bash -eu
 
EXTERNAL_URL_HOST_NAME="$1"
ADMIN_USERNAME="$2"
ADMIN_PASSWORD="$3"
 
CONCOURSE_VERSION=${CONCOURSE_VERSION:-5.5.1}
 
sudo apt-get update
sudo apt install postgresql -y
sudo su postgres -c "createuser $(whoami)"
sudo su postgres -c "createdb --owner=$(whoami) atc"

 
curl -L -f -o /tmp/concourse-$CONCOURSE_VERSION-linux-amd64.tgz https://github.com/concourse/concourse/releases/download/v$CONCOURSE_VERSION/concourse-$CONCOURSE_VERSION-linux-amd64.tgz
curl -L -f -o /tmp/fly-$CONCOURSE_VERSION-linux-amd64.tgz https://github.com/concourse/concourse/releases/download/v$CONCOURSE_VERSION/fly-$CONCOURSE_VERSION-linux-amd64.tgz
sudo tar -zxvf /tmp/concourse-*.tgz -C /usr/local
sudo tar -zxvf /tmp/fly-*.tgz -C /usr/local/bin
sudo chmod +x /usr/local/bin/fly
sudo chmod +x /usr/local/concourse/bin
sudo chmod 0777 /etc/profile
export PATH=$PATH:/usr/local/concourse/bin
sudo echo 'export PATH=$PATH:/usr/local/concourse/bin' >> /etc/profile
sudo chmod 0644 /etc/profile
concourse --version
fly --version

sudo adduser --system --group concourse
sudo mkdir -p /etc/concourse
sudo chown $(whoami):concourse /etc/concourse

concourse generate-key -t rsa -f /etc/concourse/session_signing_key
concourse generate-key -t ssh -f /etc/concourse/tsa_host_key
concourse generate-key -t ssh -f /etc/concourse/worker_key
cp /etc/concourse/worker_key.pub /etc/concourse/authorized_worker_keys
 
sudo chmod g+r /etc/concourse/*
 
sudo cat >concourse_web.service <<-EOF
        [Unit]
        Description=Concourse CI Web
        After=postgres.service
 
        [Service]
        ExecStart=/usr/local/concourse/bin/concourse web \
               --add-local-user=$ADMIN_USERNAME:$ADMIN_PASSWORD \
               --main-team-local-user=$ADMIN_USERNAME \
               --session-signing-key=/etc/concourse/session_signing_key \
               --tsa-host-key=/etc/concourse/tsa_host_key \
               --tsa-authorized-keys=/etc/concourse/authorized_worker_keys \
               --external-url=http://$EXTERNAL_URL_HOST_NAME:8080 \
               --postgres-socket=/var/run/postgresql
 
        User=$(whoami)
        Group=$(whoami)
 
        Type=simple
 
        [Install]
        WantedBy=default.target
EOF

 
sudo cat >concourse_worker.service <<-EOF
        [Unit]
        Description=Concourse CI Worker
        After=concourse_web.service
 
        [Service]
        ExecStart=/usr/local/concourse/bin/concourse worker \
               --work-dir=/etc/concourse/worker \
               --tsa-host=127.0.0.1:2222 \
               --tsa-public-key=/etc/concourse/tsa_host_key.pub \
               --tsa-worker-private-key=/etc/concourse/worker_key
 
        User=root
        Group=root
 
        Type=simple
 
        [Install]
        WantedBy=default.target
EOF

sudo mv concourse_web.service /etc/systemd/system/concourse_web.service
sudo mv concourse_worker.service /etc/systemd/system/concourse_worker.service

sudo systemctl enable concourse_web.service
sudo systemctl start concourse_web.service
 
sudo systemctl enable concourse_worker.service
sudo systemctl start concourse_worker.service

sudo systemctl status concourse_web.service
sudo systemctl status concourse_worker.service