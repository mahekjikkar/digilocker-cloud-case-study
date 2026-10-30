# Week 1 summary: DigiLocker

IT457 Cloud Computing, Group 36. Mahek Jikkar (202301260), Shambhavi Singh
(202301107), Meet Jain (202301073).

Transcribed from the submitted Week 1 document (`Group_36.pdf`). Figures are as
reported there; see the [research log](research-log.md) for provenance.

## About DigiLocker

DigiLocker is India's national digital document wallet, run by the National
e-Governance Division (NeGD) under MeitY. A citizen signs in and reaches driving
licences, vehicle registrations, PAN, marksheets and insurance policies that carry
the same legal standing as the original paper. Four pressures shape how such a
platform must be built.

**Load is event-driven, not steady.** Traffic is mostly flat, then a board result is
declared and tens of millions of students arrive within the hour. CBSE published
Class 12 results through DigiLocker in May 2026 and deliberately ran several result
platforms at once to spread the demand. The COVID vaccination certificate produced
the same effect at national scale. Failing on result day is a news story, not a
dropped shopping cart.

**The platform is federated, not owned.** Documents are produced by central
ministries, state transport authorities, examination boards and insurers. Their
systems vary enormously in capacity and reliability, and DigiLocker cannot upgrade
any of them. One slow department can stall a citizen's request.

(The Week 2 report adds two further pressures: trust and sovereignty constraints,
and the absence of revenue per user.)

## How it works

DigiLocker holds the pointer; the issuer still holds the document. Reconstructed
from the Digital Locker Technology Specification (DLTS) v2.3 and the Issuer and
Requester API specifications.

- **The URI is the whole trick.** Every document has an identifier of the form
  `IssuerID-DocType-DocID`, independent of where the file physically sits. The access
  gateway turns it into a real URL in the right repository when the request arrives.
- **Two issuance paths exist.** Most documents are pulled from the issuer on demand
  through the pull APIs. Registered partner organisations can also push a
  certificate directly into a citizen's locker.
- **Self-uploaded documents are the exception.** DigiLocker does store these, capped
  at 1 GB per citizen, and they are explicitly not treated as authentic originals.
  Only issued documents carry legal standing.

Component view: a citizen (web or mobile app) and a requester (bank or employer)
reach DigiLocker core, made of sign-in and consent (mobile or Aadhaar, OTP and PIN),
the URI registry (pointers and metadata, not files) and the access gateway (resolves
a URI to the issuer). The core fetches from issuer repositories (UIDAI, Parivahan,
exam boards, Income Tax) and receives the signed document back. The figures cited
are 2,347 issuers and 5,437 document types and services.

## Sources reviewed

| Source | Publisher, date | What it gave us |
|---|---|---|
| Digital Locker Technology Specification v2.3 | NeGD, Mar 2015 | The system roles, the federated no-central-repository design, and the document URI scheme |
| PIB: UMANG and DigiLocker service delivery | Press Information Bureau, 12 Aug 2026 | Current dated figures: users, document types, access transactions |
| DigiLocker Partners Resource Centre | API Setu, NeGD | Current Issuer, Requester and Meri Pehchaan specifications and the integration workflows |
| DigiLocker: Citizen's Vault of Trust on Public Cloud | NeGD, Oct 2025 | Origin and hosting history, and why issued documents differ legally from uploaded ones |
| MeitY Annual Report 2025-26 | MeitY, Apr 2026 | Issuer count and a second dated adoption figure for comparison |

(Links are in the original PDF.)

## Salient points

1. **The scale is in the accounts, not the traffic.** 72.43 crore registered users as
   of 31 July 2026, but only about 72.86 crore document access transactions across
   three years, which averages roughly 7 to 8 requests per second. The engineering
   problem is the spikes, not sustained throughput.
2. **Load arrives in nationally synchronised bursts.** Board result days are the
   clearest case, with CBSE running several result platforms at once to spread
   demand. COVID vaccination certificates produced the same effect.
3. **The platform avoids storing what it serves.** DLTS states that documents sit in
   federated repositories with no central document repository. Each has a URI of the
   form `IssuerID-DocType-DocID`, resolved to the issuer's repository at request
   time. Only self-uploaded documents are stored, capped at 1 GB per citizen, and
   those are not legally authentic.
4. **It depends on systems it does not control.** 2,347 issuers and 5,437 document
   types, of which 4,776 are state-level. Sign-in runs through Meri Pehchaan, the
   National Single Sign-On, and the platform also integrates Aadhaar and eSign. Each
   is an external dependency in the request path.
5. **Independent scalability was designed in, and so were the constraints.** DLTS
   requires the repository, gateway and locker to communicate only through DLTS APIs
   so each can scale and be administered separately. At the same time, consent
   precedes retrieval, documents are signed XML, the gateway may store no document or
   credential, and hosting sits on government cloud under data-residency rules.
