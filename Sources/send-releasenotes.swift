//
//  HTMLMessage.swift
//  SwiftSendmail
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

// project=GOAPPTV AND status in ('Open','In Development','PR Approved Ready for QA') ORDER BY issuetype,assignee

struct HTMLReport: SwiftHTML, CustomStringConvertible {
    typealias IssueGroups = [String: [Issue]]
    
    let issueGroups: IssueGroups
    
    var description: String {
        return String(describing: HTML(
            head([
                node("meta", ["http-equiv" => "Content-Type", "content" => "text/html; charset=utf-8"], nil),
                node("title", "tvOS Release Notes"),
                node("style", ["type" => "text/css"], ["* {font-family: sans-serif;} ul {list-style: none;} li {margin: 1em 0;} img {vertical-align: top; width: 16px; height: 16px}"])
            ]),
            body([
                h1("tvOS Dev Complete Tickets")
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
    
    init(issueGroups: IssueGroups) {
        self.issueGroups = issueGroups
    }
}

Logger.loggingLevel = .debug

let arguments = Moderator(description: "Search JIRA and send release notes to specified recipients")

let host = arguments.add(Argument<String>
    .optionWithValue("h", name: "host", description: "The host to Jira")
    .default("tickets.turner.com")
    //    .required()
)
let jql = arguments.add(Argument<String>
    .optionWithValue("j", name: "jql", description: "Jira JQL query")
    .default("project = GOAPPTV AND status in (Open, Done, 'In Development', 'PR Approved Ready for QA') AND Sprint = 7569 ORDER BY issuetype, assignee")
    //    .required()
)
let version = arguments.add(Argument<String>
    .optionWithValue("v", name: "version", description: "Build version")
    .default("2.3")
    //    .required()
)
let build = arguments.add(Argument<String>
    .optionWithValue("b", name: "build", description: "Build number")
    .default("2017.9.12.NNNNNN")
    //    .required()
)
let verbose = arguments.add(Argument<Bool>.option("verbose"))

do {
    try arguments.parse()
} catch {
    Logger.error("Unable to parse args:", error)
    exit(Int32(error._code))
}

let semaphore = DispatchSemaphore(value: 0)

let jira = Jira(host: host.value)
jira.search(query: jql.value) { (data, error) in
    guard error == nil else {
        Logger.error(error)
        exit(Int32(error!._code))
    }
    
    guard let data = data else {
        Logger.error("no data")
        exit(1)
    }
    
    guard let json = try! JSONSerialization.jsonObject(with: data) as? [AnyHashable: Any] else {
        Logger.error("unable to convert data to JSON")
        exit(1)
    }
    
    guard let issuesJson = json["issues"] as? [JSON] else {
        Logger.error("cannot parse errors")
        exit(1)
    }
    
    let issues = issuesJson.flatMap { Issue(issue: $0) }
    guard issues.count == issuesJson.count else {
        Logger.error("Some issues could not be mapped")
        exit(1)
    }
    
    let from = "noreply@cnnxcodeserver.com"
    let to = ["kyle.watson@turner.com"]
    let subject = "tvOS \(version.value) Build (\(build.value))"
    let html = HTMLReport(issueGroups: issues.group { $0.type.name })
    let message = HTMLMessage(sender: from, recipients: to, subject: subject, body: String(describing: html))
    
    Logger.debug(String(describing: html))
    print()
    Logger.debug(String(describing: message))
    let sendmail = Sendmail()
    sendmail.send(message: message)
    
    _ = semaphore.signal()
}

semaphore.wait()
