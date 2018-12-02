#!/bin/bash

set -e

ca_file= #CA key
node_num=1 
ip_file=
ip_param=
use_ip_param=
ip_array=
output_dir=nodes
port_start=30300 
state_type=mpt 
storage_type=LevelDB
conf_path="conf/"
eth_path=
gen_sdk=false
jks_passwd=123456
make_tar=
enable_listen_ip="false"
Download=false
Download_Link=https://github.com/FISCO-BCOS/lab-bcos/raw/dev/bin/fisco-bcos

help() {
    echo $1
    cat << EOF
Usage:
    -l <IP list>                [Required] "ip1:nodeNum1,ip2:nodeNum2" e.g:"192.168.0.1:2,192.168.0.2:3"
    -f <IP list file>           [Optional] "split by line, "ip:nodeNum"
    -i <enable public listen ip>          Default 127.0.0.1
    -e <FISCO-BCOS binary path> Default download from GitHub
    -o <Output Dir>             Default ./nodes/
    -p <Start Port>             Default 30300
    -d <JKS passwd>             Default not generate jks files, if set use param as jks passwd
    -s <State type>             Default mpt. if set -s, use storage 
    -t <Cert config file>       Default auto generate
    -z <Generate tar packet>    Default no
    -h Help
e.g 
    build_chain.sh -l "192.168.0.1:2,192.168.0.2:2"
EOF

exit 0
}

fail_message()
{
    echo $1
    false
}

EXIT_CODE=-1

check_env() {
    version=`openssl version 2>&1 | grep 1.0.2`
    [ -z "$version" ] && {
        echo "please install openssl 1.0.2k-fips!"
        #echo "please install openssl 1.0.2 series!"
        #echo "download openssl from https://www.openssl.org."
        echo "use \"openssl version\" command to check."
        exit $EXIT_CODE
    }
}
# check_env

check_java() {
    ver=`java -version 2>&1 | grep version | grep 1.8`
    tm=`java -version 2>&1 | grep "Java(TM)"`
    [ -z "$ver" -o -z "$tm" ] && {
        echo "please install java Java(TM) 1.8 series!"
        echo "use \"java -version\" command to check."
        exit $EXIT_CODE
    }

    which keytool >/dev/null 2>&1
    [ $? != 0 ] && {
        echo "keytool command not exists!"
        exit $EXIT_CODE
    }
}

usage() {
printf "%s\n" \
"usage command gen_chain_cert chaindir|
              gen_agency_cert chaindir agencydir|
              gen_node_cert agencydir nodedir|
              gen_sdk_cert agencydir sdkdir|
              help"
}

getname() {
    local name="$1"
    if [ -z "$name" ]; then
        return 0
    fi
    [[ "$name" =~ ^.*/$ ]] && {
        name="${name%/*}"
    }
    name="${name##*/}"
    echo "$name"
}

check_name() {
    local name="$1"
    local value="$2"
    [[ "$value" =~ ^[a-zA-Z0-9._-]+$ ]] || {
        echo "$name name [$value] invalid, it should match regex: ^[a-zA-Z0-9._-]+\$"
        exit $EXIT_CODE
    }
}

file_must_exists() {
    if [ ! -f "$1" ]; then
        echo "$1 file does not exist, please check!"
        exit $EXIT_CODE
    fi
}

dir_must_exists() {
    if [ ! -d "$1" ]; then
        echo "$1 DIR does not exist, please check!"
        exit $EXIT_CODE
    fi
}

dir_must_not_exists() {
    if [ -e "$1" ]; then
        echo "$1 DIR exists, please clean old DIR!"
        exit $EXIT_CODE
    fi
}

gen_chain_cert() {
    path="$2"
    name=`getname "$path"`
    echo "$path --- $name"
    dir_must_not_exists "$path"
    check_name chain "$name"
    
    chaindir=$path
    mkdir -p $chaindir
    openssl genrsa -out $chaindir/ca.key 2048
    openssl req -new -x509 -days 3650 -subj "/CN=$name/O=fiscobcos/OU=chain" -key $chaindir/ca.key -out $chaindir/ca.crt
    cp cert.cnf $chaindir

    if [ $? -eq 0 ]; then
        echo "build chain ca succussful!"
    else
        echo "please input at least Common Name!"
    fi
}

