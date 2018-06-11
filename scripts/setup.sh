#!/bin/bash 

# 'https://drive.google.com/file/d/1alJev7sV-5tRcc0bi-W4NODGOab70Jos/view?usp=sharing' => id: 1alJev7sV-5tRcc0bi-W4NODGOab70Jos
linkTarGz="https://docs.google.com/uc?export=download&id=${GOOGLE_DRIVE_ID}"
dbToRestore="${DB_TO_RESTORE}"

mongodb1=`getent hosts ${MONGO1} | awk '{ print $1 }'`
mongodb2=`getent hosts ${MONGO2} | awk '{ print $1 }'`
mongodb3=`getent hosts ${MONGO3} | awk '{ print $1 }'`

port=${PORT:-27017}

function waitMongo {
    echo "Aguardando banco subir..."
    until mongo --host ${mongodb1}:${port} --eval 'quit(db.runCommand({ ping: 1 }).ok ? 0 : 2)' &>/dev/null; do
      printf '.'
      sleep 1
    done

    echo "SUBIU!"
}

function replicaSetConfig {
    echo "Verificando se deve configurar o Replica Set..."
    currentRsName=`mongo --host ${mongodb1}:${port} --eval '(rs.config() || {})._id' --quiet`
    if [ "$currentRsName" == "$RS" ]; then 
        echo 'Pulando config do Replica Set'; 
    else
        echo 'Configurando Replica Set...'; 
        mongo --host ${mongodb1}:${port} <<EOF
           var cfg = {
                "_id": "${RS}",
                "members": [
                    {
                        "_id": 0,
                        "host": "${mongodb1}:${port}"
                    },
                    {
                        "_id": 1,
                        "host": "${mongodb2}:${port}"
                    },
                    {
                        "_id": 2,
                        "host": "${mongodb3}:${port}"
                    }
                ]
            };
            rs.initiate(cfg, { force: true });
            rs.reconfig(cfg, { force: true });
EOF
    fi
}

function waitPrimary {
    echo "Esperando o primary..."
    waiting=`mongo "mongodb://${mongodb1},${mongodb2},${mongodb3}/?replicaSet=${RS}" --eval 'db.test.count()' --quiet`
    echo "$waiting" | grep -q 'No primary detected for set'
    while [[ $? == 0 ]] ; do
        sleep 2
        waiting=`mongo "mongodb://${mongodb1},${mongodb2},${mongodb3}/?replicaSet=${RS}" --eval 'db.test.count()' --quiet`
        echo $waiting | grep -q 'No primary detected for set'
    done
}

function restore {
    echo 'Iniciando restore...'; 

    apt-get update
    apt-get install wget -y

    wget --no-check-certificate "$linkTarGz" -O $dbToRestore.tar.gz
    tar -xzvf $dbToRestore.tar.gz

    mongorestore --host "${RS}/${mongodb1},${mongodb2},${mongodb3}" $dbToRestore/ --db $dbToRestore
}

function checkRestore {
    echo "Verificando se deve fazer restore..."
    testRestore=`mongo "mongodb://${mongodb1},${mongodb2},${mongodb3}/?replicaSet=${RS}" --eval 'db.adminCommand( { listDatabases: 1 } )' --quiet`
    echo "$testRestore" | grep -q "name\" : \"$dbToRestore\""
    if [[ $? == 0 ]]; then 
        echo 'Pulando restore'; 

    else
        restore
    fi
}

waitMongo
replicaSetConfig
waitPrimary
if [ "${CHECK_RESTORE}" == true ]; then
    checkRestore
fi

echo "TUDO CERTO!"

# mongodump --host "WOLOLO-DB/172.18.0.3:27017,172.18.0.2:27017,172.18.0.4:27017" -d uhul

# apt-get update
# apt-get install wget -y
# wget --no-check-certificate "https://docs.google.com/uc?export=download&id=1alJev7sV-5tRcc0bi-W4NODGOab70Jos" -O uhul.tar.gz
# tar -xzvf uhul.tar.gz

# mongorestore --host "WOLOLO-DB/172.18.0.3:27017,172.18.0.2:27017,172.18.0.4:27017" uhul/ --db uhul

# uhul=`mongo --host "WOLOLO-DB/172.18.0.3:27017,172.18.0.2:27017,172.18.0.4:27017" --eval 'db.adminCommand( { listDatabases: 1 } )' --quiet`
# echo "$uhul" | grep "name\" : \"uhul\""