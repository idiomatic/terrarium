"""Checks of `pull`'s qcow2 conversion and tar extraction with synthetic images. Usage: pull.py BINARY
Each image it pulls is removed again with `rmi`."""
import gzip, io, os, queue, struct, subprocess, sys, tarfile, tempfile, time, zlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from client import Checks, Client

binary = sys.argv[1]
# A support directory of its own, so the user's images, VMs, and caches are never touched.
os.environ["TERRARIUM_SUPPORT"] = tempfile.mkdtemp(prefix="terrarium-support-")
check = Checks()
CS = 1 << 16
store = os.path.join(os.environ["TERRARIUM_SUPPORT"], "images")


def qcow2(backing=False, incompatible=0, header_length=112, l1_offset=CS, l1_size=1, eof=False):
    """Guest clusters: 0 plain, 1 zlib, 2 zero flag, 3 unallocated, 4 plain and cut short.
    A 104-byte header is followed by a backing-format extension, whose magic starts at byte 104. With `eof`, the file ends
    inside the compressed cluster's last sector, and cluster 4 is unallocated."""
    size = 4 * CS + 1000
    plain0, plain4 = os.urandom(CS), os.urandom(CS)
    cluster1 = (b"terrarium " * 6000)[:CS].ljust(CS, b"\0")
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    packed1 = c.compress(cluster1) + c.flush()
    header = struct.pack(">IIQIIQIIQQIIQ", 0x514649FB, 3, 0x200 if backing else 0, 0, 16, size, 0, l1_size, l1_offset, 0, 0, 0, 0)
    header += struct.pack(">QQQII", incompatible, 0, 0, 4, header_length)
    if header_length == 104:
        header = header[:104] + struct.pack(">II", 0xE2792ACA, 0)
    img = bytearray(6 * CS + 0x1000)
    img[:len(header)] = header
    struct.pack_into(">Q", img, CS, 2 * CS)
    sectors = (len(packed1) - 1) // 512
    entries = [3 * CS | 1 << 63, 4 * CS | sectors << 54 | 1 << 62, 1, 0, 0 if eof else 5 * CS | 1 << 63]
    struct.pack_into(">5Q", img, 2 * CS, *entries)
    img[3 * CS:4 * CS] = plain0
    img[4 * CS:4 * CS + len(packed1)] = packed1
    img[5 * CS:6 * CS] = plain4
    expected = plain0 + cluster1 + bytes(2 * CS) + plain4[:1000]
    if eof:
        assert len(packed1) % 512 != 0
        img = img[:4 * CS + len(packed1)]
        expected = plain0 + cluster1 + bytes(2 * CS) + bytes(1000)
    return bytes(img), expected


def pull(data, suffix=".qcow2"):
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as f:
        f.write(data)
    try:
        return subprocess.run([binary, "pull", f.name], capture_output=True, text=True)
    finally:
        os.unlink(f.name)


image, expected = qcow2()
r = pull(image)
name = r.stdout.strip()
check("pull converts a qcow2 image", r.returncode == 0 and name != "", r.stderr)
path = os.path.join(store, name + ".img")
try:
    got = open(path, "rb").read() if os.path.exists(path) else b""
    check("plain, compressed, zero, and unallocated clusters, and the cut-short last one, convert exactly", got == expected, (len(got), len(expected)))
    check("the stored image is not named .qcow2", ".qcow2" not in name, name)
finally:
    if name:
        subprocess.run([binary, "rmi", name], capture_output=True)

def converts(label, **args):
    image, expected = qcow2(**args)
    r = pull(image)
    name = r.stdout.strip()
    try:
        path = os.path.join(store, name + ".img")
        got = open(path, "rb").read() if name and os.path.exists(path) else b""
        check(label, r.returncode == 0 and got == expected, (r.stderr, len(got), len(expected)))
    finally:
        if name:
            subprocess.run([binary, "rmi", name], capture_output=True)
converts("a 104-byte version 3 header, followed by an extension, converts", header_length=104)
converts("a file that ends inside the last compressed cluster's sector converts", eof=True)
converts("an L1 table longer than the disk needs is read only as far as it needs", l1_size=1 << 20)
for label, args, expect in [
    ("a backing file", dict(backing=True), "backing file"),
    ("an incompatible feature", dict(incompatible=8), "cannot read"),
    ("an L1 table past the end of the file", dict(l1_offset=1 << 40), "truncated or damaged"),
    ("an L1 offset beyond what a file offset holds", dict(l1_offset=1 << 63), "truncated or damaged"),
]:
    r = pull(qcow2(**args)[0])
    check(label + " is refused", r.returncode != 0 and expect in r.stderr and r.stdout.strip() == "", r.stderr)