gen_agency_cert() {
    chain="$2"
    agencypath="$3"
    name=`getname "$agencypath"`

    dir_must_exists "$chain"
    file_must_exists "$chain/ca.key"
    check_name agency "$name"
    agencydir=$agencypath
    dir_must_not_exists "$agencydir"
    mkdir -p $agencydir

    openssl genrsa -out $agencydir/agency.key 2048
    openssl req -new -sha256 -subj "/CN=$name/O=fiscobcos/OU=agency" -key $agencydir/agency.key -config $chain/cert.cnf -out $agencydir/agency.csr
    openssl x509 -req -days 3650 -sha256 -CA $chain/ca.crt -CAkey $chain/ca.key -CAcreateserial\
        -in $agencydir/agency.csr -out $agencydir/agency.crt  -extensions v4_req -extfile $chain/cert.cnf
    
    cp $chain/ca.crt $chain/cert.cnf $agencydir/
    cp $chain/ca.crt $agencydir/ca-agency.crt
    more $agencydir/agency.crt | cat >>$agencydir/ca-agency.crt
    rm -f $agencydir/agency.csr

    echo "build $name agency cert successful!"
}

gen_cert_secp256k1() {
    capath="$1"
    certpath="$2"
    name="$3"
    type="$4"
    openssl ecparam -out $certpath/${type}.param -name secp256k1
    openssl genpkey -paramfile $certpath/${type}.param -out $certpath/${type}.key
    openssl pkey -in $certpath/${type}.key -pubout -out $certpath/${type}.pubkey
    openssl req -new -sha256 -subj "/CN=${name}/O=fiscobcos/OU=${type}" -key $certpath/${type}.key -config $capath/cert.cnf -out $certpath/${type}.csr
    openssl x509 -req -days 3650 -sha256 -in $certpath/${type}.csr -CAkey $capath/agency.key -CA $capath/agency.crt\
        -force_pubkey $certpath/${type}.pubkey -out $certpath/${type}.crt -CAcreateserial -extensions v3_req -extfile $capath/cert.cnf
    openssl ec -in $certpath/${type}.key -outform DER | tail -c +8 | head -c 32 | xxd -p -c 32 | cat >$certpath/${type}.private
    rm -f $certpath/${type}.csr
}

