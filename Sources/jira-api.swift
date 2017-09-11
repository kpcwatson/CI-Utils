//
//  jira-api.swift
//  CI-Utils
//
//  Created by Kyle Watson on 9/7/17.
//
//

import Foundation
import SwiftLogger

// project = GOAPPTV AND status = "PR Approved Ready for QA" ORDER BY issuetype
// project = GOAPPTV AND status in (Open, "PR Approved Ready for QA") AND assignee in (kwatson) ORDER BY issuetype,assignee

public typealias SearchCompletion = (Data?, Error?) -> Void
open class Jira {
    
    static let defaultUrlSession: URLSession = {
        return URLSession(configuration: URLSessionConfiguration.default)
    }()
    
    let host: String
    let version: Int
    let urlSession: URLSession
    
    public init(host: String, version: Int = 2, urlSession: URLSession = defaultUrlSession) {
        self.host = host
        self.version = version
        self.urlSession = urlSession
    }
    
    public func search(query: JQLQuery, fields: [String]? = nil, completion: @escaping SearchCompletion) {
        search(query: query.queryString, fields: fields, completion: completion)
    }
    
    public func search(query: String, fields: [String]? = nil, completion: @escaping SearchCompletion) {
        
        var queryParams = ["jql": query]
        if let fields = fields {
            queryParams["fields"] = fields.joined(separator: ",")
        }
        
        var request: URLRequest
        do {
            request = try JiraRequestBuilder(host: host, version: version, endpointMethod: "search")
                .queryParameters(queryParams)
                .build()
        } catch {
            Logger.error(self, error)
            completion(nil, error)
            return
        }
        
        urlSession.dataTask(with: request) { (data, response, error) in
            if let response = response as? HTTPURLResponse {
                Logger.debug(self, "HTTP status code \(response.statusCode)")
            }
            
            completion(data, error)
        }
    }
}

public enum JiraError: Error {
    case unableToConstructURL(host: String?, path: String?)
}

public class JiraRequestBuilder {
    
    let host: String
    let version: String
    let endpointMethod: String
    var httpMethod: String?
    var queryItems: [URLQueryItem]?
    var postParams: [String]?
    var timeout: TimeInterval?
    
    public init(host: String, version: Int, endpointMethod: String) {
        self.host = host
        self.version = String(version)
        self.endpointMethod = endpointMethod
    }
    
    public func httpMethod(_ method: String) -> JiraRequestBuilder {
        httpMethod = method
        return self
    }
    
    public func queryParameters(_ params: [String: String]) -> JiraRequestBuilder {
        queryItems = params.flatMap { URLQueryItem(name: $0.key, value: $0.value) }
        return self
    }
    
    public func postParameters(_ params: [String: String]) -> JiraRequestBuilder {
        
        var pairs = [String]()
        params.forEach { (key, value) in
            let pair = key + "=" + value
            pairs.append(pair)
        }
        postParams = pairs
        
        return self
    }
    
    public func timeout(_ timeout: TimeInterval) -> JiraRequestBuilder {
        self.timeout = timeout
        return self
    }
    
    public func build() throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.path = "/rest/api/\(version)/\(endpointMethod)"
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw JiraError.unableToConstructURL(host: components.host, path: components.path)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.httpBody = postParams?.joined(separator: "&")
            .data(using: .utf8)
        
        if let timeout = timeout {
            request.timeoutInterval = timeout
        }
        
        Logger.debug(self, "built URLRequest:", request)
        
        return request
    }
}

public struct JQLQuery {

    public let clauses: [JQLClause]
    
    public init(whereClause: JQLClause, orderClause: JQLClause?) {
        var clauses = [whereClause]
        
        if let orderClause = orderClause {
            clauses.append(orderClause)
        }
        
        self.init(clauses: clauses)
    }
    
    public init(clauses: [JQLClause]) {
        self.clauses = clauses
    }
    
    public var queryString: String {
        return clauses.joined(separator: " ")
    }
}

public typealias JQLClause = String

open class SimpleJQLQueryBuilder {
    
