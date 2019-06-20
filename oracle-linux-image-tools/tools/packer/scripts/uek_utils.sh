#!/bin/bash
#
# Copyright © 2019 Oracle Corp., Inc.  All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl
#

OS_REV=$(sed s/.*release\ // /etc/redhat-release | sed s/\ .*// | awk -F'.' '{print $1}')

installed_UEK()
{ 
    local version=$(rpm -q kernel-uek --qf "%{VERSION}\n" | sort -u)
    case "${version}" in
        "4.1.12")
            echo UEK4
            ;;
        "4.14.35")
            echo UEK5
            ;;
        *)
            : 
            ;;
    esac

}

# pass UEK version(UEK4,UEK5,default)
match_UEKrepo()
{ 
    local uek_version=$1
    repo_uek=default
    if [ "X${uek_version}" = "Xdefault" ]; then
        # do nothing
        repo_uek=default
    fi
    case "${OS_REV},${uek_version}" in
                "7,UEK4")
                    repo_uek=ol${OS_REV}_UEKR4 
                    ;; 
                "7,UEK5")
                    repo_uek=ol${OS_REV}_UEKR5
                    ;; 
                *)
                    # do nothing
                    repo_uek=default
                    ;;
    esac   
    echo $repo_uek
}

enable_repo()
{
    local repo_file="/etc/yum.repos.d/public-yum-ol${OS_REV}.repo"
    local repo_name=$1 
    [ -f "${repo_file}" ] || return 0
    [ -z "${repo_name}" ] && return 0
    if [ "$(grep "${repo_name}\]" "${repo_file}")" = "[${repo_name}]" ]; then
        line_num=$(grep -n "${repo_name}"\] "${repo_file}" | awk -F':' '{print $1}')
    fi
    [ -z "${line_num}" ] && return 0
    line_end=$((line_num + 5))
    sed -i -e "${line_num},${line_end} s/enabled.*/enabled=1/" "${repo_file}"
    return 0
}

disable_repo()
{
    local repo_file="/etc/yum.repos.d/public-yum-ol${OS_REV}.repo"
    local repo_name=$1
    [ -f "${repo_file}" ] || return 0
    [ -z "${repo_name}" ] && return 0
    if [ "$(grep "${repo_name}\]" "${repo_file}")" = "[${repo_name}]" ]; then
        line_num=$(grep -n "${repo_name}"\] "${repo_file}" | awk -F':' '{print $1}')
    fi
    [ -z "${line_num}" ] && return 0
    num=$((line_num+5))
    sed -i -e "${num} s/enabled.*/enabled=0/" "${repo_file}"
    return 0
}
