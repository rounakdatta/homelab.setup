"""Build trust.mobileconfig: today's roots, taken from macOS's system trust store, for an iOS 9 iPad.

UUIDs are derived from the names, so a regenerated profile replaces an installed
one instead of sitting beside it.
"""
import plistlib
import ssl
import subprocess
import sys
import uuid

ROOTS = [
    ("ISRG Root X1", "isrg-root-x1"),
    ("ISRG Root X2", "isrg-root-x2"),
    ("USERTrust RSA Certification Authority", "usertrust-rsa"),
]
NAMESPACE = uuid.uuid5(uuid.NAMESPACE_DNS, "books.taptappers.club")


def der(name):
    pem = subprocess.run(
        ["security", "find-certificate", "-c", name, "-p", "/System/Library/Keychains/SystemRootCertificates.keychain"],
        capture_output=True, text=True, check=True,
    ).stdout
    return ssl.PEM_cert_to_DER_cert(pem)


payloads = [
    {
        "PayloadType": "com.apple.security.root",
        "PayloadVersion": 1,
        "PayloadIdentifier": f"club.taptappers.books.trust.{slug}",
        "PayloadUUID": str(uuid.uuid5(NAMESPACE, slug)).upper(),
        "PayloadDisplayName": name,
        "PayloadCertificateFileName": f"{slug}.cer",
        "PayloadContent": der(name),
    }
    for name, slug in ROOTS
]
profile = {
    "PayloadType": "Configuration",
    "PayloadVersion": 1,
    "PayloadIdentifier": "club.taptappers.books.trust",
    "PayloadUUID": str(uuid.uuid5(NAMESPACE, "profile")).upper(),
    "PayloadDisplayName": "Certificate roots for the bookshelf",
    "PayloadOrganization": "taptappers.club",
    "PayloadDescription": (
        "iOS 9 trusts the certificate authorities of 2015. This adds three that every current "
        "device already trusts (Let's Encrypt's ISRG Root X1 and X2, and Sectigo's USERTrust RSA), "
        "so Safari can open books.taptappers.club and most of today's web. "
        "Remove it any time in Settings > General > Profiles."
    ),
    "PayloadRemovalDisallowed": False,
    "PayloadContent": payloads,
}
sys.stdout.buffer.write(plistlib.dumps(profile, fmt=plistlib.FMT_XML))
