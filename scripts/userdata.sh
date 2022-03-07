#!/bin/sh
sudo amazon-linux-extras install -y nginx1
sudo amazon-linux-extras install -y php7.4

sudo systemctl enable nginx
sudo systemctl enable php-fpm

sudo mkdir -p /var/www/html
sudo chown nginx:nginx /var/www/html
cat <<'EOF' > /etc/nginx/conf.d/phpid.conf
server {
  listen 8080;
  root /var/www/html;

  location / {
        index index.php index.html;
        try_files $uri $uri/ /index.php?$args;
  }
  charset utf-8;
  gzip  on;
  location ~ /\. {
        access_log                      off;
        log_not_found                   off;
        deny                            all;
  }
 
  location = /robots.txt {
               allow all;
               log_not_found off;
               access_log off;
  }
  location ~* /(?:uploads|files)/.*\.php$ {
    deny all;
  }
  location ~ \.php$ {
        try_files                       $uri =404;
        include                         /etc/nginx/fastcgi_params;
        fastcgi_read_timeout            3600s;
        fastcgi_buffer_size             128k;
        fastcgi_buffers                 4 128k;
        fastcgi_param                   SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_pass                    unix:/run/php-fpm/www.sock;
        fastcgi_index                   index.php;
  }
}
EOF

cat <<EOF > /etc/php-fpm.d/z99-phpid.conf
user = nginx
group = nginx
pm = ondemand
EOF

cat <<EOF > /var/www/html/index.php
<?php phpinfo();
EOF

sudo systemctl start nginx
sudo systemctl start php-fpm