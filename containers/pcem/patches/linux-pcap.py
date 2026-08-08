#!/usr/bin/env python3
"""Build PCem v17's bridged (PCap) network backend on Linux.

Upstream compiles the whole PCap path only `#ifdef _WIN32`, and on every other
platform `ne2000_init()` hard-codes:

    net_is_slirp = 1;
    net_is_pcap  = 0;

SLiRP is a userspace NAT stack. It answers ARP and IP for one guest behind one
private 10.0.2.x network and drops every other ethertype, so two PCem instances
running SLiRP are isolated islands that both believe they are 10.0.2.15. That
makes a LAN game between two containers impossible — DirectPlay's session
discovery never reaches the other guest.

The PCap backend puts the guest's frames straight onto a host interface, which
is what allows two emulator pods sharing an L2 segment (bridge + TAP + VXLAN
mesh, the same mechanism the QEMU flavor uses) to see each other.

Nothing here changes the emulation. The code was already written and is already
used on Windows; it is only unavailable because of how it is compiled. The
edits are:

  1. include <pcap.h> unconditionally
  2. declare the `_pcap_*` function pointers on Linux too, and take the
     `__cdecl` off the typedefs (an MSVC calling convention gcc rejects)
  3. bind those pointers directly to libpcap instead of LoadLibrary/GetProcAddress
  4. let `net_type` / `pcap_device` be read from pcem.cfg on Linux
  5. open the gates around the send and receive paths

Usage: linux-pcap.py <pcem-source-root>
"""

import pathlib
import sys

SRC = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")

# 1. ---------------------------------------------------------------- include
INCLUDE_OLD = """#ifdef _WIN32
#include <pcap.h>
#endif"""
INCLUDE_NEW = """#include <pcap.h>"""

# 2. ------------------------------------------- typedefs and function pointers
DECLS_OLD = """#ifdef _WIN32
static HINSTANCE net_hLib = 0;                      /* handle to DLL */
static char *net_lib_name = "wpcap.dll";
pcap_t *net_pcap;
typedef pcap_t* (__cdecl * PCAP_OPEN_LIVE)(const char *, int, int, int, char *);
typedef int (__cdecl * PCAP_SENDPACKET)(pcap_t* handle, const u_char* msg, int len);
typedef int (__cdecl * PCAP_SETNONBLOCK)(pcap_t *, int, char *);
typedef const u_char*(__cdecl *PCAP_NEXT)(pcap_t *, struct pcap_pkthdr *);
typedef const char*(__cdecl *PCAP_LIB_VERSION)(void);
typedef void (__cdecl *PCAP_CLOSE)(pcap_t *);
typedef int  (__cdecl *PCAP_GETNONBLOCK)(pcap_t *p, char *errbuf);
typedef int (__cdecl *PCAP_COMPILE)(pcap_t *p, struct bpf_program *fp, const char *str, int optimize, bpf_u_int32 netmask);
typedef int (__cdecl *PCAP_SETFILTER)(pcap_t *p, struct bpf_program *fp);
"""

DECLS_NEW = """#ifdef _WIN32
static HINSTANCE net_hLib = 0;                      /* handle to DLL */
static char *net_lib_name = "wpcap.dll";
#define PCEM_CDECL __cdecl
#else
/* Linux: libpcap is linked, not loaded at runtime. Keep the same indirection
   so the call sites below stay byte-identical to the Windows ones. */
static void *net_hLib = 0;
static char *net_lib_name = "libpcap";
#define PCEM_CDECL
#endif
pcap_t *net_pcap;
typedef pcap_t* (PCEM_CDECL * PCAP_OPEN_LIVE)(const char *, int, int, int, char *);
typedef int (PCEM_CDECL * PCAP_SENDPACKET)(pcap_t* handle, const u_char* msg, int len);
typedef int (PCEM_CDECL * PCAP_SETNONBLOCK)(pcap_t *, int, char *);
typedef const u_char*(PCEM_CDECL *PCAP_NEXT)(pcap_t *, struct pcap_pkthdr *);
typedef const char*(PCEM_CDECL *PCAP_LIB_VERSION)(void);
typedef void (PCEM_CDECL *PCAP_CLOSE)(pcap_t *);
typedef int  (PCEM_CDECL *PCAP_GETNONBLOCK)(pcap_t *p, char *errbuf);
typedef int (PCEM_CDECL *PCAP_COMPILE)(pcap_t *p, struct bpf_program *fp, const char *str, int optimize, bpf_u_int32 netmask);
typedef int (PCEM_CDECL *PCAP_SETFILTER)(pcap_t *p, struct bpf_program *fp);
"""

