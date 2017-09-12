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

struct HTMLReport: SwiftHTML, CustomStringConvertible {
    typealias IssueGroups = [String: [Issue]]
    
    let version: String
    let build: String
    let issueGroups: IssueGroups
    
    var description: String {
        return String(describing: HTML(
            head([
                node("style", ["type" => "text/css"], ["\n* {font-family: sans-serif;}\n ul {list-style: none;}\n li {margin: 1em 0;}\n img {vertical-align: top; width: 16px; height: 16px}\n"])
            ]),
            body([
                h1(.text("tvOS \(version) (\(build)) Dev Complete Tickets")),
                div([strong("Note: "), "This build is processing and should be available shortly"])
            ] + nodes))
        )
    }
    
    private var nodes: [Node] {
        return issueGroups.flatMap { (type, issues) -> Node in
            return div([
                h2(.text(type)),
                ul(issues.flatMap({ (issue) -> Node in
                    return li([
                        div([strong("Ticket: "), a([href => "http://tickets.turner.com/browse/\(issue.key)"], .text(issue.key)), " - ", .text(issue.summary)]),
                        div([strong("Fix Version: "), .text(issue.fixVersion)]),
                        div([strong("Reported By: "), img([src => issue.reporter.imageHref]), .text(issue.reporter.name)]),
                        div([strong("Priority: "), img([src => issue.priority.imageHref]), .text(issue.priority.name)]),
                        issue.assignee != nil ? div([strong("Assigned To: "), img([src => issue.assignee!.imageHref]), .text(issue.assignee!.name)]) : div([]),
                        div([strong("Updated: "), .text(issue.updated)])
                    ])
                }))
            ])
        }
    }
    
    init(version: String, build: String, issueGroups: IssueGroups) {
        self.version = version
        self.build = build
        self.issueGroups = issueGroups
    }
}

// specify args
let arguments = Moderator(description: "Search JIRA and send release notes to specified recipients")

let host = arguments.add(Argument<String>
    .optionWithValue("h", name: "host", description: "The host to Jira")
    .required()
)
let jql = arguments.add(Argument<String>
    .optionWithValue("j", name: "jql", description: "Jira JQL query")
    .required()
)
let version = arguments.add(Argument<String>
    .optionWithValue("v", name: "version", description: "Build version")
    .required()
)
let build = arguments.add(Argument<String>
    .optionWithValue("b", name: "build", description: "Build number")
    .required()
)
let pathToRecipients = arguments.add(Argument<String>
    .optionWithValue("r", name: "recipients", description: "Path to recipients file")
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
        let json = try! JSONSerialization.jsonObject(with: data) as? [AnyHashable: Any],
        let issuesJson = json["issues"] as? [JSON]
        else {
            Logger.error("error parsing JSON")
            exit(1)
    }
    
    // if no issues to send, then exit without error
    guard issuesJson.count > 0 else {
        Logger.info("nothing to send, exiting")
        exit(0)
    }
    
    // flatMap to an array of `Issue` objects, json mapping is done in `Issue`
    // flatMap excludes nils, ensure `issues` count matches `issuesJson` count
    let issues = issuesJson.flatMap { Issue(issue: $0) }
    guard issues.count == issuesJson.count else {
        Logger.error("Some issues could not be mapped")
        exit(1)
    }
    
    // build HTMLMessage
    let from = "noreply@cnnxcodeserver.com"
    let subject = "tvOS \(version.value) Build (\(build.value))"
    let html = HTMLReport(version: version.value, build: build.value, issueGroups: issues.group { $0.type.name })
    let message = HTMLMessage(sender: from, recipients: recipients, subject: subject, body: String(describing: html))
    
    // send email using `sendmail`
    let sendmail = Sendmail()
    sendmail.send(message: message)
    
    // signal semaphore, increment count
    _ = semaphore.signal()
}

// semaphore so script does not exit before completing
semaphore.wait()
