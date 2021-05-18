#!/bin/sh
#
# check_mem v. 1.4
#
# Nagios/Icinga script to check memory usage on FreeBSD.
# No need perl! :) Work on clean install FreeBSD.
# Tested on FreeBSD 10
#
# Copyrigth (c) 2015 "OPTERIS" Michal Krowicki
#
# https://krowicki.pl https//www.opteris.pl
#
# TODO:
# - check: mem and/or committed and/or swap
# - warn and crit as real values
#
 
print_help() {
    echo "Wrong command: $@"
    echo "Usage:"
    echo "-w Memory Warning level as a percentage"
    echo "-c Memory Critical level as a percentage"
    echo "[-W] Committed Warning level as a percentage"
    echo "[-C] Committed Critical level as a percentage"
    echo "[-s] Swap Warning level as a percentage"
    echo "[-S] Swap Critical level as a percentage"
    echo "[-u] Units: k(iloB) M(egaB) G(igaB). Default 'M'"
    echo "If not defined in optional args [], defaults sets to 100"
    exit 3
}
 
while test -n "$1"; do
    case "$1" in
        --help|-h)
            print_help
            exit 3
            ;;
        -w)
            mem_warn_lvl=$2
            shift
            ;;
        -c)
            mem_crit_lvl=$2
            shift
            ;;
        -W)
            committed_warn_lvl=$2
            shift
            ;;
        -C)
            committed_crit_lvl=$2
            shift
            ;;
        -s)
            swap_warn_lvl=$2
            shift
            ;;
        -S)
            swap_crit_lvl=$2
            shift
            ;;
        -u)
            unit=$2
            shift
            ;;
        *)
            echo "Unknown Argument: $1"
            print_help
            exit 3
            ;;
    esac
    shift
done
 
if [ "$mem_warn_lvl" == "" ]; then
    echo "No Memory Warning Level Specified"
    print_help
    exit 3;
fi
 
if [ "$mem_crit_lvl" == "" ]; then
    echo "No Memory Critical Level Specified"
    print_help
    exit 3;
fi
 
if [ "$committed_warn_lvl" == "" ]; then
    committed_warn_lvl=100
fi
 
if [ "$committed_crit_lvl" == "" ]; then
    committed_crit_lvl=100
fi
 
if [ "$swap_warn_lvl" == "" ]; then
    swap_warn_lvl=100
fi
 
if [ "$swap_crit_lvl" == "" ]; then
    swap_crit_lvl=100
fi
 
if [ "$unit" == "" ]; then
    unit="M"
fi
 
#--------------------------------------------------------------------------------------------------------------------
# REAL MEMORY
#--------------------------------------------------------------------------------------------------------------------
 
sysctl_out=`sysctl hw.pagesize hw.physmem vm.stats.vm.v_inactive_count vm.stats.vm.v_cache_count vm.stats.vm.v_free_count | tr -d "[:alpha:]_. "`
 
pagesize=`echo $sysctl_out | cut -d":" -f2`
mem_total=`echo $sysctl_out | cut -d":" -f3`
 
mem_inactive=`echo $sysctl_out | cut -d":" -f4`
mem_inactive=`expr $mem_inactive \* $pagesize`
 
mem_cache=`echo $sysctl_out | cut -d":" -f5`
mem_cache=`expr $mem_cache \* $pagesize`
 
mem_free=`echo $sysctl_out | cut -d":" -f6`
mem_free=`expr $mem_free \* $pagesize`
 
#mem_avail=`expr $mem_inactive \+ $mem_cache \+ $mem_free`
mem_avail=$mem_free
#mem_avail=$mem_free
 
mem_used=`expr $mem_total \- $mem_avail`
 
#--------------------------------------------------------------------------------------------------------------------
# SWAP
#--------------------------------------------------------------------------------------------------------------------
 
swapctl_out=`swapctl -lsk | grep Total | tr -s " "`
 
swap_total=`echo $swapctl_out | cut -d" " -f2`
swap_total=`expr $swap_total \* 1024`
 
swap_used=`echo $swapctl_out | cut -d" " -f3`
swap_used=`expr $swap_used \* 1024`
 
swap_free=`expr $swap_total \- $swap_used`
 
#--------------------------------------------------------------------------------------------------------------------
# COMMITTED
#--------------------------------------------------------------------------------------------------------------------
 
committed_total=`expr $mem_total \+ $swap_total`
committed_used=`expr $mem_used \+ $swap_used`
committed_free=`expr $committed_total \- $committed_used`
 