DECLS_END_OLD = """PCAP_SETFILTER		_pcap_setfilter;
#endif

queueADT slirpq;"""
DECLS_END_NEW = """PCAP_SETFILTER		_pcap_setfilter;

queueADT slirpq;"""

# 3. ------------------------------------------------------------ backend choice
NETTYPE_OLD = """#ifdef _WIN32
        net_is_slirp = (config_get_int(CFG_GLOBAL, NULL, "net_type", NET_SLIRP) == NET_SLIRP) ? 1 : 0;"""
NETTYPE_NEW = """        net_is_slirp = (config_get_int(CFG_GLOBAL, NULL, "net_type", NET_SLIRP) == NET_SLIRP) ? 1 : 0;"""

NETTYPE_END_OLD = """        else if (net_is_slirp == 0)
        	net_is_pcap = 1;
#else
	net_is_slirp = 1;
	net_is_pcap = 0;
#endif"""
NETTYPE_END_NEW = """        else if (net_is_slirp == 0)
        	net_is_pcap = 1;"""

# 4. ---------------------------------------------------------------- transmit
TX_OLD = """#ifdef _WIN32
                        if(net_is_pcap && net_pcap!=NULL)"""
TX_NEW = """                        if(net_is_pcap && net_pcap!=NULL)"""

# 5. ----------------------------------------------------------------- receive
RX_HDR_OLD = """#ifdef _WIN32
        struct pcap_pkthdr h;
#endif"""
RX_HDR_NEW = """        struct pcap_pkthdr h;"""

RX_OLD = """#ifdef _WIN32
        if (net_is_pcap && net_pcap!=NULL)"""
RX_NEW = """        if (net_is_pcap && net_pcap!=NULL)"""

# 7. ------------------------------- close the blocks whose #ifdef we removed
TX_END_OLD = """                        }
#endif
                        ne2000_tx_event(value, ne2000);"""
TX_END_NEW = """                        }
                        ne2000_tx_event(value, ne2000);"""

RX_END_OLD = """                        ne2000_rx_frame(ne2000,data,h.caplen); 
                }
	}
#endif
}"""
RX_END_NEW = """                        ne2000_rx_frame(ne2000,data,h.caplen); 
                }
	}
}"""

LOADER_END_OLD = """        } //end pcap setup
#endif
        pclog("ne2000 is_slirp %d is_pcap %d\\n",net_is_slirp,net_is_pcap);"""
LOADER_END_NEW = """        } //end pcap setup
        pclog("ne2000 is_slirp %d is_pcap %d\\n",net_is_slirp,net_is_pcap);"""

EDITS = [
    (INCLUDE_OLD, INCLUDE_NEW),
    (DECLS_OLD, DECLS_NEW),
    (DECLS_END_OLD, DECLS_END_NEW),
    (NETTYPE_OLD, NETTYPE_NEW),
    (NETTYPE_END_OLD, NETTYPE_END_NEW),
    (TX_OLD, TX_NEW),
    (RX_HDR_OLD, RX_HDR_NEW),
    (RX_OLD, RX_NEW),
    (TX_END_OLD, TX_END_NEW),
    (RX_END_OLD, RX_END_NEW),
    (LOADER_END_OLD, LOADER_END_NEW),
]



LINUX_BINDINGS = """#else
                /* Linux: libpcap is linked in, so bind the same pointers
                   directly instead of resolving them out of a DLL. */
                net_hLib = (void *)1;
                _pcap_lib_version = pcap_lib_version;
                _pcap_open_live   = pcap_open_live;
                _pcap_sendpacket  = pcap_sendpacket;
                _pcap_setnonblock = pcap_setnonblock;
                _pcap_next        = pcap_next;
                _pcap_close       = pcap_close;
                _pcap_getnonblock = pcap_getnonblock;
                _pcap_compile     = pcap_compile;
                _pcap_setfilter   = pcap_setfilter;
#endif
"""


