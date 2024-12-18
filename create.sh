#!/bin/bash
docker compose down
docker compose up --build -d
sleep 3
echo "Restarting MinIO to allow it to connect to OpenLDAP"
docker compose restart minio
sleep 3
echo "Show all users and groups in the LDAP directory"
docker exec ldap-openldap-1 ldapsearch -H ldap://localhost -D "cn=admin,dc=example,dc=org" -w "admin123" -b "dc=example,dc=org" -x "(objectclass=inetOrgPerson)"
docker exec ldap-openldap-1 ldapsearch -H ldap://localhost -D "cn=admin,dc=example,dc=org" -w "admin123" -b "dc=example,dc=org" -x "(objectclass=groupOfNames)"
echo "Attach 'readonly' policies to all users and 'consoleAdmin' to user1'"
mc mb local/test
mc admin policy create local prefix prefix-policy.json
mc idp ldap policy attach local readonly --group='cn=others,ou=groups,dc=example,dc=org'
mc idp ldap policy attach local readonly --group='cn=admins,ou=groups,dc=example,dc=org'
mc idp ldap policy attach local prefix --group='cn=admins,ou=groups,dc=example,dc=org'
sleep 1
echo "You can log on using user1/pwd1 or user2/pwd2"
mc idp ldap policy entities local --user='CN=admins,ou=groups,dc=example,dc=org'

USER1_CREDS_JSON=$(curl -X POST 'http://localhost:9000?Action=AssumeRoleWithLDAPIdentity&LDAPUsername=user1&LDAPPassword=pwd1&Version=2011-06-15' | xq | jq .AssumeRoleWithLDAPIdentityResponse.AssumeRoleWithLDAPIdentityResult.Credentials)
export MC_HOST_user1=http://$(echo $USER1_CREDS_JSON | jq -r .AccessKeyId):$(echo $USER1_CREDS_JSON | jq -r .SecretAccessKey):$(echo $USER1_CREDS_JSON | jq -r .SessionToken)@localhost:9000

USER2_CREDS_JSON=$(curl -X POST 'http://localhost:9000?Action=AssumeRoleWithLDAPIdentity&LDAPUsername=user2&LDAPPassword=pwd2&Version=2011-06-15' | xq | jq .AssumeRoleWithLDAPIdentityResponse.AssumeRoleWithLDAPIdentityResult.Credentials)
export MC_HOST_user2=http://$(echo $USER2_CREDS_JSON | jq -r .AccessKeyId):$(echo $USER2_CREDS_JSON | jq -r .SecretAccessKey):$(echo $USER2_CREDS_JSON | jq -r .SessionToken)@localhost:9000

echo "Copying using user 1 (should succeed)"
mc idp ldap policy entities local --user='cn=user1,ou=users,dc=example,dc=org'
mc cp create.sh user1/test/prefix/create-user-1

echo "Copying using user 2 (expect failure)"
mc idp ldap policy entities local --user='cn=user2,ou=users,dc=example,dc=org'
mc cp create.sh user2/test/prefix/create-user-2