def tar_of(members, compress=False):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz" if compress else "w") as t:
        for member, data in members:
            info = tarfile.TarInfo(member)
            info.size = len(data)
            t.addfile(info, io.BytesIO(data))
    return buf.getvalue()


def stored(label, data, suffix, expected):
    r = pull(data, suffix)
    name = r.stdout.strip()
    try:
        path = os.path.join(store, name + ".img")
        got = open(path, "rb").read() if name and os.path.exists(path) else b""
        check(label, r.returncode == 0 and got == expected, (r.stderr, len(got), len(expected)))
    finally:
        if name:
            subprocess.run([binary, "rmi", name], capture_output=True)


disk = os.urandom(CS) + bytes(3 * CS) + os.urandom(1024)
stored("a tar archive of one raw disk, with a zero stretch", tar_of([("disk.raw", disk)]), ".tar", disk)
stored("a .tar.gz of one raw disk", tar_of([("disk.raw", disk)], True), ".tar.gz", disk)
stored("a .tar.gz of a qcow2 image", tar_of([("disk.qcow2", image)], True), ".tar.gz", expected)
r = pull(tar_of([("a.raw", disk), ("b.raw", disk)]), ".tar")
check("a tar archive of several files is refused", r.returncode != 0 and "2 files" in r.stderr and r.stdout.strip() == "", r.stderr)


# `images` shows the hash only where names collide, and every shown name resolves.
tag = "tt" + os.urandom(4).hex()
made = []


def pull_file(name, data):
    folder = tempfile.mkdtemp()
    path = os.path.join(folder, name)
    open(path, "wb").write(data)
    r = subprocess.run([binary, "pull", path], capture_output=True, text=True)
    os.unlink(path)
    os.rmdir(folder)
    made.append(r.stdout.strip())
    return r.stdout.strip()


try:
    same1 = pull_file(tag + "-same.img", os.urandom(1024))
    same2 = pull_file(tag + "-same.img", os.urandom(1024))
    only = pull_file(tag + "-only.img", os.urandom(1024))
    longer = pull_file(tag + "-only-extra.img", os.urandom(1024))
    listing = subprocess.run([binary, "images"], capture_output=True, text=True).stdout
    names = [line.split()[0] for line in listing.splitlines()[1:] if line.startswith(tag)]
    check("images shows the hash only for names that collide", sorted(names) == sorted([same1, same2, tag + "-only", tag + "-only-extra"]), names)
    r = subprocess.run([binary, "rmi", tag + "-same"], capture_output=True, text=True)
    check("a name shared by two images is ambiguous", r.returncode != 0 and "ambiguous" in r.stderr and same1 in r.stderr, r.stderr)
    r = subprocess.run([binary, "rmi", tag + "-only"], capture_output=True, text=True)
    check("a shown name resolves even when it prefixes another image's name", r.returncode == 0, r.stderr)
    check("and it removed that image", not os.path.exists(os.path.join(store, only + ".img")) and os.path.exists(os.path.join(store, longer + ".img")))
finally:
    for name in made:
        if name:
            subprocess.run([binary, "rmi", name], capture_output=True)
# Concurrent pulls in one MCP server: two different files of the same name, and the same file twice.
mc = Client(binary)
folders = [tempfile.mkdtemp() for _ in range(2)]
datas = [os.urandom(1 << 20), os.urandom(1 << 20)]
paths = [os.path.join(folder, "disk.img") for folder in folders]
for path, data in zip(paths, datas):
    open(path, "wb").write(data)
ids = [mc.request("tools/call", {"name": "pull", "arguments": {"source": path}}) for path in paths + [paths[0]]]
replies, end = {}, time.time() + 120
while len(replies) < len(ids) and time.time() < end:
    try:
        message = mc.lines.get(timeout=0.5)
    except queue.Empty:
        continue
    if message.get("id") in ids and "result" in message:
        replies[message["id"]] = message["result"]
mc.close()
names = [replies.get(i, {}).get("content", [{}])[0].get("text", "") for i in ids]
try:
    check("concurrent pulls in one MCP server all succeed", len(replies) == 3 and not any(r.get("isError") for r in replies.values()), replies)
    check("two files of the same name pulled at once are stored apart, each intact",
          names[0] != names[1] and all(open(os.path.join(store, n + ".img"), "rb").read() == d for n, d in zip(names, datas)), names)
    check("the same file pulled twice at once is one image", names[2] == names[0], names)
    check("concurrent pulls leave no scratch files", not [f for f in os.listdir(store) if ".partial." in f], os.listdir(store))
finally:
    for n in set(names):
        if n:
            subprocess.run([binary, "rmi", n], capture_output=True)
    for path, folder in zip(paths, folders):
        os.unlink(path)
        os.rmdir(folder)
import shutil
shutil.rmtree(os.environ["TERRARIUM_SUPPORT"], ignore_errors=True)
check.finish()
