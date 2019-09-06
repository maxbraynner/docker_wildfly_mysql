#!/bin/bash

# Usage: execute.sh [WildFly mode] [configuration file]
#
# The default mode is 'standalone' and default configuration is based on the
# mode. It can be 'standalone.xml' or 'domain.xml'.

JBOSS_HOME=/opt/jboss/wildfly
JBOSS_CLI=$JBOSS_HOME/bin/jboss-cli.sh
JBOSS_MODE=${1:-"standalone"}
JBOSS_CONFIG=${2:-"$JBOSS_MODE.xml"}

function wait_for_server() {
  until `$JBOSS_CLI -c ":read-attribute(name=server-state)" 2> /dev/null | grep -q running`; do
    sleep 1
  done
}

echo "=> Starting WildFly server"
$JBOSS_HOME/bin/$JBOSS_MODE.sh -b 0.0.0.0 -c $JBOSS_CONFIG -Djboss.http.port=$PORT &

echo "=> Waiting for the server to boot"
wait_for_server

echo "=> Executing the commands"
echo "=> MYSQL_URI (docker with networking): " $MYSQL_URI
echo "=> DATASOURCE_NAME (docker with networking): " $DATASOURCE_NAME
echo "=> DATABASE_NAME (docker with networking): " $DATABASE_NAME

$JBOSS_CLI -c << EOF
batch
set CONNECTION_URL=jdbc:mysql://$MYSQL_URI/$DATABASE_NAME
# Add mysql module
module add --name=com.mysql --resources=/opt/jboss/wildfly/customization/mysql-connector-java-8.0.17.jar --dependencies=javax.api,javax.transaction.api
# Add mysql driver
/subsystem=datasources/jdbc-driver=mysql:add(driver-name=mysql,driver-module-name=com.mysql,driver-xa-datasource-class-name=com.mysql.jdbc.jdbc2.optional.MysqlXADataSource)
# Add the datasource
data-source add --name=$DATASOURCE_NAME --driver-name=mysql --jndi-name=java:jboss/datasources/$DATASOURCE_NAME --connection-url=jdbc:mysql://$MYSQL_URI/$DATABASE_NAME --user-name=$DATABASE_USER --password=$DATABASE_PASSWORD --use-ccm=false --max-pool-size=25 --blocking-timeout-wait-millis=5000 --enabled=true
# Execute the batch
run-batch
EOF

# Deploy the WAR
cp /opt/jboss/wildfly/customization/api.war $JBOSS_HOME/$JBOSS_MODE/deployments/ROOT.war

echo "=> Shutting down WildFly"
if [ "$JBOSS_MODE" = "standalone" ]; then
  $JBOSS_CLI -c ":shutdown"
else
  $JBOSS_CLI -c "/host=*:shutdown"
fi

echo "=> Restarting WildFly"
$JBOSS_HOME/bin/$JBOSS_MODE.sh -b 0.0.0.0 -c $JBOSS_CONFIG -Djboss.http.port=$PORT