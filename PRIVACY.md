# Netmin Privacy Policy

Effective and last updated: September 21, 2026

This policy explains what data Netmin handles, where it goes, and how you can control it.

Netmin runs only the diagnostic requests that you choose. It has no advertising, analytics, tracking SDKs, account system, or developer-operated diagnostic service.

## Data on your Mac

Netmin stores app preferences, favorites, recent diagnostic targets, the local Pro trial start date, and the current day's Free request count in its macOS app container. The trial and daily allowance are calculated on this Mac and are not sent to the developer.

Diagnostic output stays in memory while you view it. Netmin does not save complete output automatically. A report is written to disk only when you choose where to export it. Text you copy is placed on the macOS general pasteboard.

The app does not monitor network traffic or run diagnostics in the background.

Apple processes Netmin Pro purchases and does not share payment details with Netmin's developer. The app reads your Apple purchase status to unlock Pro, including purchases shared through Family Sharing.

## Network requests

The target, hostname, IP address, URL, network range, or resolver you submit is sent only to systems needed for the diagnostic you start. Depending on the tool, this can include the target itself, its DNS and mail servers, a resolver you select, registry and WHOIS servers, certificate-transparency services, IP-information providers, or other public network-data services.

Built-in lookups can contact Cloudflare, Google Public DNS, Quad9, OpenDNS, RIPE, Team Cymru, ipify, ipinfo.io, rdap.org, hstspreload.org, and crt.sh. These services receive an ordinary network request, your public IP address, and the target or query needed to respond. They may process or retain that information under their own privacy policies and terms.

Local Network tools inspect addresses, interfaces, routes, and advertised services on networks connected to your Mac. Results are processed on your Mac. macOS asks for Local Network permission before allowing discovery.

Netmin does not send diagnostic targets, queries, or results to the developer.

## Retention and deletion

Recent targets remain in the app container until you choose **Netmin → Clear Recent Data…** or remove the container. Netmin keeps at most eight recent targets.

Complete diagnostic output is discarded when you replace or close the current result or quit the app. Exported reports remain at the location you selected until you delete them. Text copied from a result remains on the general pasteboard until you or another app replaces or clears it.

The trial start date, daily request count, favorites, and other preferences remain in the app container when you clear recent data. Removing Netmin and its app container deletes app-managed data. Apple controls purchase records associated with your Apple Account.

External services control retention of the requests they receive. Use their privacy and account controls when available.

## Your choices

You choose every diagnostic, its target, and when it runs. You can avoid tools that contact third-party services, choose a different DNS resolver where offered, deny Local Network access, clear recent targets, delete exported reports, clear copied text, or remove Netmin and its container.

## Changes and contact

This policy and its date will be updated when material changes occur. For privacy questions or requests, visit [Netmin support](https://min.tools/netmin/support/).
