#!/usr/bin/python3
"""Append Chewing to a GNOME input-source GVariant without removing layouts."""
import sys
from gi.repository import GLib


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Expected one GVariant input-source array")
    sources = GLib.Variant.parse(GLib.VariantType.new("a(ss)"), sys.argv[1], None, None).unpack()
    if ("ibus", "chewing") not in sources:
        sources.append(("ibus", "chewing"))
    print(GLib.Variant("a(ss)", sources).print_(True))


if __name__ == "__main__":
    main()
