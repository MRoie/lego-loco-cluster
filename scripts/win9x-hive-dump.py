#!/usr/bin/env python3
"""Read a Windows 95/98 registry hive (SYSTEM.DAT / USER.DAT).

No Linux tool does this. hivex and chntpw both handle only the NT format; Win9x
uses CREG, which is a completely different on-disk layout. That gap is why every
registry change to the LEGO LOCO guest image was, for a long time, a blind write
followed by a reboot and a guess — and why a wrong guess cost an afternoon each
time.

    win9x-hive-dump.py SYSTEM.DAT                       # every live key and value
    win9x-hive-dump.py SYSTEM.DAT --find W5C5G7         # which key holds this string
    win9x-hive-dump.py SYSTEM.DAT --key 'System\\CurrentControlSet\\Services\\VxD\\VNETSUP'
    win9x-hive-dump.py a/SYSTEM.DAT --diff b/SYSTEM.DAT # what differs between two guests

Get a hive off a guest disk with mtools, which reads the image in place:

    export MTOOLSRC=/run/pcem/mtoolsrc MTOOLS_SKIP_CHECK=1
    mcopy -o c:/WINDOWS/SYSTEM.DAT /tmp/SYSTEM.DAT

--find is the mode worth knowing about. Grepping a hive for a string finds
*deleted* records too: REGEDIT rewrites a key into a new record and orphans the
old one, whose bytes stay in the file on a free list. Searching this image for
its original computer name turns up three hits, only one of which is live, and
believing the dead one sends you looking for a bug that is not there. This tool
labels every hit LIVE or FREE.

FORMAT NOTES, since the layout is barely documented and one detail is a trap.

A CREG file is a 32-byte header, an RGKN block holding the key *tree*, then a
series of RGDB blocks holding key *names and values*. A key is therefore split
across two structures, joined by an (RGDB block number, key id) pair.

RGKN nodes are 28 bytes, but they are NOT laid out at a uniform stride from the
block header. Enumerating them by stride mislabels most nodes, and a tree walk
that then resolves child/sibling pointers against that strided table silently
drops whole subtrees — on this image, 283 keys reached instead of 17,216, with
no error to indicate anything was missed. Read each node at whatever byte offset
a pointer actually names, as below.

RGKN node, offsets relative to the RGKN block start (file offset 32):
    +0x00 u32 flags/type      +0x04 u32 name hash     +0x08 u32 next free
    +0x0C u32 parent          +0x10 u32 first child   +0x14 u32 next sibling
    +0x18 u16 RGDB key id     +0x1A u16 RGDB block number
"""

import argparse
import struct
import sys

U32 = lambda b, o: struct.unpack_from("<I", b, o)[0]
U16 = lambda b, o: struct.unpack_from("<H", b, o)[0]

# A pointer is nil when it is all-ones; 0 also appears as a terminator.
NIL = (0xFFFFFFFF, 0)

TYPES = {0: "REG_NONE", 1: "REG_SZ", 2: "REG_EXPAND_SZ", 3: "REG_BINARY",
         4: "REG_DWORD", 7: "REG_MULTI_SZ"}

FREE_ID = 0xFFFF


