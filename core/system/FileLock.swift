import Foundation

/// Opens the lock file at `path` (making it) and takes `operation` on it (`LOCK_EX` or `LOCK_SH`, with `LOCK_NB` not to
/// wait); returns the descriptor, or nil when another holds it and `LOCK_NB` was given. A lock file may be removed while
/// another process is taking it, which would then hold a lock on a file no longer at the path, so the file locked is
/// checked to be the one at the path, and taken again if it is not.
func lockFile(_ path: String, _ operation: Int32) throws -> Int32? {
    while true {
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CLIError.failure("cannot open \(path): \(String(cString: strerror(errno)))") }
        guard flock(fd, operation) == 0 else {
            let why = errno
            close(fd)
            if why == EWOULDBLOCK { return nil }
            throw CLIError.failure("cannot lock \(path): \(String(cString: strerror(why)))")
        }
        var locked = stat(), named = stat()
        if fstat(fd, &locked) == 0, stat(path, &named) == 0, locked.st_dev == named.st_dev, locked.st_ino == named.st_ino { return fd }
        close(fd)
    }
}
