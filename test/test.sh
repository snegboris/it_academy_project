#!/bin/bash

old_ifs="$IFS"
IFS=$'\n'

files=("wp-activate.php" "wp-config-docker.php" "wp-login.php" "wp-signup.php")
flag1=0
flag2=0

case "$1" in

"Image" )

cd /usr/src/wordpress/

echo -e "####### Wordpress some files checking #######\n"
for var in ${files[@]}
do
 if [[ -f $var ]]
  then echo "$var ....... OK"
  else echo "$var ....... Fail"
       flag1=1
 fi
done

echo -e "\n####### Apache2 installation checking #######\n"
for var in $(dpkg --get-selections | grep apache)
do
 if [[ $var == *"install"* ]]
  then echo "$var --- OK"
  else echo "$var --- Fail"
       flag2=1
 fi
done

if [[ $flag1 == 0 && $flag2 == 0 ]]
 then echo -e "\n=== Test status: SUCCESSFUL ===\n"
 else echo -e "\n=== Test status: FAILED ===\n"
fi

;;

"Deploy" )

echo -e "Response status:\n"
curl -siL http://wordpress.k8s-1.sa | grep HTTP | sed -n 2p

echo -e "\nContent check:\n"
if (curl -sL http://wordpress.k8s-1.sa | grep -q 'Select a default language')
 then echo "OK"
 else echo "Bad"
      flag1=1
fi

if [[ $flag1 == 0 ]]
 then echo -e "\n=== Test status: SUCCESSFUL ===\n"
 else echo -e "\n=== Test status: FAILED ===\n"
fi

;;

"Upgrade" )

echo -e "Response status:\n"
curl -s -i http://wordpress.k8s-1.sa | head -1

echo -e "\nContent check:\n"
if (curl -s http://wordpress.k8s-1.sa | grep -wq 'Proudly powered by')
 then echo "OK"
 else echo "Bad"
      flag1=1
fi
echo -e "\nWordpress version:\n"
curl -s http://wordpress.k8s-1.sa | grep 'generator' | awk -F'"' '{print $4}'

if [[ $flag1 == 0 ]]
 then echo -e "\n=== Test status: SUCCESSFUL ===\n"
 else echo -e "\n=== Test status: FAILED ===\n"
fi

;;

esac

IFS="$old_ifs"
