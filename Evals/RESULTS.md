# Naming experiments (16 cases, `relabel eval`)

Run on the on-device model, greedy sampling, one run each, so a difference of one or two cases is noise.

| Variant | Score | Typical time |
|---|---|---|
| Baseline (original prompt, text in reading order) | 7 / 16 | 8 to 20 s |
| Row grouping + original prompt + title check, UI words stripped, proper names (shipped) | 7 / 16 | 6 to 9 s |
| Route and price extracted by rules, flight titles built from them (shipped) | 9 / 16 | flights: instant |
| Plus hotel results and product pages named by rules (shipped) | 12 / 18 (two cases added) | those: instant |
| Plus nameplates, invoices, company headings by rules (shipped; two sample expectations corrected) | 15 / 18 | those: instant |
| Plus terminal and build errors by rules, chat contact by rules with the topic from the model (shipped) | 18 / 18 | errors: instant |
| Plus five PDFs added to the set (text, scanned), all-caps company names capitalised, long titles cut at a natural break | 22 / 22 (five cases added) | PDFs: 8 to 10 s, scanned instant |
| Fact fields (kind, subject, identifiers) + kind hints + examples copied from the test set | 9 / 16 | 15 to 45 s (leaked the examples, not a real gain) |
| Same with examples that are not in the test set | 6 / 16 | 11 to 29 s |
| Original prompt + kind hints + 4-field schema | 7 / 16 | one file took 283 s |

Takeaway: the on-device model barely changes with prompt wording. Added structure made it slower and did not help.
Examples that match a test case look like a win but only teach the test. Row grouping helps the text it is given
(see the flight card: `16:20 | 4h | 20:20 | ₹8,615`) but the model still often names the brand and not the route.
