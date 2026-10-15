import XCTest

final class ClassCreateRequestTests: XCTestCase {
    private func body(_ description: String?) throws -> [String: Any] {
        let data = try JSONEncoder().encode(ClassCreateRequest(name: "Physics", description: description))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testAbsentDescriptionsAreOmittedRatherThanNull() throws {
        for description: String? in [nil, "", "   ", "\t\n\r "] {
            let json = try body(description)
            XCTAssertEqual(json["name"] as? String, "Physics")
            XCTAssertFalse(json.keys.contains("description"), "Blank descriptions must not be encoded, even as null")
        }
    }

    func testNonemptyDescriptionIsPreservedExactly() throws {
        let description = "  Synthetic physics lesson\n"
        XCTAssertEqual(try body(description)["description"] as? String, description)
    }
}