class Hive:
    def __init__(self, path):
        self.path = path
        self.d = d = open(path, "rb").read()
        if d[:4] != b"CREG":
            raise SystemExit("%s: not a Win9x CREG hive (NT hives start 'regf' —"
                             " use hivex for those)" % path)
        self.rgdb_off = U32(d, 8)
        if d[32:36] != b"RGKN":
            raise SystemExit("%s: no RGKN block at offset 32" % path)
        self.base = 32
        self.rgkn_size = U32(d, 36)
        self.root = U32(d, 40)
        self.records = {}       # (block, id) -> record, live only
        self.free_records = []  # orphaned by a rewrite; bytes still present
        self._read_rgdb()

    def _read_rgdb(self):
        d = self.d
        off = self.rgdb_off
        while off + 8 <= len(d) and d[off:off + 4] == b"RGDB":
            size = U32(d, off + 4)
            end, p = off + size, off + 0x20
            while p + 0x14 <= end:
                rsize = U32(d, p)
                if rsize < 0x14 or p + rsize > end:
                    break
                rid, rblk = U16(d, p + 4), U16(d, p + 6)
                namelen, nvalues = U16(d, p + 0x0C), U16(d, p + 0x0E)
                if p + 0x14 + namelen > p + rsize:
                    p += rsize
                    continue
                name = d[p + 0x14:p + 0x14 + namelen].decode("latin-1")

                # Bound every read by the record end. A length field that
                # over-runs is a mis-parse, and following it silently swallows
                # the rest of the block into one "value name" — which looks like
                # a real key with a megabyte-long name and is deeply confusing.
                rec_end = p + rsize
                values, q = [], p + 0x14 + namelen
                for _ in range(nvalues):
                    if q + 0x0C > rec_end:
                        break
                    vtype = U32(d, q)
                    vnlen, vdlen = U16(d, q + 8), U16(d, q + 0x0A)
                    if q + 0x0C + vnlen + vdlen > rec_end:
                        break
                    vname = d[q + 0x0C:q + 0x0C + vnlen].decode("latin-1")
                    vdata = d[q + 0x0C + vnlen:q + 0x0C + vnlen + vdlen]
                    values.append(dict(name=vname, type=vtype, data=vdata, off=q))
                    q += 0x0C + vnlen + vdlen

                rec = dict(name=name, values=values, off=p, id=rid, blk=rblk)
                if rid == FREE_ID:
                    self.free_records.append(rec)
                else:
                    self.records[(rblk, rid)] = rec
                p += rsize
            off = end

    def node(self, rel):
        """Read a 28-byte RGKN node at an arbitrary relative offset."""
        o = self.base + rel
        if rel in NIL or o + 28 > self.base + self.rgkn_size:
            return None
        d = self.d
        return dict(rel=rel, parent=U32(d, o + 0x0C), child=U32(d, o + 0x10),
                    nxt=U32(d, o + 0x14), id=U16(d, o + 0x18), blk=U16(d, o + 0x1A))

    def walk(self):
        """(path, record) for every key reachable from the root, depth first."""
        out, seen = [], set()
        stack = [(self.root, "")]
        while stack:
            rel, prefix = stack.pop()
            if rel in NIL or rel in seen:
                continue
            seen.add(rel)
            n = self.node(rel)
            if n is None:
                continue
            rec = self.records.get((n["blk"], n["id"]))
            if rel == self.root:
                path = ""
            else:
                label = rec["name"] if rec else "<id%d:%d>" % (n["blk"], n["id"])
                path = (prefix + "\\" + label).lstrip("\\")
            out.append((path, rec))
            stack.append((n["child"], path))
            stack.append((n["nxt"], prefix))
        return out

    def flat(self):
        """{"key\\value": rendered} for every live value. Used by --diff."""
        out = {}
        for path, rec in self.walk():
            if not rec:
                continue
            for v in rec["values"]:
                out["%s\\%s" % (path, v["name"] or "(default)")] = render(v)
        return out


TEXT_TYPES = (1, 2, 7)   # REG_SZ, REG_EXPAND_SZ, REG_MULTI_SZ


def render(v, limit=None):
    t, data = v["type"], v["data"]
    if t in TEXT_TYPES:
        out = data.rstrip(b"\0").decode("latin-1").replace("\0", " ")
    elif t == 4 and len(data) == 4:
        out = "0x%08x" % U32(data, 0)
    else:
        out = data.hex(" ")
    if limit and len(out) > limit:
        out = out[:limit] + "... (%d bytes)" % len(data)
    return out


def cmd_dump(hive, args):
    for path, rec in sorted(hive.walk(), key=lambda x: x[0].lower()):
        if not path or not rec:
            continue
        print("[%s]" % path)
        for v in rec["values"]:
            print('  "%s" (%s) = %s' % (v["name"] or "(default)",
                                        TYPES.get(v["type"], v["type"]), render(v)))


def cmd_key(hive, args):
    want = args.key.lower().lstrip("\\")
    hits = 0
    for path, rec in hive.walk():
        if path.lower() == want and rec:
            hits += 1
            print("[%s]   (record at file offset 0x%06x)" % (path, rec["off"]))
            for v in rec["values"]:
                print('  "%s" (%s) = %s' % (v["name"] or "(default)",
                                            TYPES.get(v["type"], v["type"]), render(v)))
    if not hits:
        print("no live key at %s" % args.key, file=sys.stderr)
        return 1
    return 0


