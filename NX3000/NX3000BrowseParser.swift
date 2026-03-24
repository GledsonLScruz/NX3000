import Foundation

final class NX3000BrowseParser {
    func parseBrowseResponse(_ responseData: Data) throws -> BrowsePage {
        let responseText = String(decoding: responseData, as: UTF8.self)
        let body = try extractHTTPBody(from: responseText)

        let soapDelegate = SOAPBrowseResponseDelegate()
        let soapParser = XMLParser(data: Data(body.utf8))
        soapParser.delegate = soapDelegate
        soapParser.shouldProcessNamespaces = false

        guard soapParser.parse() else {
            throw soapDelegate.capturedError ?? NX3000Error.parseFailed(soapParser.parserError?.localizedDescription ?? "SOAP parsing failed.")
        }

        let embeddedXML = decodeXMLEntities(soapDelegate.embeddedDIDL)
        let didlDelegate = DIDLItemsDelegate()
        let didlParser = XMLParser(data: Data(embeddedXML.utf8))
        didlParser.delegate = didlDelegate
        didlParser.shouldProcessNamespaces = false

        guard didlParser.parse() else {
            throw didlDelegate.capturedError ?? NX3000Error.parseFailed(didlParser.parserError?.localizedDescription ?? "DIDL parsing failed.")
        }

        return BrowsePage(
            items: didlDelegate.items,
            numberReturned: soapDelegate.numberReturned ?? didlDelegate.items.count,
            totalMatches: soapDelegate.totalMatches
        )
    }

    private func extractHTTPBody(from responseText: String) throws -> String {
        if let range = responseText.range(of: "\r\n\r\n") {
            return String(responseText[range.upperBound...])
        }
        if let range = responseText.range(of: "\n\n") {
            return String(responseText[range.upperBound...])
        }
        throw NX3000Error.missingHTTPBody
    }

    private func decodeXMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

private final class SOAPBrowseResponseDelegate: NSObject, XMLParserDelegate {
    var embeddedDIDL = ""
    var numberReturned: Int?
    var totalMatches: Int?
    var capturedError: NX3000Error?

    private var currentElement = ""
    private var currentText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName.localName
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let element = elementName.localName
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch element {
        case "Result":
            embeddedDIDL.append(trimmed)
        case "NumberReturned":
            numberReturned = Int(trimmed)
        case "TotalMatches":
            totalMatches = Int(trimmed)
        default:
            break
        }

        currentElement = ""
        currentText = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        capturedError = NX3000Error.parseFailed(parseError.localizedDescription)
    }
}

private final class DIDLItemsDelegate: NSObject, XMLParserDelegate {
    private struct Resource {
        let url: URL
        let protocolInfo: String
    }

    private struct PartialItem {
        var title = ""
        var date = ""
        var resources: [Resource] = []
    }

    var items: [MediaAsset] = []
    var capturedError: NX3000Error?

    private var currentItem: PartialItem?
    private var currentText = ""
    private var currentResourceProtocolInfo: String?
    private let isoFormatter = ISO8601DateFormatter()
    private lazy var fallbackFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
    private lazy var dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""
        let element = elementName.localName

        if element == "item" {
            currentItem = PartialItem()
        } else if element == "res" {
            currentResourceProtocolInfo = attributeDict["protocolInfo"]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let element = elementName.localName
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch element {
        case "title":
            currentItem?.title = trimmed
        case "date":
            currentItem?.date = trimmed
        case "res":
            if let protocolInfo = currentResourceProtocolInfo,
               let url = URL(string: trimmed),
               !trimmed.isEmpty {
                currentItem?.resources.append(Resource(url: url, protocolInfo: protocolInfo))
            }
            currentResourceProtocolInfo = nil
        case "item":
            do {
                guard let currentItem else {
                    throw NX3000Error.parseFailed("Missing media item payload.")
                }
                items.append(try makeAsset(from: currentItem))
            } catch let error as NX3000Error {
                capturedError = error
                parser.abortParsing()
            } catch {
                capturedError = NX3000Error.parseFailed(error.localizedDescription)
                parser.abortParsing()
            }
            self.currentItem = nil
        default:
            break
        }

        currentText = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if capturedError == nil {
            capturedError = NX3000Error.parseFailed(parseError.localizedDescription)
        }
    }

    private func makeAsset(from item: PartialItem) throws -> MediaAsset {
        guard let primary = item.resources.first else {
            throw NX3000Error.parseFailed("Media item has no resource URLs.")
        }

        let parts = primary.protocolInfo.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count >= 4 else {
            throw NX3000Error.parseFailed("Malformed protocolInfo: \(primary.protocolInfo)")
        }

        let mimeParts = parts[2].split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard mimeParts.count == 2 else {
            throw NX3000Error.parseFailed("Malformed MIME type: \(primary.protocolInfo)")
        }

        let mediaType: MediaAssetType
        switch String(mimeParts[0]).lowercased() {
        case "image":
            mediaType = .image
        case "video":
            mediaType = .video
        default:
            throw NX3000Error.parseFailed("Unsupported media type: \(mimeParts[0])")
        }

        let normalizedDate = item.date.replacingOccurrences(of: "Z", with: "+00:00")
        let parsedDate =
            isoFormatter.date(from: normalizedDate) ??
            fallbackFormatter.date(from: item.date) ??
            dateOnlyFormatter.date(from: item.date)
        guard let date = parsedDate else {
            throw NX3000Error.parseFailed("Unsupported date format: \(item.date)")
        }

        return MediaAsset(
            title: item.title.isEmpty ? "Untitled" : item.title,
            date: date,
            type: mediaType,
            fullContentURL: primary.url,
            thumbnailURL: item.resources.count > 1 ? item.resources[1].url : nil,
            screenImageURL: mediaType == .image && item.resources.count > 2 ? item.resources[2].url : nil,
            fileExtension: String(mimeParts[1]).lowercased(),
            protocolInfo: primary.protocolInfo
        )
    }
}

private extension String {
    var localName: String {
        if let lastColon = lastIndex(of: ":") {
            return String(self[index(after: lastColon)...])
        }
        return self
    }
}
