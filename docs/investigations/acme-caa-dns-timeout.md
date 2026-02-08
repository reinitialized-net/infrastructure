# ACME Certificate Renewal Failure — CAA DNS Timeout

## Symptoms

Intermittent ACME certificate renewal failures across all hosts using the `shortlived` profile. The error from lego/Let's Encrypt:

```
acme: error: 400 :: urn:ietf:params:acme:error:dns :: While processing CAA for
unifi.in.reinitialized.net: DNS problem: query timed out looking up CAA for
unifi.in.reinitialized.net
```

Renewals sometimes succeed, sometimes fail. All certificates are affected, not just `unifi.in.reinitialized.net`.

## Root Cause

A **nameserver delegation issue** at the `.net` TLD registrar level caused Let's Encrypt's DNS resolution to intermittently fail.

### The DNS Delegation Chain (Original Issue)

The `.net` TLD servers were returning **three** NS records for `reinitialized.net`:

| Nameserver | IP | Status |
|---|---|---|
| `one.dns.reinitialized.net` | `47.190.182.77` | ✅ Active — proxied via rp1 nginx stream to Technitium dnsOne |
| `two.dns.reinitialized.net` | `47.190.182.78` | ✅ Active — proxied via rp1 nginx stream to Technitium dnsTwo |
| `three.dns.reinitialized.net` | `129.213.103.16` | ❌ Dead — not yet configured, no DNS service running |

Technitium itself only advertises two NS records (`one.dns` and `two.dns`). The `three.dns` entry existed at the registrar level but was not yet operational (intended for future use).

### Why Failures Are Intermittent

When Let's Encrypt validates a certificate, it performs CAA record lookups by querying the authoritative nameservers for the domain. The DNS resolver randomly selects which NS to query from the three returned by the `.net` TLD. The probability breakdown:

- **~67% chance**: Resolver picks `one.dns` or `two.dns` → query succeeds → certificate renews
- **~33% chance**: Resolver picks `three.dns` (129.213.103.16) → query times out → renewal fails

Let's Encrypt performs multi-perspective validation from multiple vantage points, which means even a single vantage point selecting `three.dns` can cause the entire validation to fail.

### CAA Tree-Walking Amplifies the Problem

For `unifi.in.reinitialized.net`, Let's Encrypt performs CAA lookups at each level:
1. `unifi.in.reinitialized.net` — no CAA record
2. `in.reinitialized.net` — no CAA record  
3. `reinitialized.net` — no CAA record (allow any CA)

Each of these queries independently selects a nameserver. With 3 queries, the probability of at least one hitting the dead `three.dns` increases to approximately **70%** per validation attempt (1 - 0.67³ ≈ 0.70).

## Steps Taken to Identify Root Cause

1. Checked ACME configuration across all hosts (rp1, apps1, apps2) — configuration is correct, using DNS-01 challenge via Technitium API
2. Queried CAA records from internal Technitium DNS — no CAA records exist (correct, means "allow any CA")
3. Ran `dig +trace` from devenv for `CAA unifi.in.reinitialized.net @8.8.8.8`:
   - Trace showed `.net` TLD returns 3 NS records including `three.dns.reinitialized.net`
   - `dig` reported: `couldn't get address for 'three.dns.reinitialized.net': not found`
   - All communications to `47.190.182.77` timed out (expected — hairpin NAT doesn't work from VLAN 200)
4. Queried registrar glue records directly from `.net` TLD (`dig NS reinitialized.net @e.gtld-servers.net +norecurse`):
   - Found `three.dns.reinitialized.net` with glue record `129.213.103.16`
   - This IP is completely unreachable (no DNS service, times out on both TCP and UDP)
5. Verified via Google DNS-over-HTTPS (`dns.google/resolve`) that queries **do** succeed when a working NS is selected
6. Confirmed Technitium only advertises 2 NS records — `three.dns` is purely a registrar-level orphan

## Fix

### Applied: Remove NS Delegation for Non-Operational Nameserver

**Action taken:** Removed `three.dns.reinitialized.net` from the NS delegation records at the domain registrar.

**Important:** The glue record (`three.dns.reinitialized.net` → `129.213.103.16`) remains at the registrar for future use when the third DNS server is configured. **This is safe** because:
- Glue records are only returned in DNS responses when the corresponding NS record is in the delegation
- Since `three.dns` is no longer in the NS list, its glue record is **not advertised** and won't be queried
- When the third DNS server becomes operational, only the NS delegation needs to be re-added

After removal, the `.net` TLD returns only the two operational nameservers, eliminating the ~33% failure rate per query.

**Note:** TLD NS record changes propagated within 24-48 hours. During this period, some resolvers may have still had the old 3-NS response cached.

### Optional: Add CAA Records to Reduce Query Depth

Adding a CAA record at the `reinitialized.net` zone apex would not fix the root cause (the dead NS will still cause timeouts for A/TXT lookups too), but is generally good practice:

```
reinitialized.net.  CAA  0 issue "letsencrypt.org"
```

This restricts certificate issuance to Let's Encrypt only, which is a security best practice.

### TLD NS Records

Verified only 2 NS records are now delegated at the TLD level:

```bash
$ dig NS reinitialized.net @e.gtld-servers.net +norecurse

;; AUTHORITY SECTION:
reinitialized.net.      172800  IN      NS      one.dns.reinitialized.net.
reinitialized.net.      172800  IN      NS      two.dns.reinitialized.net.

;; ADDITIONAL SECTION:
one.dns.reinitialized.net. 172800 IN    A       47.190.182.77
two.dns.reinitialized.net. 172800 IN    A       47.190.182.78
```

### CAA Resolution from Public Internet

Tested via Google DNS (simulates Let's Encrypt's perspective):

```bash
$ curl -s "https://dns.google/resolve?name=unifi.in.reinitialized.net&type=CAA" | jq
{
  "Status": 0,  # NOERROR - success
  "Comment": "Response from 47.190.182.77."
}
```

All three levels of the CAA tree walk (`unifi.in.reinitialized.net`, `in.reinitialized.net`, `reinitialized.net`) now resolve successfully without timeouts.

### Certificate Renewal

To verify ACME renewals now succeed:

```bash
# Force a certificate renewal
systemctl start acme-unifi.in.reinitialized.net.service

# Check renewal status
systemctl status acme-unifi.in.reinitialized.net.service
```

Expected result: Renewal completes successfully without CAA lookup timeouts.

## Future Work

When `three.dns.reinitialized.net` is configured and operational:
1. Add it back to the NS delegation at the registrar (the glue record is already present)
2. Update Technitium to advertise 3 NS records in the zone SOA
3. Verify all three servers respond to DNS queries from the public internetorce a certificate renewal to verify
systemctl start acme-unifi.in.reinitialized.net.service
```
