import Foundation

/// Centralized utility for resolving application paths across macOS app bundles and command-line execution.
public struct AppPaths: Sendable {
    /// macOS Application Support directory for Yue2Studio
    public static var appSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Yue2Studio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: appSupport.path) {
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        return appSupport
    }

    /// Base directory for models and generations
    /// Base directory for models and generations
    public static var baseDirectory: URL {
        let isAppBundle = Bundle.main.bundleURL.pathExtension == "app"
        if isAppBundle {
            let bundleParent = Bundle.main.bundleURL.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: bundleParent.appendingPathComponent("Models").path) {
                return bundleParent
            }
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if FileManager.default.fileExists(atPath: cwd.appendingPathComponent("Models").path) {
            return cwd
        }
        let projectDir = URL(fileURLWithPath: "/Users/ngkarchai/Documents/MyProjects/Yue2Studio")
        if FileManager.default.fileExists(atPath: projectDir.appendingPathComponent("Models").path) {
            return projectDir
        }
        return appSupportDirectory
    }

    /// Resolves the SQLite database file path.
    /// Uses Application Support directory to conform to macOS conventions and avoid TCC security stalls.
    public static var databasePath: String {
        let appSupportDB = appSupportDirectory.appendingPathComponent("storage.sqlite3")

        // If it doesn't exist in Application Support yet, but exists next to the app bundle or in cwd, copy it as seed
        if !FileManager.default.fileExists(atPath: appSupportDB.path) {
            let bundleParentDB = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("storage.sqlite3")
            if FileManager.default.fileExists(atPath: bundleParentDB.path) {
                try? FileManager.default.copyItem(at: bundleParentDB, to: appSupportDB)
            } else {
                let projectDB = URL(fileURLWithPath: "/Users/ngkarchai/Documents/MyProjects/Yue2Studio/storage.sqlite3")
                if FileManager.default.fileExists(atPath: projectDB.path) {
                    try? FileManager.default.copyItem(at: projectDB, to: appSupportDB)
                }
            }
        }

        return appSupportDB.path
    }

    /// Resolves a path string to an absolute path, using baseDirectory if relative.
    public static func resolvePath(_ path: String) -> String {
        if (path as NSString).isAbsolutePath {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        let candidate = baseDirectory.appendingPathComponent(path).path
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        let projectCandidate = "/Users/ngkarchai/Documents/MyProjects/Yue2Studio/\(path)"
        if FileManager.default.fileExists(atPath: projectCandidate) {
            return projectCandidate
        }
        return candidate
    }

    /// Resolves a path string to an absolute URL, using baseDirectory if relative.
    public static func resolveURL(_ path: String) -> URL {
        return URL(fileURLWithPath: resolvePath(path))
    }

    /// Default models directory URL
    public static var defaultModelsURL: URL {
        let candidate = baseDirectory.appendingPathComponent("Models", isDirectory: true)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        let projectCandidate = URL(fileURLWithPath: "/Users/ngkarchai/Documents/MyProjects/Yue2Studio/Models", isDirectory: true)
        if FileManager.default.fileExists(atPath: projectCandidate.path) {
            return projectCandidate
        }
        let appSupportModels = appSupportDirectory.appendingPathComponent("Models", isDirectory: true)
        if !FileManager.default.fileExists(atPath: appSupportModels.path) {
            try? FileManager.default.createDirectory(at: appSupportModels, withIntermediateDirectories: true)
        }
        return appSupportModels
    }

    /// Default generations directory URL
    public static var defaultGenerationsURL: URL {
        let candidate = baseDirectory.appendingPathComponent("Generations", isDirectory: true)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        let projectCandidate = URL(fileURLWithPath: "/Users/ngkarchai/Documents/MyProjects/Yue2Studio/Generations", isDirectory: true)
        if FileManager.default.fileExists(atPath: projectCandidate.path) {
            return projectCandidate
        }
        let appSupportGen = appSupportDirectory.appendingPathComponent("Generations", isDirectory: true)
        if !FileManager.default.fileExists(atPath: appSupportGen.path) {
            try? FileManager.default.createDirectory(at: appSupportGen, withIntermediateDirectories: true)
        }
        return candidate
    }
}
