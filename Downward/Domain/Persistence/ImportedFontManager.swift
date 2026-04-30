import CoreText
import Foundation
import Observation
import UIKit

struct ImportedFontRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { postScriptName }

    let displayName: String
    let familyName: String
    let postScriptName: String
    let styleName: String
    let relativePath: String
    let importDate: Date
    let symbolicTraitsRawValue: UInt32

    init(
        displayName: String,
        familyName: String,
        postScriptName: String,
        styleName: String,
        relativePath: String,
        importDate: Date,
        symbolicTraitsRawValue: UInt32
    ) {
        self.displayName = displayName
        self.familyName = familyName
        self.postScriptName = postScriptName
        self.styleName = styleName
        self.relativePath = relativePath
        self.importDate = importDate
        self.symbolicTraitsRawValue = symbolicTraitsRawValue
    }

    private enum CodingKeys: String, CodingKey {
        case displayName
        case familyName
        case postScriptName
        case styleName
        case relativePath
        case importDate
        case symbolicTraitsRawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decode(String.self, forKey: .displayName)
        postScriptName = try container.decode(String.self, forKey: .postScriptName)
        familyName = try container.decodeIfPresent(String.self, forKey: .familyName) ?? displayName
        styleName = try container.decodeIfPresent(String.self, forKey: .styleName) ?? "Regular"
        relativePath = try container.decode(String.self, forKey: .relativePath)
        importDate = try container.decode(Date.self, forKey: .importDate)
        symbolicTraitsRawValue = try container.decodeIfPresent(
            UInt32.self,
            forKey: .symbolicTraitsRawValue
        ) ?? 0
    }
}

struct ImportedFontMetadata: Equatable, Sendable {
    let displayName: String
    let familyName: String
    let postScriptName: String
    let styleName: String
    let symbolicTraitsRawValue: UInt32
}

struct ImportedFontFamily: Equatable, Identifiable, Sendable {
    var id: String { familyName }

    let familyName: String
    let displayName: String
    let records: [ImportedFontRecord]

    var baseRecord: ImportedFontRecord? {
        record(matching: .regular) ?? records.first
    }

    var styleSummary: String {
        records.count == 1 ? "Regular only" : "\(records.count) styles"
    }

    var styleSet: ImportedFontStyleSet? {
        guard let baseRecord else {
            return nil
        }

        return ImportedFontStyleSet(
            familyName: familyName,
            basePostScriptName: baseRecord.postScriptName,
            boldPostScriptName: record(matching: .bold)?.postScriptName,
            italicPostScriptName: record(matching: .italic)?.postScriptName,
            boldItalicPostScriptName: record(matching: .boldItalic)?.postScriptName
        )
    }

    func record(matching style: ImportedFontStyleRequest) -> ImportedFontRecord? {
        switch style {
        case .regular:
            records.first(where: { $0.matchesRegularStyle })
        case .bold:
            records.first(where: { $0.isBoldFace && $0.isItalicFace == false && $0.matchesNamedWeight("bold") })
                ?? records.first(where: { $0.isBoldFace && $0.isItalicFace == false })
        case .italic:
            records.first(where: { $0.isItalicFace && $0.isBoldFace == false })
                ?? records.first(where: { $0.matchesAnyNamedWeight(["italic", "oblique"]) && $0.isBoldFace == false })
        case .boldItalic:
            records.first(where: { $0.isBoldFace && $0.isItalicFace })
                ?? records.first(where: { $0.matchesAnyNamedWeight(["bolditalic", "bold italic", "bold oblique"]) })
        }
    }
}

struct ImportedFontStyleSet: Equatable, Sendable {
    let familyName: String
    let basePostScriptName: String
    let boldPostScriptName: String?
    let italicPostScriptName: String?
    let boldItalicPostScriptName: String?

    func uiFont(for style: ImportedFontStyleRequest, size: CGFloat) -> UIFont? {
        let postScriptName = postScriptName(for: style)
        return UIFont(name: postScriptName, size: size)
    }

    func postScriptName(for style: ImportedFontStyleRequest) -> String {
        switch style {
        case .regular:
            basePostScriptName
        case .bold:
            boldPostScriptName ?? basePostScriptName
        case .italic:
            italicPostScriptName ?? basePostScriptName
        case .boldItalic:
            boldItalicPostScriptName ?? boldPostScriptName ?? italicPostScriptName ?? basePostScriptName
        }
    }
}

