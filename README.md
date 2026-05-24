# Plesk IP Swap

Bash script for bulk-swapping IPv4 and/or IPv6 addresses across Plesk
subscriptions. Finds every subscription using a given old address and
reassigns it to a new one — for both hosting and mail service — while
keeping the other address family untouched.

> Previously this script unconditionally added a hard-coded IPv6 to all
> subscriptions on a hard-coded IPv4. It is now a generic swap tool driven
> by command-line flags. The filename is kept for backwards compatibility,
> but feel free to rename it (e.g. `plesk-ip-swap.sh`).

## Features

- Swap IPv4 → IPv4, IPv6 → IPv6, or both in a single run
- Preserves the unchanged address family per subscription
- Verifies the new address exists in the Plesk IP pool before doing anything
- `--dry-run` mode showing the exact `plesk bin subscription -u` command that
  would be executed for each match
- Idempotent — safe to run repeatedly or from cron

## Requirements

- Plesk Obsidian (or any version with `plesk db` and `plesk bin subscription`)
- Bash 4+
- Root privileges
- The new target IP address(es) must already exist in the Plesk IP pool
  (add via *Tools & Settings → IP Addresses* or `plesk bin ipmanage --create`)

## Usage

```
./assign_ipv6.sh [--dry-run] \
                 [--old-ipv4 IP --new-ipv4 IP] \
                 [--old-ipv6 IP --new-ipv6 IP]
```

| Flag              | Description                                                 |
|-------------------|-------------------------------------------------------------|
| `--old-ipv4 IP`   | Current IPv4 to look for                                    |
| `--new-ipv4 IP`   | IPv4 to swap in                                             |
| `--old-ipv6 IP`   | Current IPv6 to look for                                    |
| `--new-ipv6 IP`   | IPv6 to swap in                                             |
| `--dry-run`, `-n` | Show planned changes without modifying anything             |
| `--help`, `-h`    | Show usage info                                             |

At least one complete pair must be provided. Half-pairs (e.g. only
`--old-ipv4`) are rejected to prevent accidents.

## Examples

Dry-run an IPv6 swap to preview the changes:

```
sudo ./assign_ipv6.sh --dry-run \
    --old-ipv6 2606:4700:4700::1111 \
    --new-ipv6 2606:4700:4700::1001
```

Swap only IPv4:

```
sudo ./assign_ipv6.sh --old-ipv4 1.1.1.1 --new-ipv4 1.0.0.1
```

Swap both at once (matches any subscription using either old address):

```
sudo ./assign_ipv6.sh \
    --old-ipv4 1.1.1.1 --new-ipv4 1.0.0.1 \
    --old-ipv6 2606:4700:4700::1111 --new-ipv6 2606:4700:4700::1001
```

## Logging

Redirect output to a file as usual:

```
sudo ./assign_ipv6.sh --old-ipv6 2606:4700:4700::1111 --new-ipv6 2606:4700:4700::1001 \
    >> /var/log/plesk-ip-swap.log 2>&1
```

## Run as a cronjob

To catch newly created subscriptions automatically, install as a cronjob.

1. Edit root's crontab:

   ```
   sudo crontab -e -u root
   ```

2. Add a line such as:

   ```
   0 * * * * /path/to/assign_ipv6.sh --old-ipv4 1.1.1.1 --new-ipv4 1.0.0.1 >> /var/log/plesk-ip-swap.log 2>&1
   ```

The script is idempotent — subscriptions that don't match the supplied
old IP are logged as `SKIPPING ... - no matching IP to swap` and left alone.

## Safety notes

- Always run with `--dry-run` first against production.
- The script only modifies subscriptions where the current IP **exactly**
  matches the supplied old IP.
- Mail service IPs are updated in lockstep with hosting IPs
  (`-mail-service-ip`).
- Add-on domains are excluded at the SQL level (`parentDomainId=0`) — they
  inherit their parent subscription's IPs.
