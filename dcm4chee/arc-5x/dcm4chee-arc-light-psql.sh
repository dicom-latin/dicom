!#/usr/bin/env bash

# install_dcm4chee-arc-light
# Instalanción desatendida de Dcm4chee Arc Light

# Actualizamos el sistema operativo como root -- si no se especifica no usar root
apt update && sudo apt -y upgrade                                           #como SUPERUSER
apt install unzip gcc build-essential libdb-dev libtool libltdl-dev -y      #como SUPERUSER

# Nos ubicamos en el directorio home del usuario actual
cd $HOME

# Creamos un directorio para la instalación
mkdir dcm4chee
cd dcm4chee

# Descargamos los paquetes que vamos a necesitar para construir Dcm4chee Arc Light
wget http://download.oracle.com/berkeley-db/db-5.0.32.tar.gz
#wget ftp://ftp.openldap.org/pub/OpenLDAP/openldap-release/openldap-2.4.45.tgz
wget http://www.linuxfromscratch.org/patches/blfs/8.1/openldap-2.4.45-consolidated-1.patch
wget https://sourceforge.net/projects/dcm4che/files/dcm4chee-arc-light5/5.13.0/dcm4chee-arc-5.13.0-psql.zip/download?use_mirror=phoenixnap&r=https%3A%2F%2Fsourceforge.net%2Fprojects%2Fdcm4che%2Ffiles%2Fdcm4chee-arc-light5%2F5.13.0%2F&use_mirror=phoenixnap -O dcm4chee-arc-5.13.0-psql.zip
wget https://download.jboss.org/wildfly/12.0.0.Final/wildfly-12.0.0.Final.zip
wget https://jdbc.postgresql.org/download/postgresql-42.2.5.jar

tar zxvf db-5.0.32.tar.gz
tar xvf openldap-2.4.47.tgz
unzip dcm4chee-arc-5.13.0-psql.zip
unzip wildfly-12.0.0.Final.zip

# Movemos algunas carpetas
mv dcm4chee-arc-5.13.0-mysql dcm4chee
mv wildfly-12.0.0.Final jboss
cd ..

# Movemos la carpeta dcm4chee a /opt
sudo mv dcm4chee /opt/

# Exportamos alguna variables
echo "export DCM4CHEE_ARC='/opt/dcm4chee/dcm4chee'" >> $HOME/.bashrc
echo "export WILDFLY_HOME='/opt/dcm4chee/jboss'" >> $HOME/.bashrc
source $HOME/.bashrc

# Instalamos JRE8
sudo add-apt-repository -y ppa:openjdk-r/ppa
sudo apt update && sudo apt -y upgrade
sudo apt install -y openjdk-8-jre

# Instalamos Postgresql
cd $HOME
apt install -y postgresql #como root

#Configuramos la base de datos
su postgres
createuser -DRSP bdpacs     #usuario se usa bdpacs pero usuario y  password los que consideren convenientes
psql
ALTER ROLE bdpacs WITH SUPERUSER;
\q
createdb dcm4chee_bdpacs -O admin_bdpacs  #se usa como nombre de la base dcm4chee_bdpacs pero es libre
exit
psql -h localhost dcm4chee_bdpacs admin_bdpacs < $DCM4CHEE_ARC/sql/create-psql.sql           
psql -h localhost dcm4chee_bdpacs admin_bdpacs < $DCM4CHEE_ARC/sql/create-fk-index.sql

# Instalación de openLdap
# berkeleydb
cd /opt/dcm4chee/db-5.0.32/build_unix
../dist/configure
su
make #como SUPERUSER
make install #como SUPERUSER
echo '/usr/local/BerkeleyDB.5.0/lib' | tee --append /etc/ld.so.conf   #como SUPERUSER