def patch_loader(text):
    """Open the pcap init block on Linux and bind libpcap directly.

    Done line-by-line rather than as one big literal because upstream leaves
    trailing tabs on several of the GetProcAddress lines, which makes an exact
    block match far too fragile.
    """
    lines = text.split("\n")

    opener = None
    for i, line in enumerate(lines):
        if line.strip() == "#ifdef _WIN32" and lines[i + 1].strip() == "if (net_is_pcap)":
            opener = i
            break
    if opener is None:
        sys.exit("ne2000.c: could not find the '#ifdef _WIN32' guarding the pcap init block")
    del lines[opener]

    load = next((i for i, l in enumerate(lines)
                 if "net_hLib = LoadLibraryA(net_lib_name);" in l), None)
    last = next((i for i, l in enumerate(lines)
                 if "_pcap_setfilter=(PCAP_SETFILTER)GetProcAddress" in l), None)
    if load is None or last is None or last < load:
        sys.exit("ne2000.c: could not find the LoadLibrary/GetProcAddress sequence")

    lines.insert(last + 1, LINUX_BINDINGS.rstrip("\n"))
    lines.insert(load, "#ifdef _WIN32")
    return "\n".join(lines)



NET_DEBUG_HELPER = """
/* PCEM_NET_DEBUG=1 traces the PCap receive path. Without it there is no way to
   tell "the frame never reached libpcap" from "PCem read it and dropped it" —
   both look identical from outside: a guest that transmits fine and receives
   nothing. */
static int pcem_net_debug(void)
{
        static int cached = -1;
        if (cached < 0)
        {
                const char *e = getenv("PCEM_NET_DEBUG");
                cached = (e && *e && *e != '0') ? 1 : 0;
        }
        return cached;
}
"""


def instrument_rx(text):
    """Count polls and frames on the PCap receive path, and log what arrives."""
    lines = text.split("\n")

    # helper goes just above ne2000_poller
    poller = next((i for i, l in enumerate(lines)
                   if l.startswith("static void ne2000_poller(")), None)
    if poller is None:
        sys.exit("ne2000.c: could not find ne2000_poller()")
    lines.insert(poller, NET_DEBUG_HELPER)

    nxt = next((i for i, l in enumerate(lines)
                if "data = _pcap_next(net_pcap,&h);" in l), None)
    if nxt is None:
        sys.exit("ne2000.c: could not find the pcap_next call")

    indent = lines[nxt][:len(lines[nxt]) - len(lines[nxt].lstrip())]
    lines.insert(nxt, indent + "static unsigned long pcem_rx_polls = 0, pcem_rx_frames = 0;")
    lines.insert(nxt + 1, indent + "pcem_rx_polls++;")

    # after the `if (data == 0x0) return;` pair, report the frame
    ret = next((i for i, l in enumerate(lines)
                if i > nxt and "if (data == 0x0)" in l), None)
    if ret is None:
        sys.exit("ne2000.c: could not find the pcap_next NULL check")
    trace = (
        indent + "if (pcem_net_debug() && !(pcem_rx_polls % 500000))\n"
        + indent + "        fprintf(stderr, \"netrx idle polls=%lu frames=%lu\\n\", pcem_rx_polls, pcem_rx_frames);\n"
        + indent + "if (data == 0x0)\n"
        + indent + "        return;\n"
        + indent + "pcem_rx_frames++;\n"
        + indent + "if (pcem_net_debug())\n"
        + indent + "{\n"
        + indent + "        fprintf(stderr, \"netrx #%lu len=%u dst=%02x:%02x:%02x:%02x:%02x:%02x \"\n"
        + indent + "                        \"src=%02x:%02x:%02x:%02x:%02x:%02x type=%02x%02x loop=%d tcr=%d\\n\",\n"
        + indent + "                pcem_rx_frames, (unsigned)h.caplen,\n"
        + indent + "                data[0],data[1],data[2],data[3],data[4],data[5],\n"
        + indent + "                data[6],data[7],data[8],data[9],data[10],data[11],\n"
        + indent + "                data[12],data[13],\n"
        + indent + "                (int)ne2000->DCR.loop, (int)ne2000->TCR.loop_cntl);\n"
        + indent + "        fflush(stderr);\n"
        + indent + "}"
    )
    lines[ret] = trace
    del lines[ret + 1]                      # the original bare `return;`
    return "\n".join(lines)


def main():
    path = SRC / "src/ne2000.c"
    text = path.read_text()

    text = patch_loader(text)
    text = instrument_rx(text)

    for old, new in EDITS:
        count = text.count(old)
        if count != 1:
            sys.exit(
                f"src/ne2000.c: expected exactly 1 match for a patch anchor, found {count}\n"
                f"--- anchor ---\n{old}\n"
                "PCem's source shape changed; re-derive this patch."
            )
        text = text.replace(old, new)

    path.write_text(text)
    print("patched src/ne2000.c (PCap backend enabled on Linux)")


if __name__ == "__main__":
    main()
