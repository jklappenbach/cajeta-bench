#!/usr/bin/env python3
"""csv-column.py — read a column of a dev.cajeta.bench results.csv, CSV-aware.

Since 0.1.3 every free-text field holding a comma, a quote or a newline is
RFC 4180-quoted (notes, flags, os, driver, model, platform, ...), so
`awk -F,` / `cut -d,` column checks in smoke scripts split those fields and
read the wrong column. Use this instead:

  csv-column.py results.csv status                      # one value per row
  csv-column.py results.csv benchmark --where status=failed
  csv-column.py results.csv status --join-tab           # one line, tab-joined
  csv-column.py --count-columns results.csv             # header width (37)

or, inline, the equivalent one-liner:

  python3 -c 'import csv,sys; [print(r[sys.argv[2]]) for r in csv.DictReader(open(sys.argv[1], newline="", encoding="utf-8"))]' results.csv status

Exit 0; 2 on a usage error or an unknown column (the message lists the header).
"""
import csv
import sys


def main(argv):
    count = "--count-columns" in argv
    join = "--join-tab" in argv
    where = []
    rest = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--where" and i + 1 < len(argv):
            k, _, v = argv[i + 1].partition("=")
            where.append((k, v))
            i += 2
            continue
        if a not in ("--count-columns", "--join-tab"):
            rest.append(a)
        i += 1
    if not rest or (not count and len(rest) != 2):
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print("usage: csv-column.py [--count-columns] <csv> [column] [--where col=val]... [--join-tab]",
              file=sys.stderr)
        return 2
    with open(rest[0], newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        header = reader.fieldnames or []
        if count:
            print(len(header))
            return 0
        column = rest[1]
        for k in [column] + [k for k, _ in where]:
            if k not in header:
                print(f"csv-column: no column {k} (have: {', '.join(header[:2])}, …)")
                return 2
        values = [r[column] for r in reader if all(r[k] == v for k, v in where)]
    if join:
        print("\t".join(values))
    else:
        for v in values:
            print(v)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
