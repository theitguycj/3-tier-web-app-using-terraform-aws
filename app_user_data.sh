#!/bin/bash
sudo -u ec2-user -i <<'EOF'

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash
source ~/.bashrc
nvm install 16
nvm use 16
npm install -g pm2
cd ~/
wget https://github.com/theitguycj/3-tier-web-app-using-terraform-aws/archive/refs/heads/master.zip
unzip master.zip
cp 3-tier-web-app-using-terraform-aws-master/app-tier app-tier --recursive
cd ~/app-tier
sed -i 's/DBENDPOINT/${WRITER-ENDPOINT}/g' DbConfig.js
sed -i 's/DBUSERNAME/${USERNAME}/g' DbConfig.js
sed -i 's/DBPASS/${PASSWORD}/g' DbConfig.js
npm install
pm2 start index.js
pm2 startup
sudo env PATH=$PATH:/home/ec2-user/.nvm/versions/node/v16.20.2/bin /home/ec2-user/.nvm/versions/node/v16.20.2/lib/node_modules/pm2/bin/pm2 startup systemd -u ec2-user --hp /home/ec2-user
pm2 save
sudo yum install mysql -y
mysql -h ${WRITER-ENDPOINT} -u ${USERNAME} -p${PASSWORD}
CREATE DATABASE webappdb;
USE webappdb;
CREATE TABLE IF NOT EXISTS transactions(id INT NOT NULL
AUTO_INCREMENT, amount DECIMAL(10,2), description
VARCHAR(100), PRIMARY KEY(id));
INSERT INTO transactions (amount,description) VALUES ('100','bags');
INSERT INTO transactions (amount,description) VALUES ('200','carts');
INSERT INTO transactions (amount,description) VALUES ('300','shelves');
INSERT INTO transactions (amount,description) VALUES ('400','groceries');
INSERT INTO transactions (amount,description) VALUES ('500','gas');

EOF