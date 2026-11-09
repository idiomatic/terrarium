import Foundation
import Virtualization

/// What only a macOS guest needs of its owner: the installer, first-boot provisioning, and the helper's installation.
extension Owner {
    /// Runs Apple's installer on the VM's (blank) disk, reporting progress as the VM's state, then calls `done`.
    func installMacOS(from restoreImage: URL, then done: @escaping () -> Void) {
        let installer = VZMacOSInstaller(virtualMachine: vm, restoringFromImageAt: restoreImage)
        // Read and written on the main queue only; the observer itself runs on any thread.
        nonisolated(unsafe) var last = -1
        let observation = installer.progress.observe(\.fractionCompleted) { [self] progress, _ in
            let percent = Int(progress.fractionCompleted * 100)
            DispatchQueue.main.async { [self] in
                guard percent != last else { return }
                last = percent
                info.state = "installing \(percent)%"
                try? Runtime.write(info)
                if percent % 10 == 0 { note("installing macOS: \(percent)%") }
            }
        }
        info.state = "installing 0%"
        try? Runtime.write(info)
        note("installing macOS (this takes a while)")
        installer.install { [self] result in
            observation.invalidate()
            switch result {
            case .success:
                note("macOS is installed; starting it")
                // The installer leaves its VM running, and a running VM cannot be started: finish it, and boot a new one.
                let finishInstall = { [self] in
                    do {
                        plan.mac?.restoreImage = nil
                        try replaceVM()
                        done()
                    } catch {
                        note("terrarium: cannot start the installed system: \((error as? CLIError)?.message ?? "\(error)")")
                        finish(1)
                    }
                }
                if vm.canStop { vm.stop { _ in DispatchQueue.main.async { finishInstall() } } } else { finishInstall() }
            case .failure(let error):
                note("terrarium: the macOS installation failed: \(error.localizedDescription)")
                finish(1)
            }
        }
    }

    /// Starts the VM, giving a first boot the account to create (and no Setup Assistant).
    func startMacOS(first: Bool, then done: @escaping (Result<Void, Error>) -> Void) {
        let options = VZMacOSVirtualMachineStartOptions()
        if first, let account = plan.mac?.account {
            let provisioning = VZMacGuestProvisioningOptions()
            provisioning.fullName = account.username
            provisioning.username = account.username
            provisioning.password = account.password
            provisioning.logsInAutomatically = true
            provisioning.enablesRemoteLogin = true
            do {
                try options.setGuestProvisioning(provisioning)
            } catch {
                return done(.failure(error))
            }
        }
        vm.start(options: options) { error in done(error.map { .failure($0) } ?? .success(())) }
    }

    /// In the background, installs the helper once the guest is up; its notes go to the owner's log. `done` gets, on the
    /// main queue, nil once it is installed or why it is not.
    func installHelperInBackground(_ done: @escaping (String?) -> Void) {
        guard let account = plan.mac?.account else { return done("the guest has no account") }
        guard let helper = Embedded.helper(for: .macos) else { return done("this terrarium has no macOS helper") }
        guard let mac = guestMAC else { return done("the guest has no MAC address") }
        let directory = self.directory
        DispatchQueue.global().async {
            do {
                try MacHelperInstall.run(mac: mac, account: account, helper: helper, in: directory)
                DispatchQueue.main.async { done(nil) }
            } catch {
                let why = (error as? CLIError)?.message ?? "\(error)"
                note("terrarium: cannot install the helper: \(why)")
                DispatchQueue.main.async { done(why) }
            }
        }
    }
}
