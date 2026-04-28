import Foundation

/// Central policy for file types that should appear in the workspace browser.
enum SupportedFileType: String, CaseIterable, Sendable {
    case markdown = "md"
    case markdownText = "markdown"
    case plainText = "txt"
    case json = "json"
    case swift = "swift"
    case html = "html"
    case htm = "htm"
    case css = "css"
    case javascript = "js"
    case typescript = "ts"
    case jsx = "jsx"
    case tsx = "tsx"
    case python = "py"
    case ruby = "rb"
    case go = "go"
    case rust = "rs"
    case c = "c"
    case header = "h"
    case cpp = "cpp"
    case cxx = "cxx"
    case cc = "cc"
    case hpp = "hpp"
    case objectiveC = "m"
    case objectiveCpp = "mm"
    case java = "java"
    case kotlin = "kt"
    case kotlinScript = "kts"
    case shell = "sh"
    case zsh = "zsh"
    case bash = "bash"
    case yaml = "yaml"
    case yml = "yml"
    case toml = "toml"
    case xml = "xml"
    case csv = "csv"
    case tsv = "tsv"
    case log = "log"
    case ini = "ini"
    case conf = "conf"

    nonisolated static func isSupported(url: URL) -> Bool {
        guard url.hasDirectoryPath == false else {
            return false
        }

        return isSupportedExtension(url.pathExtension)
    }

    nonisolated static func isSupportedExtension(_ fileExtension: String) -> Bool {
        Self(rawValue: fileExtension.lowercased()) != nil
    }
}
