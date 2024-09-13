#!/usr/bin/bash

set -e

docker compose --env-file dev.env build
docker compose --env-file dev.env down || true

# Purge old DB
docker volume rm postfix-tls-audit_postfix-audit-db || true

docker compose --env-file dev.env up -d --wait


subdomains=(a b c d)
for i in {1..4}
do
    subdomain=${subdomains[$i-1]}
    echo "Checking server ($i) $subdomain"
    UUID=$(uuidgen)
    echo "Using USERID: ${UUID}"

    # Ensure the MTA-STS policy is available on both HTTP and HTTPS
    # Not on third server
    if (( $i != 3 ));
    then
        curl -k -H "Host: mta-sts.$subdomain.audit.alexsci.com" https://127.0.0.1:8443/.well-known/mta-sts.txt | grep "enforce"
	# Make sure it was logged
        curl -k -H "Host: api.audit.alexsci.com" https://127.0.0.1:8443/poll -F users= | grep "mta-sts.${subdomain}.audit.alexsci.com"
    else
        echo "C won't have a policy hosted"
    fi

    echo "Checking that email hasn't been seen"
    curl -k -H "Host: api.audit.alexsci.com" https://127.0.0.1:8443/health | grep "pong"
    curl -k -H "Host: api.audit.alexsci.com" https://127.0.0.1:8443/poll -F users=$UUID | grep "{}"

    echo "Send the emails"
    ./test-send-email.exp 127.0.0.$i $UUID $subdomain.audit.alexsci.com

    # Email processing takes some time...
    sleep 1

    echo "Checking that email has been seen"
    curl -k -H "Host: api.audit.alexsci.com" https://127.0.0.1:8443/poll -F users=$UUID | grep "$UUID" | grep "Message Received"
    curl -k -H "Host: api.audit.alexsci.com" https://127.0.0.1:8443/poll -F users=$UUID | grep "$UUID" | grep "MSG: This Is The Message"

    echo ""
    echo "Server $subdomain looks OK!"
    echo ""
done

# Check TLS reporting
curl -k -H "Host: api.audit.alexsci.com" https://127.0.0.1:8443/tlsrpt -d "TLS REPORT"
curl -k -H "Host: api.audit.alexsci.com" https://127.0.0.1:8443/poll -F users= | grep "TLS REPORT"

docker compose --env-file dev.env down
echo ""
echo "SUCCESS!"
echo ""
