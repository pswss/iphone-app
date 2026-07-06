//
//  Live_ActLiveActivity.swift
//  Live Act
//
//  Created by 표상우 on 7/5/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct Live_ActAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct Live_ActLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: Live_ActAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension Live_ActAttributes {
    fileprivate static var preview: Live_ActAttributes {
        Live_ActAttributes(name: "World")
    }
}

extension Live_ActAttributes.ContentState {
    fileprivate static var smiley: Live_ActAttributes.ContentState {
        Live_ActAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: Live_ActAttributes.ContentState {
         Live_ActAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: Live_ActAttributes.preview) {
   Live_ActLiveActivity()
} contentStates: {
    Live_ActAttributes.ContentState.smiley
    Live_ActAttributes.ContentState.starEyes
}
