import Foundation

/// A generator that creates a JSON schema from any `Codable` type.
internal enum JSONSchemaGenerator {
    static func generateSchema(for type: Any.Type) throws -> OpenAI.JSONSchema {
        guard let codableType = type as? Codable.Type else {
            throw SchemaError.notCodable("Type \(type) does not conform to Codable for schema generation.")
        }
        
        let schemaEncoder = SchemaEncoder()
        let fakeInstance = try codableType.init(from: FakeDecoder())
        try fakeInstance.encode(to: schemaEncoder)

        return schemaEncoder.schema
    }
    
    enum SchemaError: Error {
        case notCodable(String)
        case unsupportedType(String)
    }
}

// MARK: - Schema Encoder
private class SchemaEncoder: Encoder {
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]
    var schema = OpenAI.JSONSchema(type: "object")

    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        return KeyedEncodingContainer(SchemaKeyedEncodingContainer<Key>(encoder: self, codingPath: codingPath))
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        return SchemaUnkeyedEncodingContainer(encoder: self, codingPath: codingPath)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        return SchemaSingleValueEncodingContainer(encoder: self, codingPath: codingPath)
    }
}

// MARK: - Keyed Container
private struct SchemaKeyedEncodingContainer<K: CodingKey>: KeyedEncodingContainerProtocol {
    typealias Key = K
    var codingPath: [CodingKey]
    private let encoder: SchemaEncoder

    init(encoder: SchemaEncoder, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
        self.encoder.schema.properties = self.encoder.schema.properties ?? [:]
        self.encoder.schema.required = self.encoder.schema.required ?? []
    }

    mutating func encodeNil(forKey key: K) throws { /* Optional: do nothing */ }
    
    mutating func encode<T>(_ value: T, forKey key: K) throws where T: Encodable {
        let propertyEncoder = SchemaEncoder()
        try value.encode(to: propertyEncoder)
        
        encoder.schema.properties?[key.stringValue] = propertyEncoder.schema
        if !(value is ExpressibleByNilLiteral) {
             encoder.schema.required?.append(key.stringValue)
        }
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: K) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let newEncoder = SchemaEncoder()
        encoder.schema.properties?[key.stringValue] = newEncoder.schema
        encoder.schema.required?.append(key.stringValue)
        return newEncoder.container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer(forKey key: K) -> UnkeyedEncodingContainer {
        let newEncoder = SchemaEncoder()
        newEncoder.schema.type = "array"
        encoder.schema.properties?[key.stringValue] = newEncoder.schema
        encoder.schema.required?.append(key.stringValue)
        return newEncoder.unkeyedContainer()
    }

    mutating func superEncoder() -> Encoder { encoder }
    mutating func superEncoder(forKey key: K) -> Encoder { encoder }
}

// MARK: - Unkeyed Container
private struct SchemaUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    var codingPath: [CodingKey]
    private let encoder: SchemaEncoder
    var count: Int = 0

    init(encoder: SchemaEncoder, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
    }

    mutating func encode<T>(_ value: T) throws where T: Encodable {
        guard count == 0 else { return }
        let itemEncoder = SchemaEncoder()
        try value.encode(to: itemEncoder)
        encoder.schema.items = itemEncoder.schema
        count += 1
    }

    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let itemEncoder = SchemaEncoder()
        encoder.schema.items = itemEncoder.schema
        count += 1
        return itemEncoder.container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let itemEncoder = SchemaEncoder()
        itemEncoder.schema.type = "array"
        encoder.schema.items = itemEncoder.schema
        count += 1
        return itemEncoder.unkeyedContainer()
    }
    
    mutating func encodeNil() throws { /* Optional, do nothing */ }
    mutating func superEncoder() -> Encoder { encoder }
}

// MARK: - Single Value Container
private struct SchemaSingleValueEncodingContainer: SingleValueEncodingContainer {
    var codingPath: [CodingKey]
    private let encoder: SchemaEncoder

    init(encoder: SchemaEncoder, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
    }
    