conv_units()
{
 
    if [ "$1" -ne 0 ]; then
        case $unit in
            k)
                printf "%0.2f" $(echo $1 / 1024 | bc -l)
            ;;
            M)
                printf "%0.2f" $(echo $1 / 1024 / 1024 | bc -l)
            ;;
            G)
                printf "%0.2f" $(echo $1 / 1024 / 1024 / 1024 | bc -l)
            ;;
        esac
    else
        printf "0.00"
    fi
 
    if [ "$2" != "n" ]; then
        echo "${unit}B"
    fi
}
 
conv_pct()
{
    while true; do
        case $2 in
        n)
            v=""
        ;;
        *)
            case $2 in
            P)
                if [ "$1" -ne 0 ]; then
                    printf "%0.0f" $(echo "100 * $1 / $3" | bc -l)
                else
                    printf "0"
                fi
                v="%"
            ;;
            p)
                if [ "$1" -ne 0 ]; then
                    printf "%0.0f" $(echo "$1 / 100 * $3" | bc -l)
                else
                    printf "0"
                fi
 
                v="%"
            ;;
            esac
        ;;
        esac
        shift || break
    done
    echo "$v"
 
}
 
res_mem=$(conv_pct $mem_used P $mem_total n)
res_committed=$(conv_pct $committed_used P $committed_total n)
res_swap=$(conv_pct $swap_used P $swap_total n)
 
if [ "$res_mem" -lt "$mem_warn_lvl" ] && [ "$res_committed" -lt "$committed_warn_lvl" ] && [ "$res_swap" -lt "$swap_warn_lvl" ]; then
    stat_msg="OK:"
    exit_status=0;
else
    if [ "$res_mem" -gt "$mem_crit_lvl" ] || [ "$res_committed" -gt "$committed_crit_lvl" ] || [ "$res_swap" -gt "$swap_crit_lvl" ]; then
        stat_msg="CRITICAL: "
        exit_status=2;
    else
        if [ "$res_mem" -ge "$mem_warn_lvl" ] && [ "$res_mem" -le "$mem_crit_lvl" ]; then
            stat_msg="WARNING: "
            exit_status=1;
 
        elif [ "$res_committed" -ge "$committed_warn_lvl" ] && [ "$res_committed" -le "$committed_crit_lvl" ]; then
            stat_msg="WARNING: "
            exit_status=1;
 
        elif [ "$res_swap" -ge "$swap_warn_lvl" ] && [ "$res_swap" -le "$swap_crit_lvl" ]; then
            stat_msg="WARNING: "
            exit_status=1;
        else
            stat_msg="UNKNOWN: "
            exit_status=3;
 
        fi
    fi
fi
 
echo "$stat_msg PHYSICAL : Total: $(conv_units $mem_total) - Used: $(conv_units $mem_used) ($(conv_pct $mem_used P $mem_total)) - Free: $(conv_units $mem_avail) ($(conv_pct $mem_avail P $mem_total)) \
SWAP     : Total: $(conv_units $swap_total) - Used: $(conv_units $swap_used) ($(conv_pct $swap_used P $swap_total)) - Free: $(conv_units $swap_free) ($(conv_pct $swap_free P $swap_total)) \
COMMITTED: Total: $(conv_units $committed_total) - Used: $(conv_units $committed_used) ($(conv_pct $committed_used P $committed_total)) - Free: $(conv_units $committed_free) ($(conv_pct $committed_free P $committed_total)) \
|'physical'=$(conv_units $mem_used);$(conv_units $(conv_pct $mem_warn_lvl p $mem_total n) n);$(conv_units $(conv_pct $mem_crit_lvl p $mem_total n) n);0;$(conv_units $mem_total n) \
'physical %'=$(conv_pct $mem_used P $mem_total);$mem_warn_lvl;$mem_crit_lvl;0;100 \
'swap'=$(conv_units $swap_used);$(conv_units $(conv_pct $swap_warn_lvl p $swap_total n) n);$(conv_units $(conv_pct $swap_crit_lvl p $swap_total n) n);0;$(conv_units $swap_total n) \
'swap %'=$(conv_pct $swap_used P $swap_total);$swap_warn_lvl;$swap_crit_lvl;0;100 \
'committed'=$(conv_units $committed_used);$(conv_units $(conv_pct $committed_warn_lvl p $committed_total n) n);$(conv_units $(conv_pct $committed_crit_lvl p $committed_total n) n);0;$(conv_units $committed_total n) \
'committed %'=$(conv_pct $committed_used P $committed_total);$committed_warn_lvl;$committed_crit_lvl;0;100"