def _matches(v, needle, binary):
    """Does this value contain the needle?

    Text values only unless --binary is given. A hex-rendered REG_BINARY blob
    matches almost any short hex-ish needle and buries the real hits in
    kilobytes of noise, which is the opposite of what this mode is for.
    """
    if needle in v["name"].lower():
        return True
    if v["type"] in TEXT_TYPES or v["type"] == 4:
        return needle in render(v).lower()
    return binary and needle in v["data"].hex().lower()


def cmd_find(hive, args):
    """Locate a string, saying for each hit whether the record is live.

    This is the mode that matters. A raw grep cannot tell a live value from one
    in a record REGEDIT orphaned when it rewrote the key — the orphan's bytes
    stay in the file on a free list — and the orphan reads exactly like a bug in
    whatever wrote the new value. Searching this image for its original computer
    name gives three hits, one live and one long dead.
    """
    needle = args.find.lower()
    live = 0

    for path, rec in hive.walk():
        if not rec:
            continue
        if needle in rec["name"].lower():
            print("LIVE  key   [%s]" % path)
            live += 1
        for v in rec["values"]:
            if _matches(v, needle, args.binary):
                print('LIVE  value [%s]\n        "%s" = %s   (offset 0x%06x)'
                      % (path, v["name"] or "(default)", render(v, 120), v["off"]))
                live += 1

    free = 0
    for rec in hive.free_records:
        # A free record's header is not maintained once it leaves the tree, so
        # its name length can be nonsense and "name" can swallow the rest of the
        # block. Anything absurd is a mis-parse, not a key called that.
        name = rec["name"] if len(rec["name"]) <= 64 else "<unparseable free record>"
        hit = (name != "<unparseable free record>" and needle in name.lower()) or \
            any(_matches(v, needle, args.binary) for v in rec["values"])
        if not hit:
            continue
        free += 1
        print("FREE  deleted record at 0x%06x, key '%s'  <- orphaned by a rewrite, "
              "NOT read by Windows" % (rec["off"], name))
        for v in rec["values"]:
            if _matches(v, needle, args.binary):
                print('        "%s" = %s' % (v["name"] or "(default)", render(v, 120)))

    print("\n%d live hit(s), %d in deleted records" % (live, free), file=sys.stderr)
    return 0 if live or free else 1


def cmd_diff(hive, args):
    """Values that differ between two hives.

    Two guests cloned from one image should differ only in what is genuinely
    per-instance. Anything identical that ought to be unique — a computer name,
    say — shows up as an absence here, which is the fastest way to find a
    per-instance setting that silently failed to apply.
    """
    other = Hive(args.diff)
    a, b = hive.flat(), other.flat()
    only_a = sorted(set(a) - set(b))
    only_b = sorted(set(b) - set(a))
    differ = sorted(k for k in set(a) & set(b) if a[k] != b[k])

    for k in differ:
        print("~ %s\n    %s: %s\n    %s: %s" % (k, hive.path, a[k], other.path, b[k]))
    for k in only_a:
        print("- %s = %s   (only in %s)" % (k, a[k], hive.path))
    for k in only_b:
        print("+ %s = %s   (only in %s)" % (k, b[k], other.path))

    print("\n%d values in common, %d differ, %d only in %s, %d only in %s"
          % (len(set(a) & set(b)), len(differ), len(only_a), hive.path,
             len(only_b), other.path), file=sys.stderr)
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("hive", help="SYSTEM.DAT or USER.DAT")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--find", metavar="STRING",
                   help="locate a string, marking live vs deleted records")
    g.add_argument("--key", metavar="PATH", help="dump one key")
    g.add_argument("--diff", metavar="OTHER.DAT", help="compare against another hive")
    ap.add_argument("--binary", action="store_true",
                    help="--find also searches REG_BINARY blobs (noisy)")
    args = ap.parse_args()

    hive = Hive(args.hive)
    if args.find:
        return cmd_find(hive, args)
    if args.key:
        return cmd_key(hive, args)
    if args.diff:
        return cmd_diff(hive, args)
    return cmd_dump(hive, args)


if __name__ == "__main__":
    sys.exit(main() or 0)