gen_node_cert() {
    if [ "" = "`openssl ecparam -list_curves 2>&1 | grep secp256k1`" ]; then
        echo "openssl don't support secp256k1, please upgrade openssl!"
        exit $EXIT_CODE
    fi

    agpath="$2"
    agency=`getname "$agpath"`
    ndpath="$3"
    node=`getname "$ndpath"`
    dir_must_exists "$agpath"
    file_must_exists "$agpath/agency.key"
    check_name agency "$agency"
    dir_must_not_exists "$ndpath"
    check_name node "$node"

    mkdir -p $ndpath
    gen_cert_secp256k1 "$agpath" "$ndpath" "$node" node
    #nodeid is pubkey
    openssl ec -in $ndpath/node.key -text -noout | sed -n '7,11p' | tr -d ": \n" | awk '{print substr($0,3);}' | cat >$ndpath/node.nodeid
    openssl x509 -serial -noout -in $ndpath/node.crt | awk -F= '{print $2}' | cat >$ndpath/node.serial
    cp $agpath/ca.crt $agpath/agency.crt $ndpath

    cd $ndpath
    nodeid=`cat node.nodeid | head`
    serial=`cat node.serial | head`
    cat >node.json <<EOF
{
 "id":"$nodeid",
 "name":"$node",
 "agency":"$agency",
 "caHash":"$serial"
}
EOF
    cat >node.ca <<EOF
{
 "serial":"$serial",
 "pubkey":"$nodeid",
 "name":"$node"

EOF

    echo "build $node node cert successful!"
}

read_password() {
    read -se -p "Enter password for keystore:" pass1
    echo
    read -se -p "Verify password for keystore:" pass2
    echo
    [[ "$pass1" =~ ^[a-zA-Z0-9._-]{6,}$ ]] || {
        echo "password invalid, at least 6 digits, should match regex: ^[a-zA-Z0-9._-]{6,}\$"
        exit $EXIT_CODE
    }
    [ "$pass1" != "$pass2" ] && {
        echo "Verify password failure!"
        exit $EXIT_CODE
    }
    jks_passwd=$pass1
}

gen_sdk_cert() {
    check_java

    agency="$2"
    sdkpath="$3"
    sdk=`getname "$sdkpath"`
    dir_must_exists "$agency"
    file_must_exists "$agency/agency.key"
    dir_must_not_exists "$sdkpath"
    check_name sdk "$sdk"

    mkdir -p $sdkpath
    gen_cert_secp256k1 "$agency" "$sdkpath" "$sdk" sdk
    cp $agency/ca-agency.crt $sdkpath/ca.crt
    
    read_password
    openssl pkcs12 -export -name client -passout "pass:$jks_passwd" -in $sdkpath/sdk.crt -inkey $sdkpath/sdk.key -out $sdkpath/keystore.p12
    keytool -importkeystore -srckeystore $sdkpath/keystore.p12 -srcstoretype pkcs12 -srcstorepass $jks_passwd\
        -destkeystore $sdkpath/client.keystore -deststoretype jks -deststorepass $jks_passwd -alias client 2>/dev/null 

    echo "build $sdk sdk cert successful!"
}

generate_config_ini()
{
    local output=$1
    if [ "${enable_listen_ip}" == "true" ];then
        listen_ip=$2
    else
        listen_ip="127.0.0.1"
    fi
    cat << EOF > ${output}
[rpc]
    ;rpc listen ip
    listen_ip=${listen_ip}
    ;channelserver listen port
    listen_port=$(( port_start + 1 + index * 4 ))
    ;rpc listen port
    http_listen_port=$(( port_start + 2 + index * 4 ))
    console_port=$(( port_start + 3 + index * 4 ))
[p2p]
    ;p2p listen ip
    listen_ip=0.0.0.0
    ;p2p listen port
    listen_port=$(( port_start + index * 4 ))
    ;nodes to connect
    $ip_list

;group configurations
;if need add a new group, eg. group2, can add the following configuration:
;group_config.2=conf/group.2.ini
;group.2.ini can be populated from group.1.ini
;WARNING: group 0 is forbided
[group]
    ;group_config.1=conf/group.1.ini

;certificate configuration
[secure]
    ;directory the certificates located in
    data_path=conf/
    ;the node private key file
    key=node.key
    ;the node certificate file
    cert=node.crt
    ;the ca certificate file
    ca_cert=ca.crt

;log configurations
[log]
    ;the directory of the log
    LOG_PATH=./log
    GLOBAL-ENABLED=true
    GLOBAL-FORMAT=%level|%datetime{%Y-%M-%d %H:%m:%s:%g}|%msg
    GLOBAL-MILLISECONDS_WIDTH=3
    GLOBAL-PERFORMANCE_TRACKING=false
    GLOBAL-MAX_LOG_FILE_SIZE=209715200
    GLOBAL-LOG_FLUSH_THRESHOLD=100

    ;log level configuration, enable(true)/disable(false) corresponding level log
    INFO-ENABLED=true
    WARNING-ENABLED=true
    ERROR-ENABLED=true
    DEBUG-ENABLED=false
    TRACE-ENABLED=false
    FATAL-ENABLED=false
    VERBOSE-ENABLED=false
EOF
}

generate_group_ini()
{
    local output=$1
    cat << EOF > ${output} 
;consensus configuration
[consensus]
;consensus type: only support PBFT now
consensusType=pbft
;the max number of transactions of a block
maxTransNum=1000
;the node id of leaders
$nodeid_list

;sync period time
[sync]
idleWaitMs=200

[storage]
;storage db type, now support leveldb 
type=${storage_type}
dbpath=data

[state]
;state type, now support mpt/storage
type=${state_type}



;genesis configuration
[genesis]
;used to mark the genesis block of this group
;mark=${group_id}

;txpool limit
[txPool]
limit=1000
EOF
}

generate_cert_conf()
{
    local output=$1
    cat << EOF > ${output} 
[ca]
default_ca=default_ca
[default_ca]
default_days = 365
default_md = sha256

[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
[req_distinguished_name]
countryName = CN
countryName_default = CN
stateOrProvinceName = State or Province Name (full name)
stateOrProvinceName_default =GuangDong
localityName = Locality Name (eg, city)
localityName_default = ShenZhen
organizationalUnitName = Organizational Unit Name (eg, section)
organizationalUnitName_default = fiscobcos
commonName =  Organizational  commonName (eg, fiscobcos)
commonName_default = fiscobcos
commonName_max = 64

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment

[ v4_req ]
basicConstraints = CA:TRUE

EOF
}

generate_node_scripts()
{
    local output=$1
    cat << EOF > "$output/start.sh"
#!/bin/bash
SHELL_FOLDER=\$(cd "\$(dirname "\$0")";pwd)
fisco_bcos=\${SHELL_FOLDER}/fisco-bcos
cd \${SHELL_FOLDER}
nohup setsid \${fisco_bcos} -c config.ini&
EOF

    cat << EOF > "$output/stop.sh"
#!/bin/bash
SHELL_FOLDER=\$(cd "\$(dirname "\$0")";pwd)
fisco_bcos=\${SHELL_FOLDER}/fisco-bcos
weth_pid=\`ps aux|grep "\${fisco_bcos}"|grep -v grep|awk '{print \$2}'\`
kill \${weth_pid}
EOF
    cat << EOF > "$output/start_consensus.sh"
#!/bin/bash
SHELL_FOLDER=\$(cd "\$(dirname "\$0")";pwd)
consensus=\${SHELL_FOLDER}/mini-consensus
cd \${SHELL_FOLDER}
nohup setsid \${consensus} -t \${1}&
EOF

    cat << EOF > "$output/stop_consensus.sh"
#!/bin/bash
SHELL_FOLDER=\$(cd "\$(dirname "\$0")";pwd)
consensus=\${SHELL_FOLDER}/mini-consensus
weth_pid=\`ps aux|grep "\${consensus}"|grep -v grep|awk '{print \$2}'\`
kill \${weth_pid}
EOF
    chmod +x "$output/start.sh"
    chmod +x "$output/stop.sh"
    chmod +x "$output/start_consensus.sh"
    chmod +x "$output/stop_consensus.sh"
}

genTransTest()
{
    local file=${output_dir}"/transTest.sh"
    cat << EOF > "${file}"
#!bin/bash
curl -X POST --data '{"jsonrpc":"2.0","method":"sendRawTransaction","params":[1, "f8ef9f65f0d06e39dc3c08e32ac10a5070858962bc6c0f5760baca823f2d5582d03f85174876e7ff8609184e729fff82020394d6f1a71052366dbae2f7ab2d5d5845e77965cf0d80b86448f85bce000000000000000000000000000000000000000000000000000000000000001bf5bd8a9e7ba8b936ea704292ff4aaa5797bf671fdc8526dcd159f23c1f5a05f44e9fa862834dc7cb4541558f2b4961dc39eaaf0af7f7395028658d0e01b86a371ca00b2b3fabd8598fefdda4efdb54f626367fc68e1735a8047f0f1c4f840255ca1ea0512500bc29f4cfe18ee1c88683006d73e56c934100b8abf4d2334560e1d2f75e"],"id":83}' http://127.0.0.1:$(( port_start + 2))
EOF
}

main()
{
while getopts "f:l:o:p:e:t:idszh" option;do
    case $option in
    f) ip_file=$OPTARG
       use_ip_param="false"
    ;;
    l) ip_param=$OPTARG
       use_ip_param="true"
    ;;
    o) output_dir=$OPTARG;;
    i) enable_listen_ip="true";;
    p) port_start=$OPTARG;;
    e) eth_path=$OPTARG;;
    d) gen_sdk="true"
       [ ! -z $OPTARG ] && jks_passwd=$OPTARG
       [[ "$jks_passwd" =~ ^[a-zA-Z0-9._-]{6,}$ ]] || {
        echo "password invalid, at least 6 digits, should match regex: ^[a-zA-Z0-9._-]{6,}\$"
        exit $EXIT_CODE
    }
    ;;
    s) state_type=storage;;
    t) CertConfig=$OPTARG;;
    z) make_tar="yes";;
    h) help;;
    esac
done

output_dir="`pwd`/${output_dir}"
[ -z $use_ip_param ] && help 'ERROR: Please set -l or -f option.'
if [ "${use_ip_param}" = "true" ];then
    ip_array=(${ip_param//,/ })
elif [ "${use_ip_param}" = "false" ];then
    n=0
    while read line;do
        ip_array[n]=$line
        ((++n))
    done < $ip_file
else 
    help 
fi

if [ -z ${eth_path} ];then
    eth_path=${output_dir}/fisco-bcos
    Download=true
fi

[ -d "$output_dir" ] || mkdir -p "$output_dir"

if [ "${Download}" = "true" ];then
    echo "Downloading fisco-bcos binary..." 
    curl -Lo ${eth_path} ${Download_Link}
    chmod a+x ${eth_path}
fi

if [ -z ${CertConfig} ] || [ ! -e ${CertConfig} ];then
    # CertConfig="$output_dir/cert.cnf"
    generate_cert_conf "cert.cnf"
else 
   cp ${CertConfig} .
fi

# prepare CA
if [ ! -e "$ca_file" ]; then
    echo "Generating CA key..."
    dir_must_not_exists $output_dir/chain
    gen_chain_cert "" $output_dir/chain >$output_dir/build.log 2>&1 || fail_message "openssl error!"  #生成secp256k1算法的CA密钥
    mv $output_dir/chain $output_dir/cert
    gen_agency_cert "" $output_dir/cert $output_dir/cert/agency >$output_dir/build.log 2>&1
    ca_file="$output_dir/cert/ca.key"
fi

echo "Generating node key ..."
nodeid_list=""
ip_list=""
index=0
for line in ${ip_array[*]};do
    ip=${line%:*}
    num=${line#*:}
    [ "$num" = "$ip" -o -z "${num}" ] && num=${node_num}
    for ((i=0;i<num;++i));do
        # echo "Generating IP:${ip} ID:${index} key files..."
        node_dir="$output_dir/node_${ip}_${index}"
        [ -d "$node_dir" ] && echo "$node_dir exist! Please delete!" && exit 1
        
        while :
        do
            gen_node_cert "" ${output_dir}/cert/agency $node_dir >$output_dir/build.log 2>&1
            mkdir -p ${conf_path}/
            rm node.json node.param node.private node.ca node.pubkey
            mv *.* ${conf_path}/
            cd $output_dir
            privateKey=`openssl ec -in "$node_dir/${conf_path}/node.key" -text 2> /dev/null| sed -n '3,5p' | sed 's/://g'| tr "\n" " "|sed 's/ //g'`
            len=${#privateKey}
            head2=${privateKey:0:2}
            if [ "64" == "${len}" ] && [ "00" != "$head2" ];then
                break;
            fi
            rm -rf ${node_dir}
        done
        cat ${output_dir}/cert/agency/agency.crt >> $node_dir/${conf_path}/node.crt
        cat ${output_dir}/cert/ca.crt >> $node_dir/${conf_path}/node.crt
        if [ "${gen_sdk}" = "true" ];then
            mkdir -p $node_dir/sdk/
            # read_password
            openssl pkcs12 -export -name client -passout "pass:$jks_passwd" -in "$node_dir/${conf_path}/node.crt" -inkey "$node_dir/${conf_path}/node.key" -out "$node_dir/sdk/keystore.p12"
		    keytool -importkeystore  -srckeystore "$node_dir/sdk/keystore.p12" -srcstoretype pkcs12 -srcstorepass $jks_passwd -alias client -destkeystore "$node_dir/sdk/client.keystore" -deststoretype jks -deststorepass $jks_passwd >> /dev/null 2>&1 || fail_message "java keytool error!" 
            #copy ca.crt
            cp ${output_dir}/cert/agency/ca.crt $node_dir/sdk/
            # gen_sdk_cert ${output_dir}/cert/agency $node_dir
            # mv $node_dir/* $node_dir/sdk/
        fi
        nodeid=$(openssl ec -in "$node_dir/${conf_path}/node.key" -text 2> /dev/null | perl -ne '$. > 6 and $. < 12 and ~s/[\n:\s]//g and print' | perl -ne 'print substr($_, 2)."\n"')
        nodeid_list=$"${nodeid_list}node.${index}=$nodeid
    "
        ip_list=$"${ip_list}node.${index}="${ip}:$(( port_start + index * 4 ))"
    "
        ((++index))
    done
done 
cd ..
echo "#!/bin/bash" > "$output_dir/start_all.sh"
echo "#!/bin/bash" > "$output_dir/stop_all.sh"
echo "#!/bin/bash" > "$output_dir/replace_all.sh"
echo "#!/bin/bash" > "$output_dir/start_all_consensus.sh"
echo "#!/bin/bash" > "$output_dir/stop_all_consensus.sh"

echo "SHELL_FOLDER=\$(cd \"\$(dirname \"\$0\")\";pwd)" >> "$output_dir/start_all.sh"
echo "SHELL_FOLDER=\$(cd \"\$(dirname \"\$0\")\";pwd)" >> "$output_dir/stop_all.sh"
echo "SHELL_FOLDER=\$(cd \"\$(dirname \"\$0\")\";pwd)" >> "$output_dir/replace_all.sh"
echo "SHELL_FOLDER=\$(cd \"\$(dirname \"\$0\")\";pwd)" >> "$output_dir/start_all_consensus.sh"
echo "SHELL_FOLDER=\$(cd \"\$(dirname \"\$0\")\";pwd)" >> "$output_dir/stop_all_consensus.sh"
echo "Generating node configuration..."

#Generate node config files
index=0
for line in ${ip_array[*]};do
    ip=${line%:*}
    num=${line#*:}
    [ "$num" = "$ip" -o -z "${num}" ] && num=${node_num}
    for ((i=0;i<num;++i));do
        echo "Generating IP:${ip} ID:${index} files..."
        node_dir="$output_dir/node_${ip}_${index}"
        generate_config_ini "$node_dir/config.ini" "${ip}"
        generate_group_ini "$node_dir/${conf_path}/group.1.ini"
        generate_node_scripts "$node_dir"
        cp "$eth_path" "$node_dir/fisco-bcos"
        echo "bash \${SHELL_FOLDER}/node_${ip}_${index}/start.sh" >> "$output_dir/start_all.sh"
        echo "bash \${SHELL_FOLDER}/node_${ip}_${index}/stop.sh" >> "$output_dir/stop_all.sh"
        echo "cp \${1} \${SHELL_FOLDER}/node_${ip}_${index}/" >> "$output_dir/replace_all.sh"
        echo "\${SHELL_FOLDER}/node_${ip}_${index}/start_consensus.sh \${1}" >> "$output_dir/start_all_consensus.sh"
        echo "\${1} \${SHELL_FOLDER}/node_${ip}_${index}/stop_consensus.sh" >> "$output_dir/stop_all_consensus.sh"
        ((++index))
        [ -n "$make_tar" ] && tar zcf "${node_dir}.tar.gz" "$node_dir"
    done
    chmod +x "$output_dir/start_all.sh"
    chmod +x "$output_dir/stop_all.sh"
    chmod +x "$output_dir/replace_all.sh"
    chmod +x "$output_dir/start_all_consensus.sh"
    chmod +x "$output_dir/stop_all_consensus.sh"
done 
#rm $output_dir/build.log cert.cnf
genTransTest
echo "=========================================="
echo "FISCO-BCOS Path : $eth_path"
[ ! -z $ip_file ] && echo "IP List File    : $ip_file"
[ ! -z $ip_param ] && echo "IP List Param   : $ip_param"
echo "Start Port      : $port_start"
echo "Output Dir      : $output_dir"
echo "CA Key Path     : $ca_file"
echo "=========================================="
echo "All completed. Files in $output_dir"
}

main $@