    mutating func encodeNil() throws { /* Optional */ }
    mutating func encode(_ value: Bool) throws { encoder.schema = .init(type: "boolean") }
    mutating func encode(_ value: String) throws { encoder.schema = .init(type: "string") }
    mutating func encode(_ value: Double) throws { encoder.schema = .init(type: "number") }
    mutating func encode(_ value: Float) throws { encoder.schema = .init(type: "number") }
    mutating func encode(_ value: Int) throws { encoder.schema = .init(type: "integer") }
    mutating func encode(_ value: Int8) throws { encoder.schema = .init(type: "integer") }
    mutating func encode(_ value: Int16) throws { encoder.schema = .init(type: "integer") }
    mutating func encode(_ value: Int32) throws { encoder.schema = .init(type: "integer") }
    mutating func encode(_ value: Int64) throws { encoder.schema = .init(type: "integer") }
    mutating func encode(_ value: UInt) throws { encoder.schema = .init(type: "integer") }
    mutating func encode(_ value: UInt8) throws { encoder.schema = .init(type: "integer") }
    mutating func encode(_ value: UInt16) throws { encoder.schema = .init(type: "integer") }
    mutating func encode(_ value: UInt32) throws { encoder.schema = .init(type: "integer") }
    mutating func encode(_ value: UInt64) throws { encoder.schema = .init(type: "integer") }
    
    mutating func encode<T>(_ value: T) throws where T : Encodable {
        try value.encode(to: encoder)
    }
}

// MARK: - Fake Decoder (Corrected)

private class FakeDecoder: Decoder {
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey : Any] = [:]
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> { .init(FakeKeyedContainer()) }
    func unkeyedContainer() throws -> UnkeyedDecodingContainer { FakeUnkeyedContainer() }
    func singleValueContainer() throws -> SingleValueDecodingContainer { FakeSingleValueContainer() }
}

private struct FakeKeyedContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
    var codingPath: [CodingKey] = []
    var allKeys: [K] = []
    func contains(_ key: K) -> Bool { true }
    func decodeNil(forKey key: K) throws -> Bool { true }
    
    func decode<T>(_ type: T.Type, forKey key: K) throws -> T where T : Decodable {
        // Stop recursion for primitive types
        if type == String.self { return "" as! T }
        if type == Int.self { return 0 as! T }
        if type == Double.self { return 0.0 as! T }
        if type == Bool.self { return false as! T }
        
        // For complex/nested types, recurse with another fake decoder.
        return try T(from: FakeDecoder())
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: K) throws -> KeyedDecodingContainer<NestedKey> { .init(FakeKeyedContainer<NestedKey>()) }
    func nestedUnkeyedContainer(forKey key: K) throws -> UnkeyedDecodingContainer { FakeUnkeyedContainer() }
    func superDecoder() throws -> Decoder { FakeDecoder() }
    func superDecoder(forKey key: K) throws -> Decoder { FakeDecoder() }
}

private struct FakeUnkeyedContainer: UnkeyedDecodingContainer {
    var codingPath: [CodingKey] = []
    var count: Int? = 1
    var isAtEnd: Bool = false
    var currentIndex: Int = 0
    mutating func decodeNil() throws -> Bool { true }
    
    mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        // Similar to other containers, stop recursion for primitives.
        if type == String.self { return "" as! T }
        if type == Int.self { return 0 as! T }
        if type == Double.self { return 0.0 as! T }
        if type == Bool.self { return false as! T }
        
        currentIndex += 1
        return try T(from: FakeDecoder())
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> { .init(FakeKeyedContainer()) }
    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer { self }
    mutating func superDecoder() throws -> Decoder { FakeDecoder() }
}

private struct FakeSingleValueContainer: SingleValueDecodingContainer {
    var codingPath: [CodingKey] = []
    func decodeNil() -> Bool { true }
    
    func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        // This is the critical fix: stop the recursion for primitives.
        if type == String.self { return "" as! T }
        if type == Int.self { return 0 as! T }
        if type == Double.self { return 0.0 as! T }
        if type == Bool.self { return false as! T }

        // Only recurse for non-primitive, complex types.
        return try T(from: FakeDecoder())
    }
}