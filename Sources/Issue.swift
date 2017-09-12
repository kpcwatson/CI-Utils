//
//  Issue.swift
//  CI-Utils
//
//  Created by Kyle Watson on 9/11/17.
//
//

import Foundation

typealias JSON = [AnyHashable: Any]

extension Sequence {
    func group<GroupingType: Hashable>(by key: (Iterator.Element) -> GroupingType) -> [GroupingType: [Iterator.Element]] {
        var groups: [GroupingType: [Iterator.Element]] = [:]
        forEach { element in
            let key = key(element)
            if case nil = groups[key]?.append(element) {
                groups[key] = [element]
            }
        }
        return groups
    }
}

struct IssueType {
    let name: String
    let imageHref: String
    
    init?(fields: JSON) {
        guard let type = fields["issuetype"] as? JSON,
            let name = type["name"] as? String,
            let imageHref = type["iconUrl"] as? String
            else {
                return nil
        }
        
        self.name = name
        self.imageHref = imageHref
    }
}

struct IssueReporter {
    let name: String
    let imageHref: String
    
    init?(fields: JSON) {
        guard let reporter = fields["reporter"] as? JSON,
            let name = reporter["displayName"] as? String,
            let avatar = reporter["avatarUrls"] as? JSON,
            let imageHref = avatar["16x16"] as? String
            else {
                return nil
        }
        
        self.name = name
        self.imageHref = imageHref
    }
}

struct IssueAssignee {
    let name: String
    let imageHref: String
    
    init?(fields: JSON) {
        guard let assignee = fields["assignee"] as? JSON,
            let name = assignee["displayName"] as? String,
            let avatar = assignee["avatarUrls"] as? JSON,
            let imageHref = avatar["16x16"] as? String
            else {
                return nil
        }
        
        self.name = name
        self.imageHref = imageHref
    }
}

struct IssuePriority {
    let name: String
    let imageHref: String
    
    init?(fields: JSON) {
        guard let priority = fields["priority"] as? JSON,
            let name = priority["name"] as? String,
            let imageHref = priority["iconUrl"] as? String
            else {
                return nil
        }
        
        self.name = name
        self.imageHref = imageHref
    }
}

struct Issue {
    let key: String
    let summary: String
    let fixVersion: String
    let updated: String
    let type: IssueType
    let reporter: IssueReporter
    let assignee: IssueAssignee?
    let priority: IssuePriority
    
    init?(issue: JSON) {
        guard let key = issue["key"] as? String,
            let fields = issue["fields"] as? JSON
            else {
                return nil
        }
        
        self.key = key
        
        guard let summary = fields["summary"] as? String,
            let updated = fields["updated"] as? String,
            let fixVersions = fields["fixVersions"] as? [JSON],
            let fixVersion = fixVersions.first?["name"] as? String
            else {
                return nil
        }
        
        self.summary = summary
        self.updated = updated
        self.fixVersion = fixVersion
        
        guard let type = IssueType(fields: fields),
            let reporter = IssueReporter(fields: fields),
            let priority = IssuePriority(fields: fields) else {
                return nil
        }
        
        self.type = type
        self.reporter = reporter
        self.priority = priority
        self.assignee = IssueAssignee(fields: fields)
    }
}
