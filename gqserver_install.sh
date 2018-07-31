#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "[${red}Error${plain}] This script must be run as root!" && exit 1

cur_dir=$( pwd )

goquiet_init="/etc/init.d/goquiet"
goquiet_config="/etc/goquiet/config.json"
goquiet_centos="https://raw.githubusercontent.com/yiguihai/goquiet/master/goquiet.sh"
goquiet_debian="https://raw.githubusercontent.com/yiguihai/goquiet/master/goquiet-debian.sh"

get_ip(){
    local IP=$( ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | head -n 1 )
    [ -z ${IP} ] && IP=$( wget -qO- -t1 -T2 ipv4.icanhazip.com )
    [ -z ${IP} ] && IP=$( wget -qO- -t1 -T2 ipinfo.io/ip )
    echo ${IP}
}

get_ipv6(){
    local ipv6=$(wget -qO- -t1 -T2 ipv6.icanhazip.com)
    [ -z ${ipv6} ] && return 1 || return 0
}

get_goquiet_ver(){
    goquiet_ver=$(wget --no-check-certificate -qO- https://api.github.com/repos/cbeuw/GoQuiet/releases/latest | grep 'tag_name' | cut -d\" -f4)
    [ -z ${goquiet_ver} ] && echo -e "[${red}Error${plain}] Get goquiet latest version failed" && exit 1
}

is_64bit(){
    if [ `getconf WORD_BIT` = '32' ] && [ `getconf LONG_BIT` = '64' ] ; then
        return 0
    else
        return 1
    fi
}

download(){
    local filename=$(basename $1)
    if [ -f ${1} ]; then
        echo "${filename} [found]"
    else
        echo "${filename} not found, download now..."
        wget --no-check-certificate -c -t3 -T60 -O ${1} ${2}
        if [ $? -ne 0 ]; then
            echo -e "[${red}Error${plain}] Download ${filename} failed."
            exit 1
        fi
    fi
}

download_files() {
    if is_64bit; then
        goquiet_file="gq-server-linux64-$(echo ${goquiet_ver##*v})"
   else
        goquiet_file="gq-server-linux32-$(echo ${goquiet_ver##*v})"
   fi
        goquiet_url="https://github.com/cbeuw/GoQuiet/releases/download/${goquiet_ver}/${goquiet_file}"
   if check_sys packageManager yum; then
        download "${goquiet_init}" "${goquiet_centos}"     
   elif check_sys packageManager apt; then
        download "${goquiet_init}" "${goquiet_debian}"
   fi
        download "${goquiet_file}" "${goquiet_url}"
}

move_file() {
    if [ -d ${cur_dir}/${1} ]; then
        mv -f ${cur_dir}/${1} /usr/local/bin/goquiet
      else
        mv -f ${cur_dir}/goquiet /usr/local/bin/goquiet
    fi
    if [ $? -ne 0 ]; then
        echo -e "[${red}错误提示${plain}] 移动文件 ${1} 失败!"
        exit 1
    fi
        chmod +x /usr/local/bin/goquiet
}

config_goquiet() {
if [ ! -d "$(dirname ${goquiet_config})" ]; then
    mkdir -p $(dirname ${goquiet_config})
fi
cat > ${goquiet_config}<<-EOF
{
	"WebServerAddr":"${goquietaddr}",
	"Key":"${goquietpwd}",
	"FastOpen":false
}
EOF
cat >> ${goquiet_init} <<EOF
remotePort=${goquietport}
localAddr=${ssaddr}:${ssport}
EOF
}

check_sys(){
    local checkType=$1
    local value=$2

    local release=''
    local systemPackage=''

    if [[ -f /etc/redhat-release ]]; then
        release="centos"
        systemPackage="yum"
    elif grep -Eqi "debian" /etc/issue; then
        release="debian"
        systemPackage="apt"
    elif grep -Eqi "ubuntu" /etc/issue; then
        release="ubuntu"
        systemPackage="apt"
    elif grep -Eqi "centos|red hat|redhat" /etc/issue; then
        release="centos"
        systemPackage="yum"
    elif grep -Eqi "debian" /proc/version; then
        release="debian"
        systemPackage="apt"
    elif grep -Eqi "ubuntu" /proc/version; then
        release="ubuntu"
        systemPackage="apt"
    elif grep -Eqi "centos|red hat|redhat" /proc/version; then
        release="centos"
        systemPackage="yum"
    fi

    if [[ "${checkType}" == "sysRelease" ]]; then
        if [ "${value}" == "${release}" ]; then
            return 0
        else
            return 1
        fi
    elif [[ "${checkType}" == "packageManager" ]]; then
        if [ "${value}" == "${systemPackage}" ]; then
            return 0
        else
            return 1
        fi
    fi
}

boot_init() {
    local service_name=$(basename ${1})
if   [ "${2}" == "on" ]; then
    chmod +x ${1}
    if check_sys packageManager yum; then
            chkconfig --add ${service_name}
            chkconfig ${service_name} on
        elif check_sys packageManager apt; then
            update-rc.d -f ${service_name} defaults
     fi
elif [ "${2}" == "off" ]; then
    ${1} stop
    if check_sys packageManager yum; then
        chkconfig --del ${service_name}
    elif check_sys packageManager apt; then
        update-rc.d -f ${service_name} remove
    fi
fi
}

get_char(){
    SAVEDSTTY=$(stty -g)
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}

install_prepare_goquiet_port() {
    echo "请设置一个GeQuiet服务运行端口"
    read -p "(默认: 433):" goquietport
    [ -z "${goquietport}" ] && goquietport="443"
    echo
    echo "监听端口 = ${goquietport}"
    echo
}

install_prepare_ss_addr() {
    echo "请输入Shadowsocks地址"
    read -p "(默认: 127.0.0.1):" ssaddr
    [ -z "${ssaddr}" ] && ssaddr="127.0.0.1"
    echo
    echo "Shadowsocks地址 = ${ssaddr}"
    echo
}

install_prepare_ss_port() {
    echo "请输入Shadowsocks端口"
    read -p "(默认: 80):" ssport
    [ -z "${ssport}" ] && ssport="80"
    echo
    echo "Shadowsocks端口 = ${ssport}"
    echo
}


install_prepare_goquiet_addr() {
    echo "请设置一个重定向服务器(客户端配置中ServerName域名的IP记录)"
    read -p "(默认: 204.79.197.200:443):" goquietaddr
    [ -z "${goquietaddr}" ] && goquietaddr="204.79.197.200:443"
    echo
    echo "重定向服务器 = ${goquietaddr}"
    echo
}

install_prepare_goquiet_pwd() {
    echo "请设置一个GoQuiet密匙"
    read -p "(默认: exampleconftest):" goquietpwd
    [ -z "${goquietpwd}" ] && goquietpwd="exampleconftest"
    echo
    echo "密匙 = ${goquietpwd}"
    echo
}

install_prepare() {
        clear
        install_prepare_goquiet_port
        install_prepare_ss_addr
        install_prepare_ss_port
        install_prepare_goquiet_addr
        install_prepare_goquiet_pwd
        echo
        echo "Press any key to start...or Press Ctrl+C to cancel"
        char=`get_char`
}

install_main(){
    install_goquiet
    echo
    echo "Welcome to visit: https://twitter.com/yiguihai"
    echo "Enjoy it!"
    echo
}

install_completed_goquiet() {
    clear
    ${goquiet_init} start
    echo
    echo -e "Congratulations, ${green}GoQuiet${plain} server install completed!"
    echo -e "Your Server IP        : ${red} $(get_ip) ${plain}"
    echo -e "Your Server Port      : ${red} ${goquietport} ${plain}"
    echo -e "Your Password         : ${red} ${goquietpwd} ${plain}"
}

install_goquiet(){
    install_prepare
    get_goquiet_ver
    download_files
    move_file ${goquiet_file}
    config_goquiet
    boot_init ${goquiet_init} on
    install_completed_goquiet
}

uninstall_goquiet(){
    printf "Are you sure uninstall ${red}GoQuiet${plain}? [y/n]\n"
    read -p "(default: n):" answer
    [ -z ${answer} ] && answer="n"
    if [ "${answer}" == "y" ] || [ "${answer}" == "Y" ]; then
        boot_init ${goquiet_init} off
        rm -fr $(dirname ${goquiet_config})
        rm -f /usr/local/bin/goquiet
        rm -f ${goquiet_init}
        echo -e "[${green}Info${plain}] goquiet uninstall success"
    else
        echo
        echo -e "[${green}Info${plain}] goquiet uninstall cancelled, nothing to do..."
        echo
    fi
}

# Initialization step
action=$1
[ -z $1 ] && action=install
case "${action}" in
    install|uninstall)
        ${action}_goquiet
        ;;
    *)
        echo "Arguments error! [${action}]"
        echo "Usage: $(basename $0) [install|uninstall]"
        ;;
esac
