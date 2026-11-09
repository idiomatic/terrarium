import Foundation

/// Writes all of `data` to a descriptor; false when it could not.
@discardableResult
public func writeAll(_ fd: Int32, _ data: Data) -> Bool {
    data.withUnsafeBytes { raw in
        var done = 0
        while done < raw.count {
            let n = write(fd, raw.baseAddress! + done, raw.count - done)
            if n <= 0 { return false }
            done += n
        }
        return true
    }
}

/// Whether a process exists (a zombie counts, so a parent that started it must reap it).
public func processIsAlive(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0 || errno != ESRCH
}