cd /opt/dcm4chee/openldap-2.4.47/
sudo ./configure CPPFLAGS="-I/usr/local/BerkeleyDB.5.0/include-D_GNU_SOURCE" LDFLAGS="-L/usr/local/BerkeleyDB.5.0/lib"
sudo make depend
sudo make
sudo make install
sudo cp $DCM4CHEE_ARC/ldap/schema/* /usr/local/etc/openldap/schema/
cd /usr/local/etc/openldap #como SUPERUSER

SUFFIX_ORIG='"dc=my-domain,dc=com"' #como SUPERUSER
SUFFIX_DEST='"dc=dcm4che,dc=org"' #como SUPERUSER
sed -i "s/$SUFFIX_ORIG/$SUFFIX_DEST/g" slapd.conf #como SUPERUSER

ROOTDN_ORIG='"cn=Manager,dc=my-domain,dc=com"' #como SUPERUSER
ROOTDN_DEST='"cn=admin,dc=dcm4che,dc=org"' #como SUPERUSER
sed -i "s/$ROOTDN_ORIG/$ROOTDN_DEST/g" slapd.conf #como SUPERUSER

sed -i '6iinclude        /usr/local/etc/openldap/schema/dicom.schema' slapd.conf              #como SUPERUSER
sed -i '7iinclude        /usr/local/etc/openldap/schema/dcm4che.schema' slapd.conf            #como SUPERUSER
sed -i '8iinclude        /usr/local/etc/openldap/schema/dcm4chee-archive.schema' slapd.conf   #como SUPERUSER

/usr/local/libexec/slapd            #Ejecuta el servidor ldap                                 #como SUPERUSER
ldapsearch -x -b '' -s base'(objectclass=*)'
ldapsearch -x -D "cn=admin,dc=dcm4che,dc=org" -w secret -b "dcm4che,dc=org"

# La contraseña de openLDAP por defecto es: secret     ------hasta aca vamos bien
ldapadd -x -D cn=admin,dc=dcm4che,dc=org -W -f  $DCM4CHEE_ARC/ldap/init-baseDN.ldif      #como SUPERUSER
ldapadd -x -D cn=admin,dc=dcm4che,dc=org -W -f  $DCM4CHEE_ARC/ldap/init-config.ldif      #como SUPERUSER
ldapadd -x -D cn=admin,dc=dcm4che,dc=org -W -f  $DCM4CHEE_ARC/ldap/default-config.ldif   #como SUPERUSER

cp -r $DCM4CHEE_ARC/configuration/dcm4chee-arc $WILDFLY_HOME/standalone/configuration

cd $WILDFLY_HOME/standalone/configuration/
cp standalone-full.xml dcm4chee-arc.xml
IP_ORIG="127.0.0.1"
IP_DEST="0.0.0.0"
sed -i "s/$IP_ORIG/$IP_DEST/g" dcm4chee-arc.xml

cd  $WILDFLY_HOME

# Modulos
unzip $DCM4CHEE_ARC/jboss-modules/dcm4che-jboss-modules-5.13.0.zip
unzip $DCM4CHEE_ARC/jboss-modules/jai_imageio-jboss-modules-1.2-pre-dr-b04.zip
unzip $DCM4CHEE_ARC/jboss-modules/querydsl-jboss-modules-4.1.4-noguava.zip
unzip $DCM4CHEE_ARC/jboss-modules/jclouds-jboss-modules-2.0.2-noguava.zip
unzip $DCM4CHEE_ARC/jboss-modules/ecs-object-client-jboss-modules-3.0.0.zip
unzip $DCM4CHEE_ARC/jboss-modules/jdbc-jboss-modules-1.0.0-psql.zip

PSQL_CONECTOR_ORIG='"postgresql-41.0.3.jar"'   #Corroborar si realmente tiene estos valores antes de modificarlo (cambia segun el caso)
PSQL_CONECTOR_DEST='"postgresql-42.2.5.jar"'
sed -i "s/$PSQL_CONECTOR_ORIG/$PSQL_CONECTOR_DEST/g" $WILDFLY_HOME/modules/org/postgresql/main/module.xml
#Copiar postgresql-42.2.5.jar de la ruta de descarga que estaria en /opt/dcm4chee o $DCM4CHEE_ARC/../postgresql-42.2.5.jar

# Levanta el servidor
$WILDFLY_HOME/bin/standalone.sh -c dcm4chee-arc.xml & #El & es para que quede en segundo plano
#------------------------------------Hasta aca todo bien realizado por alejandro.
$WILDFLY_HOME/bin/jboss-cli.sh -c #Habilita la consola del wildfly

/subsystem=datasources/jdbc-driver=postgresql:add(driver-name=postgresql,driver-module-name=org.postgresql) #Conecta con el driver de la base
data-source add --name=PacsDS --driver-name=postgresql --connection-url=jdbc:postgresql://localhost:5432/dcm4chee_bdpacs_soporte --jndi-name=java:/PacsDS --user-name=admin_bdpacs_soporte --password=4dm1n_p4cs_soporte    #Envia los datos de conexion de la base de datos al servidor  el parametro name deberia ser PacsNombredelEstablecimiento
data-source enable --name=PacsDS #activamos la conexion que acabamos de crear
###Activamos las queue 
jms-queue add --queue-address=StgCmtSCP --entries=java:/jms/queue/StgCmtSCP
jms-queue add --queue-address=MPPSSCU --entries=java:/jms/queue/MPPSSCU
jms-queue add --queue-address=StgCmtSCU --entries=java:/jms/queue/StgCmtSCU
jms-queue add --queue-address=IANSCU --entries=java:/jms/queue/IANSCU
jms-queue add --queue-address=Export1 --entries=java:/jms/queue/Export1
jms-queue add --queue-address=Export2 --entries=java:/jms/queue/Export2
jms-queue add --queue-address=Export3 --entries=java:/jms/queue/Export3
jms-queue add --queue-address=HL7Send --entries=java:/jms/queue/HL7Send
jms-queue add --queue-address=RSClient --entries=java:/jms/queue/RSClient
jms-queue add --queue-address=CMoveSCU --entries=java:/jms/queue/CMoveSCU
#En caso de equivocarse en una se puede usar por ejemplo jms-queue remove --queue-address=CMoveSCU
# o se puede usar $WILDFLY_HOME/bin/jboss-cli.sh -c --file=$DCM4CHEE_ARC/cli/add-jms-queues.cli
####En las versiones superiores a la 10 de Wildfly se debe reajustar los executors
/subsystem=ee/managed-executor-service=default:undefine-attribute(name=hung-task-threshold)
/subsystem=ee/managed-executor-service=default:write-attribute(name=long-running-tasks,value=true)
/subsystem=ee/managed-executor-service=default:write-attribute(name=core-threads,value=2)
/subsystem=ee/managed-executor-service=default:write-attribute(name=max-threads,value=100)
/subsystem=ee/managed-executor-service=default:write-attribute(name=queue-length,value=0)
/subsystem=ee/managed-scheduled-executor-service=default:undefine-attribute(name=hung-task-threshold)
/subsystem=ee/managed-scheduled-executor-service=default:write-attribute(name=long-running-tasks,value=true)
/subsystem=ee/managed-scheduled-executor-service=default:write-attribute(name=core-threads,value=2)

/system-property=dcm4chee-arc.DeviceName:add(value=dcm4che-arc)
#en caso que falle revisar etiqueta   <property name="dcm4chee-arc.DeviceName" value="dcm4chee-arc"/> en archivo $WILDFLY_HOME/standalone/configuration/DCM4Che.xml
 #Deploy
deploy /opt/dcm4chee/dcm4chee/deploy/dcm4chee-arc-ear-5.13.0-psql.ear
#Verificamos 










# TODO: La conexión de Wildfly al servidor de base de datos no se está haciendo
#       revisar los logs.
