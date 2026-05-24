#!/bin/bash
# Swap IPv4 and/or IPv6 on Plesk subscriptions

OLD_IPV4=""; NEW_IPV4=""
OLD_IPV6=""; NEW_IPV6=""
DRY_RUN=0

usage() {
    cat <<EOF
Usage: $0 [--dry-run] [--old-ipv4 IP --new-ipv4 IP] [--old-ipv6 IP --new-ipv6 IP]

Flags:
  --dry-run, -n   Show what would change without actually running
                  'plesk bin subscription -u'. Validation and DB reads
                  still run normally.

At least one complete pair must be provided. Both can be combined.

Examples:
  $0 --dry-run --old-ipv4 1.1.1.1 --new-ipv4 1.0.0.1
  $0 --old-ipv6 2606:4700:4700::1111 --new-ipv6 2606:4700:4700::1001
  $0 -n --old-ipv4 1.1.1.1 --new-ipv4 1.0.0.1 \\
        --old-ipv6 2606:4700:4700::1111 --new-ipv6 2606:4700:4700::1001
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --old-ipv4)   OLD_IPV4="$2"; shift 2;;
        --new-ipv4)   NEW_IPV4="$2"; shift 2;;
        --old-ipv6)   OLD_IPV6="$2"; shift 2;;
        --new-ipv6)   NEW_IPV6="$2"; shift 2;;
        --dry-run|-n) DRY_RUN=1; shift;;
        -h|--help)    usage; exit 0;;
        *) echo "Unknown argument: $1"; usage; exit 1;;
    esac
done

v4_pair=0; v6_pair=0
[[ -n "$OLD_IPV4" && -n "$NEW_IPV4" ]] && v4_pair=1
[[ -n "$OLD_IPV6" && -n "$NEW_IPV6" ]] && v6_pair=1

if [[ $v4_pair -eq 0 && $v6_pair -eq 0 ]]; then
    echo "ERROR: Provide at least one complete pair (ipv4 or ipv6)."; usage; exit 1
fi
if [[ ( -n "$OLD_IPV4" || -n "$NEW_IPV4" ) && $v4_pair -eq 0 ]]; then
    echo "ERROR: --old-ipv4 and --new-ipv4 must be provided together."; exit 1
fi
if [[ ( -n "$OLD_IPV6" || -n "$NEW_IPV6" ) && $v6_pair -eq 0 ]]; then
    echo "ERROR: --old-ipv6 and --new-ipv6 must be provided together."; exit 1
fi

check_ip_exists() {
    local c=$(/usr/sbin/plesk db -NBe "select count(*) from IP_Addresses where ip_address='$1';")
    [[ "$c" == "1" ]]
}
[[ $v4_pair -eq 1 ]] && ! check_ip_exists "$NEW_IPV4" && { echo "ERROR: $NEW_IPV4 is not in the Plesk IP pool."; exit 1; }
[[ $v6_pair -eq 1 ]] && ! check_ip_exists "$NEW_IPV6" && { echo "ERROR: $NEW_IPV6 is not in the Plesk IP pool."; exit 1; }

# Dry-run banner
prefix=""
if [[ $DRY_RUN -eq 1 ]]; then
    prefix="[DRY-RUN] "
    echo "============================================================"
    echo " DRY-RUN ENABLED - no subscriptions will be modified"
    echo "============================================================"
fi

old_ips=()
[[ $v4_pair -eq 1 ]] && old_ips+=("'$OLD_IPV4'")
[[ $v6_pair -eq 1 ]] && old_ips+=("'$OLD_IPV6'")
ip_in=$(IFS=,; echo "${old_ips[*]}")

/usr/sbin/plesk db -NBe "select distinct d.name \
    from domains d \
    join dom_param dp on d.id=dp.dom_id \
    join IP_Addresses ip on dp.val=ip.id \
    where ip.ip_address in ($ip_in) and d.parentDomainId=0;" | while read domain; do

    [[ -z "$domain" ]] && continue

    current_ipv4=""; current_ipv6=""
    while read ip; do
        [[ -z "$ip" ]] && continue
        if [[ "$ip" == *:* ]]; then current_ipv6="$ip"; else current_ipv4="$ip"; fi
    done < <(/usr/sbin/plesk db -NBe "select ip.ip_address \
        from domains d \
        join dom_param dp on d.id=dp.dom_id \
        join IP_Addresses ip on dp.val=ip.id \
        where d.name='$domain' and d.parentDomainId=0;")

    target_ipv4="$current_ipv4"; target_ipv6="$current_ipv6"; changed=0

    if [[ $v4_pair -eq 1 && "$current_ipv4" == "$OLD_IPV4" ]]; then
        target_ipv4="$NEW_IPV4"; changed=1
    fi
    if [[ $v6_pair -eq 1 && "$current_ipv6" == "$OLD_IPV6" ]]; then
        target_ipv6="$NEW_IPV6"; changed=1
    fi

    if [[ $changed -eq 0 ]]; then
        echo "${prefix}SKIPPING $domain - no matching IP to swap"
        continue
    fi

    ip_list=""
    [[ -n "$target_ipv4" ]] && ip_list="$target_ipv4"
    if [[ -n "$target_ipv6" ]]; then
        [[ -n "$ip_list" ]] && ip_list+=",$target_ipv6" || ip_list="$target_ipv6"
    fi

    echo "${prefix}$domain : ${current_ipv4:-—},${current_ipv6:-—}  ->  ${target_ipv4:-—},${target_ipv6:-—}"

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "${prefix}  would run: plesk bin subscription -u '$domain' -ip '$ip_list' -mail-service-ip '$ip_list'"
    else
        /usr/sbin/plesk bin subscription -u "$domain" \
            -ip "$ip_list" \
            -mail-service-ip "$ip_list"
    fi
done

if [[ $DRY_RUN -eq 1 ]]; then
    echo "============================================================"
    echo " DRY-RUN complete - no changes were made."
    echo " Remove --dry-run to apply the changes for real."
    echo "============================================================"
fi