enum ImportedFontStyleRequest: CaseIterable, Equatable, Identifiable, Sendable {
    case regular
    case bold
    case italic
    case boldItalic

    var id: Self { self }

    var displayName: String {
        switch self {
        case .regular:
            "Regular"
        case .bold:
            "Bold"
        case .italic:
            "Italic"
        case .boldItalic:
            "Bold Italic"
        }
    }
}

enum ImportedFontError: LocalizedError, Equatable {
    case unsupportedFileType
    case unreadableFont
    case registrationFailed(String)
    case deletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            "Choose a .ttf or .otf font file."
        case .unreadableFont:
            "Downward could not read a usable font name from the selected file."
        case let .registrationFailed(reason):
            reason.isEmpty
                ? "Downward could not register the selected font."
                : "Downward could not register the selected font. \(reason)"
        case let .deletionFailed(reason):
            reason.isEmpty
                ? "Downward could not delete the selected font."
                : "Downward could not delete the selected font. \(reason)"
        }
    }
}

@MainActor
@Observable
final class ImportedFontManager {
    typealias RegisterFont = (URL) -> ImportedFontRegistrationResult
    typealias UnregisterFont = (URL) -> ImportedFontRegistrationResult
    typealias ExtractMetadata = (URL) -> ImportedFontMetadata?

    private let fileManager: FileManager
    private let fontsDirectory: URL
    private let metadataURL: URL
    private let registerFont: RegisterFont
    private let unregisterFont: UnregisterFont
    private let extractMetadata: ExtractMetadata
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private(set) var records: [ImportedFontRecord]
    var lastError: String?