    var expressions = [JQLExpression]()
    var orderBy: JQLClause?
    
    public func expression(_ expression: JQLExpression) -> SimpleJQLQueryBuilder {
        expressions.append(expression)
        return self
    }
    
    // MARK: Project
    
    public func project(_ project: String) -> SimpleJQLQueryBuilder {
        let expression = JQLExpression(field: "project", operator: .equals, value: project)
        expressions.append(expression)
        return self
    }
    
    // MARK: Type
    
    public func type(_ op: JQLOperator, _ types: [String]) -> SimpleJQLQueryBuilder {
        let expression = JQLExpression(field: "type", operator: op, values: types)
        expressions.append(expression)
        return self
    }
    
    public func type(_ op: JQLOperator, _ type: String) -> SimpleJQLQueryBuilder {
        let expression = JQLExpression(field: "type", operator: op, value: type)
        expressions.append(expression)
        return self
    }
    
    // MARK: Status
    
    public func status(_ op: JQLOperator, _ statuses: [String]) -> SimpleJQLQueryBuilder {
        let expression = JQLExpression(field: "status", operator: op, values: statuses)
        expressions.append(expression)
        return self
    }
    
    public func status(_ op: JQLOperator, _ status: String) -> SimpleJQLQueryBuilder {
        let expression = JQLExpression(field: "status", operator: op, value: status)
        expressions.append(expression)
        return self
    }
    
    // MARK: Text
    
    public func text(contains text: String) -> SimpleJQLQueryBuilder {
        let expression = JQLExpression(field: "text", operator: .contains, value: text)
        expressions.append(expression)
        return self
    }
    
    // MARK: Assignee
    
    public func assignee(_ op: JQLOperator, _ assignees: [String]) -> SimpleJQLQueryBuilder {
        let expression = JQLExpression(field: "assignee", operator: op, values: assignees)
        expressions.append(expression)
        return self
    }
    
    public func assignee(_ op: JQLOperator, _ assignee: String) -> SimpleJQLQueryBuilder {
        let expression = JQLExpression(field: "assignee", operator: op, value: assignee)
        expressions.append(expression)
        return self
    }
    
    // MARK: Fix Version
    
    public func fixVersion(_ op: JQLOperator, _ versions: [String]) -> SimpleJQLQueryBuilder {
        let expression = JQLExpression(field: "fixVersion", operator: op, values: versions)
        expressions.append(expression)
        return self
    }
    
    public func fixVersion(_ op: JQLOperator, _ version: String) -> SimpleJQLQueryBuilder {
        let expression = JQLExpression(field: "fixVersion", operator: op, value: version)
        expressions.append(expression)
        return self
    }
    
    // MARK: Order By
    
    public func order(by fields: [String]) -> SimpleJQLQueryBuilder {
        orderBy = "ORDER BY " + fields.joined(separator: ", ")
        return self
    }
    
    // MARK: Build
    
    public func build() -> JQLQuery {
        let whereClause = expressions.flatMap { String(describing: $0) }
            .joined(separator: " AND ")
        return JQLQuery(whereClause: whereClause, orderClause: orderBy)
    }
}

public struct JQLExpression: CustomStringConvertible {
    
    let field: String
    let op: JQLOperator
    let values: [String]
    
    public init(field: String, operator op: JQLOperator, values: [String]) {
        self.field = field
        self.op = op
        self.values = values.flatMap { "'\($0)'" }
    }
    
    public init(field: String, operator op: JQLOperator, value: String) {
        self.init(field: field, operator: op, values: [value])
    }
    
    public var description: String {
        var expression: [String] = [field, op.rawValue]
        
        switch op {
        case .in, .notIn:
            expression.append("(" + values.joined(separator: ",") + ")")
            
        case .equals, .nequals, .contains, .ncontains:
            expression += values
        }
        
        return expression.joined(separator: " ")
    }
}

public enum JQLOperator: String {
    case equals = "="
    case nequals = "!="
    case `in` = "IN"
    case notIn = "NOT IN"
    case contains = "~"
    case ncontains = "!~"
}
