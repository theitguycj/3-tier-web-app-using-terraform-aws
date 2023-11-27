#!/bin/bash
sudo -u ec2-user -i <<'EOF'

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash
source ~/.bashrc
nvm install 16
nvm use 16
cd ~/
wget https://github.com/theitguycj/3-tier-web-app-using-terraform-aws/archive/refs/heads/master.zip
unzip master.zip
cd 3-tier-web-app-using-terraform-aws-master/
sed -i 's/LOAD-BALANCER-DNS/${INT-LOAD-BALANCER-DNS}/g' nginx.conf
cd ~/
cp 3-tier-web-app-using-terraform-aws-master/web-tier web-tier --recursive
cd ~/web-tier
npm install 
npm run build
sudo amazon-linux-extras install nginx1 -y
cd /etc/nginx
sudo rm nginx.conf
sudo cp ~/3-tier-web-app-using-terraform-aws-master/nginx.conf nginx.conf
sudo service nginx restart
chmod -R 755 /home/ec2-user
sudo chkconfig nginx on

EOF