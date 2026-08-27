import Foundation
import Testing
@testable import UPnPMediaTarget

@Suite("UPnP RenderingControl SCPD parser")
struct UPnPMediaTargetSCPDParserTests {
    @Test("Selects the exact Volume state variable")
    func selectsVolumeStateVariable() throws {
        let capability = try parse(
            stateVariables: """
            <stateVariable>
              <name>VolumeDB</name>
              <dataType>i2</dataType>
              <allowedValueRange><minimum>-10</minimum><maximum>10</maximum></allowedValueRange>
            </stateVariable>
            <stateVariable>
              <name>Volume</name>
              <dataType>ui2</dataType>
              <allowedValueRange><minimum>5</minimum><maximum>95</maximum><step>5</step></allowedValueRange>
            </stateVariable>
            """
        )

        #expect(capability.minimumVolume == 5)
        #expect(capability.maximumVolume == 95)
        #expect(capability.step == 5)
    }

    @Test("Defaults the RenderingControl minimum and step")
    func defaultsSpecValues() throws {
        let capability = try parse(
            stateVariables: """
            <stateVariable>
              <name>Volume</name>
              <dataType>ui2</dataType>
              <allowedValueRange><maximum>100</maximum></allowedValueRange>
            </stateVariable>
            """
        )

        #expect(capability.minimumVolume == 0)
        #expect(capability.maximumVolume == 100)
        #expect(capability.step == 1)
    }

    @Test("Requires a maximum and an allowed value range")
    func requiresRangeMetadata() {
        let missingMaximum = """
        <stateVariable><name>Volume</name><dataType>ui2</dataType>
          <allowedValueRange><minimum>0</minimum></allowedValueRange>
        </stateVariable>
        """
        #expect(throws: UPnPMediaTargetError.missingVolumeCapability) {
            try parse(stateVariables: missingMaximum)
        }

