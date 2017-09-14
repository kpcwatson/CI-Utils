//
//  send-releasenotes.swift
//  CI-Utils
//
//  Created by Kyle Watson on 9/11/17.
//
//

import Foundation
import Moderator
import JiraKit
import SwiftSendmail
import SwiftLogger
import SwiftHTML
import SwiftShell
import Unbox

class SharedArray<T> {
    var storage: [T] = []
    init(_ items: [T]) {
        self.storage = items
    }
}

extension Sequence {
    func group<GroupingType: Hashable>(by condition: (Iterator.Element) -> GroupingType) -> [GroupingType: [Iterator.Element]] {
        var groups: [GroupingType: SharedArray<Iterator.Element>] = [:]
        for item in self {
            let key = condition(item)
            if case nil = groups[key]?.storage.append(item) {
                groups[key] = SharedArray([item])
            }
        }
        var result: [GroupingType: [Iterator.Element]] = [:]
        groups.forEach { result[$0] = $1.storage }
        return result
    }
}

struct Issue {
    let type: String
    let key: String
    let summary: String
    let priority: String
    let fixVersion: String
    let reporter: String
    let assignee: String?
    let updated: Date
}

extension Issue: Unboxable {
    init(unboxer: Unboxer) throws {
        self.type = try unboxer.unbox(keyPath: "fields.issuetype.name")
        self.key = try unboxer.unbox(key: "key")
        self.summary = try unboxer.unbox(keyPath: "fields.summary")
        self.priority = try unboxer.unbox(keyPath: "fields.priority.name")
        self.fixVersion = try unboxer.unbox(keyPath: "fields.fixVersions.0.name")
        self.reporter = try unboxer.unbox(keyPath: "fields.reporter.displayName")
        self.assignee = unboxer.unbox(keyPath: "fields.assignee.displayName")
        self.updated = try unboxer.unbox(keyPath: "fields.updated", formatter: DateFormatters.raw)
    }
}

struct DateFormatters {
    static var raw: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()
    
    static var readable: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy h:mm a"
        return formatter
    }()
}

struct HTMLReport: SwiftHTML {
    typealias IssueGroups = [String: [Issue]]
    
    let heading: String
    let issueGroups: IssueGroups
    
    init(heading: String, issueGroups: IssueGroups) {
        self.heading = heading
        self.issueGroups = issueGroups
    }
}

extension HTMLReport: CustomStringConvertible {
    var description: String {
        return String(describing: HTML(
            head([
                node("style", ["type" => "text/css"], ["\n* {font-family: sans-serif;} \nul {list-style: none;} \nli {margin: 1em 0;} \nh3 {margin: .2em 0;}"])
            ]),
            body([
                h1(.text(heading)),
                div([strong("Note: "), "This build is processing and should be available shortly"])
            ] + nodes))
        )
    }
    
    private var nodes: [Node] {
        return issueGroups.flatMap { (type, issues) in
            return div([
                h2(.text(issues.count > 1 ? "\(type)s" : type)),
                ul(issues.flatMap{ issue in
                    return li([
                        node("h3", [a([href => "http://tickets.turner.com/browse/\(issue.key)"], .text(issue.key)), .text(" - \(issue.summary)")]),
                        div([strong("Priority: "), .text(issue.priority)]),
                        div([strong("Fix Version: "), .text(issue.fixVersion)]),
                        div([strong("Reported By: "), .text(issue.reporter)]),
                        issue.assignee != nil ? div([strong("Assigned To: "), .text(issue.assignee ?? "n/a")]) : div([]),
                        div([strong("Updated: "), .text(DateFormatters.readable.string(from: issue.updated))])
                    ])
                })
            ])
        }
    }
}

// specify args
let arguments = Moderator(description: "Search JIRA and send release notes to specified recipients")

let host = arguments.add(Argument<String>
    .optionWithValue("h", "host", name: "host", description: "The host to Jira")
    .required()
)
let jql = arguments.add(Argument<String>
    .optionWithValue("jql", name: "query", description: "Jira JQL query")
    .required()
)
let type = arguments.add(Argument<String>
    .optionWithValue("type", name: "build type", description: "Build type (QA, RC, etc.)")
    .required()
)
let version = arguments.add(Argument<String>
    .optionWithValue("v", "version", name: "version", description: "Build version")
    .required()
)
let build = arguments.add(Argument<String>
    .optionWithValue("b", "build", name: "build", description: "Build number")
    .required()
)
let pathToRecipients = arguments.add(Argument<String>
    .optionWithValue("recipients", name: "path", description: "Path to recipients file")
    .required()
)

// parse args
do {
    try arguments.parse()
} catch {
    Logger.error("Unable to parse args:", error)
    exit(Int32(error._code))
}

// parse recipients from file
let recipients = { () -> [String] in
    do {
        return try open(pathToRecipients.value)
            .lines()
            .flatMap { $0 }
    } catch {
        Logger.error(error)
        exit(Int32(error._code))
    }
}()

let semaphore = DispatchSemaphore(value: 0)

// perform jira search
let jira = Jira(host: host.value)
jira.search(query: jql.value) { (data, error) in
    guard error == nil else {
        Logger.error(error)
        exit(Int32(error!._code))
    }
    
    guard let data = data,
        let json = try! JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            Logger.error("unable to decode json data")
            exit(1)
    }
    
    // decode JSON to array of `Issue`s
    let issues: [Issue]
    do {
        issues = try unbox(dictionary: json, atKey: "issues")
    } catch {
        Logger.error("unboxing error", error)
        exit(Int32(error._code))
    }
    
    // if no issues to send, then exit without error
    guard issues.count > 0 else {
        Logger.info("nothing to send, exiting")
        exit(0)
    }
    
    // build HTMLMessage
    let from = "CNNgo tvOS Build Server <noreply@cnnxcodeserver.com>"
    let buildType = type.value.uppercased()
    let subject = "tvOS \(buildType) Build \(version.value) (\(build.value))"
    let heading = subject + " " + (buildType == "RC" ? "Tickets in This Release" : "Tickets Ready for QA")
    let html = HTMLReport(heading: heading, issueGroups: issues.group { $0.type })
    let message = HTMLMessage(sender: from, recipients: recipients, subject: subject, body: String(describing: html))
    
    // send email using `sendmail`
    let sendmail = Sendmail()
    sendmail.send(message: message)
    
    // signal semaphore, increment count
    _ = semaphore.signal()
}

// semaphore so script does not exit before completing
semaphore.wait()
