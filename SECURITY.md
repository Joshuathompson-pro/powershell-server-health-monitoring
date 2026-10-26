# Security and privacy

This repository is designed for lab and portfolio use. It contains no employer code, credentials, hostnames, logs, screenshots, network addresses, or proprietary configuration.

## Safe-use guidance

- Copy `config/servers.example.json` to the ignored file `config/servers.json` before adding real systems.
- Never commit production hostnames, IP addresses, usernames, credentials, access tokens, or report output.
- Use the current user's Windows authentication. Do not embed passwords in scripts or configuration.
- Grant only the remote-management permissions required for health collection.
- Restrict WinRM using approved firewall rules, trusted administration networks, and organizational policy.
- Keep the generated `reports/` and `state/` directories out of source control.
- Review exported reports before sharing them because infrastructure names and health data can be sensitive.

## Reporting concerns

If you discover a security issue in this sample project, contact the repository owner privately rather than opening a public issue containing sensitive details.

