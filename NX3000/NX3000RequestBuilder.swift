import Foundation

enum NX3000RequestBuilder {
    private static let browsePath = "/smp_4_"
    private static let controlPath = "/mode/control"
    private static let browseSOAPAction = "\"urn:schemas-upnp-org:service:ContentDirectory:1#Browse\""

    static func makeHandshakeRequest(config: NX3000CameraConfig) -> Data {
        joinHTTPLines(
            [
                "HEAD \(controlPath) HTTP/1.0",
                "HOST: http://\(config.cameraIP):\(config.controlPort)",
                "User-Agent: SEC_MODE_\(config.hostMAC)",
                "Access-Method: manual",
                "NTS: alive",
                "Content-Length: 0",
                "HOST-Mac: \(config.hostMAC)",
                "HOST-Address: \(config.hostAddress)",
                "HOST-port: \(config.hostPort)",
                "HOST-PNumber: \(config.hostPNumber)",
            ],
            body: Data()
        )
    }

    static func makeBrowseRequest(
        config: NX3000CameraConfig,
        startingIndex: Int,
        requestedCount: Int,
        objectID: String = "8"
    ) -> Data {
        let payload = makeBrowsePayload(
            objectID: objectID,
            startingIndex: startingIndex,
            requestedCount: requestedCount
        )
        let body = Data(payload.utf8)
        return joinHTTPLines(
            [
                "POST \(browsePath) HTTP/1.0",
                "Content-Type: text/xml; charset=\"utf-8\"",
                "HOST: \(config.cameraIP)",
                "Content-Length: \(body.count)",
                "SOAPACTION: \(browseSOAPAction)",
                "Connection: close",
            ],
            body: body
        )
    }

    private static func makeBrowsePayload(
        objectID: String,
        startingIndex: Int,
        requestedCount: Int
    ) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body>
        <u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
        <ObjectID>\(objectID)</ObjectID>
        <BrowseFlag>BrowseDirectChildren</BrowseFlag>
        <Filter>*</Filter>
        <StartingIndex>\(startingIndex)</StartingIndex>
        <RequestedCount>\(requestedCount)</RequestedCount>
        <SortCriteria></SortCriteria>
        </u:Browse>
        </s:Body>
        </s:Envelope>
        """
    }

    private static func joinHTTPLines(_ lines: [String], body: Data) -> Data {
        var data = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        data.append(body)
        return data
    }
}