    var families: [ImportedFontFamily] {
        Dictionary(grouping: records, by: \.familyName)
            .map { familyName, records in
                let sortedRecords = records.sorted { lhs, rhs in
                    lhs.styleSortKey < rhs.styleSortKey
                }
                return ImportedFontFamily(
                    familyName: familyName,
                    displayName: sortedRecords.first?.familyName ?? familyName,
                    records: sortedRecords
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    init(
        fontsDirectory: URL? = nil,
        metadataFileName: String = "ImportedFonts.json",
        fileManager: FileManager = .default,
        registerFont: RegisterFont? = nil,
        unregisterFont: UnregisterFont? = nil,
        extractMetadata: ExtractMetadata? = nil
    ) {
        let fontsDirectory = fontsDirectory ?? ImportedFontManager.defaultFontsDirectory()
        self.fileManager = fileManager
        self.fontsDirectory = fontsDirectory
        self.metadataURL = fontsDirectory.appending(path: metadataFileName)
        self.registerFont = registerFont ?? ImportedFontManager.registerFontWithCoreText
        self.unregisterFont = unregisterFont ?? ImportedFontManager.unregisterFontWithCoreText
        self.extractMetadata = extractMetadata ?? ImportedFontManager.extractMetadataWithCoreText
        self.records = Self.loadRecords(
            from: fontsDirectory.appending(path: metadataFileName),
            fileManager: fileManager,
            decoder: decoder
        )
    }

    func registerAllFonts() {
        guard
            let fontURLs = try? fileManager.contentsOfDirectory(
                at: fontsDirectory,
                includingPropertiesForKeys: nil
            )
        else {
            return
        }

        for fontURL in fontURLs where Self.isSupportedFontURL(fontURL) {
            _ = registerFont(fontURL)
        }
    }

    @discardableResult
    func importFont(from sourceURL: URL) async -> ImportedFontRecord? {
        do {
            let record = try importFontRecord(from: sourceURL)
            lastError = nil
            return record
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func importFonts(from sourceURLs: [URL]) async -> [ImportedFontRecord] {
        var importedRecords: [ImportedFontRecord] = []
        var errors: [String] = []

        for sourceURL in sourceURLs {
            do {
                importedRecords.append(try importFontRecord(from: sourceURL))
            } catch {
                errors.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }

        lastError = errors.first
        if errors.isEmpty {
            lastError = nil
        }
        return importedRecords
    }

    func record(withPostScriptName postScriptName: String) -> ImportedFontRecord? {
        records.first { $0.postScriptName == postScriptName }
    }

    func family(named familyName: String) -> ImportedFontFamily? {
        families.first { $0.familyName == familyName }
    }

    func fontFileExists(for record: ImportedFontRecord) -> Bool {
        let fontURL = fontsDirectory.appending(path: record.relativePath)
        return fileManager.fileExists(atPath: fontURL.path)
    }

    @discardableResult
    func deleteFamily(named familyName: String) -> Bool {
        guard let family = family(named: familyName) else {
            lastError = nil
            return true
        }

        return deleteRecords(family.records)
    }

    @discardableResult
    func deleteRecord(withPostScriptName postScriptName: String) -> Bool {
        guard let record = record(withPostScriptName: postScriptName) else {
            lastError = nil
            return true
        }

        return deleteRecords([record])
    }

    private func importFontRecord(from sourceURL: URL) throws -> ImportedFontRecord {
        guard Self.isSupportedFontURL(sourceURL) else {
            throw ImportedFontError.unsupportedFileType
        }

        try fileManager.createDirectory(
            at: fontsDirectory,
            withIntermediateDirectories: true
        )

        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let destinationFileName = uniqueDestinationFileName(for: sourceURL)
        let destinationURL = fontsDirectory.appending(path: destinationFileName)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        do {
            guard let metadata = extractMetadata(destinationURL) else {
                throw ImportedFontError.unreadableFont
            }

            if let duplicate = records.first(where: { $0.postScriptName == metadata.postScriptName }) {
                if fontFileExists(for: duplicate) {
                    try? fileManager.removeItem(at: destinationURL)
                    return duplicate
                }

                records.removeAll { $0.postScriptName == metadata.postScriptName }
            }

            let registrationResult = registerFont(destinationURL)
            guard
                registrationResult.didRegister
                    || Self.isRuntimeFontAvailable(metadata.postScriptName)
            else {
                throw ImportedFontError.registrationFailed(registrationResult.errorDescription ?? "")
            }

            let record = ImportedFontRecord(
                displayName: metadata.displayName,
                familyName: metadata.familyName,
                postScriptName: metadata.postScriptName,
                styleName: metadata.styleName,
                relativePath: destinationFileName,
                importDate: Date(),
                symbolicTraitsRawValue: metadata.symbolicTraitsRawValue
            )
            records.append(record)
            records.sort { lhs, rhs in
                if lhs.familyName.localizedCaseInsensitiveCompare(rhs.familyName) == .orderedSame {
                    return lhs.styleSortKey < rhs.styleSortKey
                }
                return lhs.familyName.localizedCaseInsensitiveCompare(rhs.familyName) == .orderedAscending
            }
            persistRecords()
            return record
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    private func uniqueDestinationFileName(for sourceURL: URL) -> String {
        let ext = sourceURL.pathExtension.lowercased()
        let safeExtension = ["ttf", "otf"].contains(ext) ? ext : "font"
        return "\(UUID().uuidString).\(safeExtension)"
    }

    private func deleteRecords(_ recordsToDelete: [ImportedFontRecord]) -> Bool {
        guard recordsToDelete.isEmpty == false else {
            lastError = nil
            return true
        }

        for record in recordsToDelete {
            let fontURL = fontsDirectory.appending(path: record.relativePath)
            guard fileManager.fileExists(atPath: fontURL.path) else {
                continue
            }

            _ = unregisterFont(fontURL)

            do {
                try fileManager.removeItem(at: fontURL)
            } catch {
                lastError = ImportedFontError.deletionFailed(error.localizedDescription).errorDescription
                return false
            }
        }

        let deletedPostScriptNames = Set(recordsToDelete.map(\.postScriptName))
        records.removeAll { deletedPostScriptNames.contains($0.postScriptName) }
        persistRecords()
        lastError = nil
        return true
    }

    private func persistRecords() {
        do {
            try fileManager.createDirectory(
                at: fontsDirectory,
                withIntermediateDirectories: true
            )
            try encoder.encode(records).write(to: metadataURL, options: .atomic)
        } catch {
            lastError = "Downward could not save imported font metadata."
        }
    }

    nonisolated private static func loadRecords(
        from metadataURL: URL,
        fileManager: FileManager,
        decoder: JSONDecoder
    ) -> [ImportedFontRecord] {
        guard
            fileManager.fileExists(atPath: metadataURL.path),
            let data = try? Data(contentsOf: metadataURL),
            let records = try? decoder.decode([ImportedFontRecord].self, from: data)
        else {
            return []
        }

        return records
    }

    nonisolated private static func defaultFontsDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupport.appending(path: "ImportedFonts", directoryHint: .isDirectory)
    }

    nonisolated private static func isSupportedFontURL(_ url: URL) -> Bool {
        ["ttf", "otf"].contains(url.pathExtension.lowercased())
    }

    nonisolated private static func registerFontWithCoreText(_ url: URL) -> ImportedFontRegistrationResult {
        var unmanagedError: Unmanaged<CFError>?
        let didRegister = CTFontManagerRegisterFontsForURL(
            url as CFURL,
            .process,
            &unmanagedError
        )

        let errorDescription = unmanagedError?
            .takeRetainedValue()
            .localizedDescription

        return ImportedFontRegistrationResult(
            didRegister: didRegister,
            errorDescription: errorDescription
        )
    }

    nonisolated private static func unregisterFontWithCoreText(_ url: URL) -> ImportedFontRegistrationResult {
        var unmanagedError: Unmanaged<CFError>?
        let didUnregister = CTFontManagerUnregisterFontsForURL(
            url as CFURL,
            .process,
            &unmanagedError
        )

        let errorDescription = unmanagedError?
            .takeRetainedValue()
            .localizedDescription

        return ImportedFontRegistrationResult(
            didRegister: didUnregister,
            errorDescription: errorDescription
        )
    }

    nonisolated private static func extractMetadataWithCoreText(_ url: URL) -> ImportedFontMetadata? {
        guard
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
            let descriptor = descriptors.first,
            let postScriptName = CTFontDescriptorCopyAttribute(
                descriptor,
                kCTFontNameAttribute
            ) as? String
        else {
            return nil
        }

        let displayName = CTFontDescriptorCopyAttribute(
            descriptor,
            kCTFontDisplayNameAttribute
        ) as? String
        let familyName = CTFontDescriptorCopyAttribute(
            descriptor,
            kCTFontFamilyNameAttribute
        ) as? String
        let styleName = CTFontDescriptorCopyAttribute(
            descriptor,
            kCTFontStyleNameAttribute
        ) as? String
        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        let symbolicTraitsRawValue = CTFontGetSymbolicTraits(font).rawValue

        return ImportedFontMetadata(
            displayName: displayName ?? postScriptName,
            familyName: familyName ?? displayName ?? postScriptName,
            postScriptName: postScriptName,
            styleName: styleName ?? "Regular",
            symbolicTraitsRawValue: symbolicTraitsRawValue
        )
    }

    nonisolated private static func isRuntimeFontAvailable(_ postScriptName: String) -> Bool {
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        return (CTFontCopyPostScriptName(font) as String) == postScriptName
    }
}

private extension ImportedFontRecord {
    var symbolicTraits: CTFontSymbolicTraits {
        CTFontSymbolicTraits(rawValue: symbolicTraitsRawValue)
    }

    var isBoldFace: Bool {
        symbolicTraits.contains(.traitBold) || matchesAnyNamedWeight(["bold", "black", "heavy"])
    }

    var isItalicFace: Bool {
        symbolicTraits.contains(.traitItalic) || matchesAnyNamedWeight(["italic", "oblique"])
    }

    var matchesRegularStyle: Bool {
        let normalized = normalizedStyleName
        return normalized == "regular"
            || normalized == "roman"
            || normalized == "book"
            || normalized == "normal"
    }

    var styleSortKey: String {
        if matchesRegularStyle { return "00-\(displayName)" }
        if isBoldFace && isItalicFace { return "30-\(displayName)" }
        if isBoldFace { return "10-\(displayName)" }
        if isItalicFace { return "20-\(displayName)" }
        return "40-\(displayName)"
    }

    func matchesNamedWeight(_ weight: String) -> Bool {
        normalizedStyleName.contains(weight.normalizedFontStyleToken)
            || displayName.normalizedFontStyleToken.contains(weight.normalizedFontStyleToken)
            || postScriptName.normalizedFontStyleToken.contains(weight.normalizedFontStyleToken)
    }

    func matchesAnyNamedWeight(_ weights: [String]) -> Bool {
        weights.contains { matchesNamedWeight($0) }
    }

    private var normalizedStyleName: String {
        styleName.normalizedFontStyleToken
    }
}

private extension String {
    var normalizedFontStyleToken: String {
        lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ImportedFontRegistrationResult: Equatable, Sendable {
    let didRegister: Bool
    let errorDescription: String?

    static let success = ImportedFontRegistrationResult(
        didRegister: true,
        errorDescription: nil
    )
}
