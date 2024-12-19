#!/bin/bash

sudo snap install yq

docker compose down
docker compose up --build -d
sleep 3

echo "Restarting MinIO to allow it to connect to OpenLDAP"
docker compose restart minio
sleep 3

echo "Show all users and groups in the LDAP directory"
docker exec minio-ldap-test-openldap-1 ldapsearch -H ldap://localhost -D "cn=admin,dc=example,dc=org" -w "admin123" -b "dc=example,dc=org" -x "(objectclass=inetOrgPerson)"
docker exec minio-ldap-test-openldap-1 ldapsearch -H ldap://localhost -D "cn=admin,dc=example,dc=org" -w "admin123" -b "dc=example,dc=org" -x "(objectclass=groupOfNames)"

echo "Create versioned ogmatic-zoo bucket"
mc alias set local http://localhost:9000 minio minio123
mc mb local/ogmatic-zoo
mc version enable local/ogmatic-zoo

echo "Attach 'readonly' policies to all users and 'consoleAdmin' to user1'"
mc admin policy create local ogmatic-zoo-policy ogmatic-zoo-policy.json
mc idp ldap policy attach local readonly --group='cn=others,ou=groups,dc=example,dc=org'
mc idp ldap policy attach local readonly --group='cn=admins,ou=groups,dc=example,dc=org'
mc idp ldap policy attach local ogmatic-zoo-policy --group='cn=admins,ou=groups,dc=example,dc=org'
sleep 1
echo "You can log on using user1/pwd1 or user2/pwd2"
#mc idp ldap policy entities local --user='cn=user1,ou=users,dc=example,dc=org'

USER1_CREDS_JSON=$(curl -X POST 'http://localhost:9000?Action=AssumeRoleWithLDAPIdentity&LDAPUsername=user1&LDAPPassword=pwd1&Version=2011-06-15' | yq -p xml -o=json .AssumeRoleWithLDAPIdentityResponse.AssumeRoleWithLDAPIdentityResult.Credentials)
export MC_HOST_user1=http://$(echo $USER1_CREDS_JSON | jq -r .AccessKeyId):$(echo $USER1_CREDS_JSON | jq -r .SecretAccessKey):$(echo $USER1_CREDS_JSON | jq -r .SessionToken)@localhost:9000

USER2_CREDS_JSON=$(curl -X POST 'http://localhost:9000?Action=AssumeRoleWithLDAPIdentity&LDAPUsername=user2&LDAPPassword=pwd2&Version=2011-06-15' | yq -p xml -o=json .AssumeRoleWithLDAPIdentityResponse.AssumeRoleWithLDAPIdentityResult.Credentials)
export MC_HOST_user2=http://$(echo $USER2_CREDS_JSON | jq -r .AccessKeyId):$(echo $USER2_CREDS_JSON | jq -r .SecretAccessKey):$(echo $USER2_CREDS_JSON | jq -r .SessionToken)@localhost:9000

echo $MC_HOST_user1
echo $MC_HOST_user2

echo "Copying using user 1 (should succeed)"
#sleep 10
mc idp ldap policy entities local --user='cn=user1,ou=users,dc=example,dc=org'
mc cp create.sh user1/ogmatic-zoo/cores_er/schemas/Cores-PD.Design.DEF_Instance.json
mc cp docker-compose.yaml user1/ogmatic-zoo/cores_er/schemas/Cores-PD.Design.DEF_Instance.json
mc cp create.sh user1/ogmatic-zoo/cores_er/schemas/Cores-PD.Power.Instance_Count.json
mc cp docker-compose.yaml user1/ogmatic-zoo/cores_er/schemas/Cores-PD.Power.Instance_Count.json
mc cp config-ldap.ldif user1/ogmatic-zoo/cores_er/schemas/Cores-PD.Power.Instance_Count.json
mc cp dex.yaml user1/ogmatic-zoo/cores_er/schemas/Cores-PD.Power.Instance_Count.json
mc cp ogmatic-zoo-policy.json user1/ogmatic-zoo/cores_er/schemas/Cores-PD.Power.Instance_Count.json
mc ls --versions user1/ogmatic-zoo/cores_er/schemas/Cores-PD.Power.Instance_Count.json 
V1_VERSION=$(mc ls --versions user1/ogmatic-zoo/cores_er/schemas/Cores-PD.Power.Instance_Count.json | awk '/v1/ { print $6 }')
mc rm user1/ogmatic-zoo/cores_er/schemas/Cores-PD.Power.Instance_Count.json --version-id $V1_VERSION
mc ls --versions user1/ogmatic-zoo/cores_er/schemas/Cores-PD.Power.Instance_Count.json 
