//
//  Resource.swift
//  CanvasKit
//
//  Created by Sam Soffes on 7/11/16.
//  Copyright © 2016 Canvas Labs, Inc. All rights reserved.
//

import Foundation
import ISO8601

typealias Attributes = [String: AnyObject]
typealias Includes = [ResourceType: [String: Resource]]
typealias ResourceIdentifiers = [String: AnyObject]

protocol Resource {
	var id: String { get }
	init(data: ResourceData) throws
}


enum ResourceType: String {
	case organization = "orgs"
	case canvas = "canvases"
	case account = "account"
	case accessToken = "access-tokens"

	var resource: Resource.Type {
		switch self {
		case .organization: return Organization.self
		case .canvas: return Canvas.self
		case .account: return Account.self
		case .accessToken: return AccessToken.self
		}
	}
}


enum ResourceError: ErrorType {
	case invalidAttribute(String)
	case missingAttribute(String)
	case missingInclude(String, ResourceIdentifier)
	case missingResourceIdentifier(String)
}

struct ResourceIdentifier {
	let id: String
	let type: ResourceType
	
	init?(dictionary: JSONDictionary) {
		guard let data = dictionary["data"] as? JSONDictionary,
			id = data["id"] as? String,
			type = (data["type"] as? String).flatMap(ResourceType.init)
		else { return nil }
		
		self.id = id
		self.type = type
	}
}


struct ResourceData {
	let type: ResourceType
	let id: String
	let attributes: JSONDictionary
	let relationships: [String: ResourceIdentifier]?
	let includes: Includes?
	let meta: JSONDictionary?
	
	init?(dictionary: JSONDictionary, includes: Includes?, meta: JSONDictionary?) {
		guard let id = dictionary["id"] as? String,
			type = (dictionary["type"] as? String).flatMap(ResourceType.init),
			attributes = dictionary["attributes"] as? JSONDictionary
		else { return nil }
		
		self.id = id
		self.type = type
		self.attributes = attributes
		self.meta = meta
		
		if let rels = dictionary["relationships"] as? [String: JSONDictionary] {
			var relationships = [String: ResourceIdentifier]()
			for (key, dictionary) in rels {
				guard let relationship = ResourceIdentifier(dictionary: dictionary) else { continue }
				relationships[key] = relationship
			}
			self.relationships = relationships
		} else {
			relationships = nil
		}
		
		self.includes = includes
	}
	
	func decode<T>(attribute key: String) throws -> T {
		guard let attribute = attributes[key] as? T else {
			throw ResourceError.missingAttribute(key)
		}
		return attribute
	}
	
	func decode<T>(attribute key: String) -> T? {
		return attributes[key] as? T
	}
	
	func decode(attribute key: String) throws -> NSDate {
		guard let iso8601 = attributes[key] as? String,
			date = NSDate(ISO8601String: iso8601)
			else {
				throw ResourceError.missingAttribute(key)
		}
		return date
	}
	
	func decode(attribute key: String) -> NSDate? {
		let iso8601 = attributes[key] as? String
		return iso8601.flatMap { NSDate(ISO8601String: $0) }
	}
	
	func decode<T>(relationship key: String) throws -> T {
		guard let relationship = relationships?[key] else {
			throw ResourceError.missingResourceIdentifier(key)
		}
		
		guard let resource = includes?[relationship.type]?[relationship.id] as? T else {
			throw ResourceError.missingInclude(key, relationship)
		}
		
		return resource
	}
}


struct ResourceSerialization {
	private static func includes(dictionary: JSONDictionary) -> Includes? {
		guard let array = dictionary["included"] as? [JSONDictionary] else { return nil }
		var includes = Includes()
		
		for dictionary in array {
			guard let type = (dictionary["type"] as? String).flatMap(ResourceType.init),
				resourceData = ResourceData(dictionary: dictionary, includes: nil, meta: nil),
				resource = unpack(resourceData: resourceData)
			else { continue }
			
			if includes[type] == nil {
				includes[type] = [:]
			}
			
			includes[type]?[resource.id] = resource
		}
		
		return includes
	}
	
	static func deserialize<T: Resource>(dictionary dictionary: JSONDictionary) -> [T]? {
		guard let datas = dictionary["data"] as? [JSONDictionary] else { return nil }
		
		let includes = self.includes(dictionary)
		let meta = dictionary["meta"] as? JSONDictionary
		
		return datas.flatMap { data in
			guard let resourceData = ResourceData(dictionary: data, includes: includes, meta: meta),
				resource = try? resourceData.type.resource.init(data: resourceData)
			else { return nil }
			
			return resource as? T
		}
	}
	
	static func deserialize<T: Resource>(dictionary dictionary: JSONDictionary) -> T? {
		guard let data = dictionary["data"] as? JSONDictionary else { return nil }

		let includes = self.includes(dictionary)
		let meta = dictionary["meta"] as? JSONDictionary

		guard let resourceData = ResourceData(dictionary: data, includes: includes, meta: meta) else { return nil }

		return unpack(resourceData: resourceData) as? T
	}

	private static func unpack(resourceData resourceData: ResourceData) -> Resource? {
		let resource: Resource

		do {
			resource = try resourceData.type.resource.init(data: resourceData)
		} catch ResourceError.invalidAttribute(let key) {
			print("[CanvasKit] Failed to unpack \(resourceData.type): Invalid `\(key)` attribute.")
			return nil
		} catch ResourceError.missingAttribute(let key) {
			print("[CanvasKit] Failed to unpack \(resourceData.type): Missing `\(key)` attribute.")
			return nil
		} catch ResourceError.missingInclude(let key, let identifier) {
			print("[CanvasKit] Failed to unpack \(resourceData.type): Missing relationship `\(key)`. Expected \(identifier).")
			return nil
		} catch ResourceError.missingResourceIdentifier(let key) {
			print("[CanvasKit] Failed to unpack \(resourceData.type): Missing resource identifier for relationship `\(key)`.")
			return nil
		} catch {
			print("[CanvasKit] Failed to unpack \(resourceData.type): Unknown error")
			return nil
		}

		return resource
	}
}