        let missingRange = """
        <stateVariable><name>Volume</name><dataType>ui2</dataType></stateVariable>
        """
        #expect(throws: UPnPMediaTargetError.missingVolumeCapability) {
            try parse(stateVariables: missingRange)
        }
    }

    @Test("Rejects action arguments, duplicates, wrong datatypes, and malformed numbers")
    func rejectsAmbiguousOrUnsafeVolumeMetadata() {
        let actionOnly = """
        <action><argument><name>Volume</name><relatedStateVariable>Volume</relatedStateVariable></argument></action>
        """
        #expect(throws: UPnPMediaTargetError.missingVolumeCapability) {
            try parse(stateVariables: actionOnly)
        }

        let duplicate = """
        <stateVariable><name>Volume</name><dataType>ui2</dataType>
          <allowedValueRange><maximum>100</maximum></allowedValueRange>
        </stateVariable>
        <stateVariable><name>Volume</name><dataType>ui2</dataType>
          <allowedValueRange><maximum>100</maximum></allowedValueRange>
        </stateVariable>
        """
        #expect(throws: UPnPMediaTargetError.invalidVolumeCapability) {
            try parse(stateVariables: duplicate)
        }

        let wrongType = """
        <stateVariable><name>Volume</name><dataType>i2</dataType>
          <allowedValueRange><maximum>100</maximum></allowedValueRange>
        </stateVariable>
        """
        #expect(throws: UPnPMediaTargetError.invalidVolumeCapability) {
            try parse(stateVariables: wrongType)
        }

        let malformedNumber = """
        <stateVariable><name>Volume</name><dataType>ui2</dataType>
          <allowedValueRange><maximum>10.0</maximum></allowedValueRange>
        </stateVariable>
        """
        #expect(throws: UPnPMediaTargetError.invalidVolumeCapability) {
            try parse(stateVariables: malformedNumber)
        }

        let duplicateRange = """
        <stateVariable><name>Volume</name><dataType>ui2</dataType>
          <allowedValueRange><maximum>100</maximum></allowedValueRange>
          <allowedValueRange><maximum>100</maximum></allowedValueRange>
        </stateVariable>
        """
        #expect(throws: UPnPMediaTargetError.invalidVolumeCapability) {
            try parse(stateVariables: duplicateRange)
        }

        let misplacedRange = """
        <stateVariable><name>Volume</name><dataType>ui2</dataType>
          <allowedValueRange><maximum>100</maximum></allowedValueRange>
          <allowedValueList>
            <allowedValueRange><minimum>50</minimum><step>7</step></allowedValueRange>
          </allowedValueList>
        </stateVariable>
        """
        #expect(throws: UPnPMediaTargetError.invalidVolumeCapability) {
            try parse(stateVariables: misplacedRange)
        }

        for invalidMaximum in ["", "+5", "1 2", "100000"] {
            let invalidNumber = """
            <stateVariable><name>Volume</name><dataType>ui2</dataType>
              <allowedValueRange><maximum>\(invalidMaximum)</maximum></allowedValueRange>
            </stateVariable>
            """
            #expect(throws: UPnPMediaTargetError.invalidVolumeCapability) {
                try parse(stateVariables: invalidNumber)
            }
        }

        let nestedStateVariable = """
        <stateVariable><name>Volume</name><dataType>ui2</dataType>
          <stateVariable>
            <allowedValueRange><maximum>100</maximum></allowedValueRange>
          </stateVariable>
        </stateVariable>
        """
        #expect(throws: UPnPMediaTargetError.invalidVolumeCapability) {
            try parse(stateVariables: nestedStateVariable)
        }
    }

    @Test("Namespaced service descriptions use local element names")
    func parsesNamespacedServiceDescription() throws {
        let xml = Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <u:scpd xmlns:u="urn:schemas-upnp-org:service-1-0">
              <u:serviceStateTable>
                <u:stateVariable>
                  <u:name>Volume</u:name>
                  <u:dataType>ui2</u:dataType>
                  <u:allowedValueRange>
                    <u:minimum>0</u:minimum>
                    <u:maximum>30</u:maximum>
                    <u:step>3</u:step>
                  </u:allowedValueRange>
                </u:stateVariable>
              </u:serviceStateTable>
            </u:scpd>
            """.utf8
        )

        let capability = try UPnPMediaTargetSCPDParser.parse(xml)

        #expect(capability.minimumVolume == 0)
        #expect(capability.maximumVolume == 30)
        #expect(capability.step == 3)
    }

    @Test("Enforces XML complexity bounds")
    func enforcesComplexityBounds() {
        let depth = String(repeating: "<nested>", count: UPnPMediaTargetSCPDParser.defaultMaximumDepth + 1)
            + "<stateVariable><name>Volume</name><dataType>ui2</dataType><allowedValueRange><maximum>100</maximum></allowedValueRange></stateVariable>"
            + String(repeating: "</nested>", count: UPnPMediaTargetSCPDParser.defaultMaximumDepth + 1)
        #expect(throws: UPnPMediaTargetError.malformedXML) {
            try parse(stateVariables: depth)
        }

        let variables = (0...UPnPMediaTargetSCPDParser.defaultMaximumStateVariableCount).map { index in
            "<stateVariable><name>Other\(index)</name><dataType>ui2</dataType></stateVariable>"
        }.joined()
        #expect(throws: UPnPMediaTargetError.malformedXML) {
            try parse(stateVariables: variables)
        }
    }

    @Test("Rejects malformed and oversized service descriptions")
    func rejectsMalformedAndOversizedPayloads() {
        #expect(throws: UPnPMediaTargetError.malformedXML) {
            try UPnPMediaTargetSCPDParser.parse(Data("<scpd>".utf8))
        }

        let oversized = Data(repeating: 0x41, count: UPnPMediaTargetSCPDParser.defaultMaximumPayloadBytes + 1)
        #expect(throws: UPnPMediaTargetError.oversizedPayload) {
            try UPnPMediaTargetSCPDParser.parse(oversized)
        }

        let doctype = Data("<!DOCTYPE scpd><scpd/>".utf8)
        #expect(throws: UPnPMediaTargetError.forbiddenMarkup) {
            try UPnPMediaTargetSCPDParser.parse(doctype)
        }
    }

    private func parse(stateVariables: String) throws -> UPnPMediaTargetVolumeCapability {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <scpd>
          <actionList>
            <action><argument><name>Volume</name></argument></action>
          </actionList>
          <serviceStateTable>
            \(stateVariables)
          </serviceStateTable>
        </scpd>
        """
        return try UPnPMediaTargetSCPDParser.parse(Data(xml.utf8))
    }
}
